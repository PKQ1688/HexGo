use std::{
    collections::{HashMap, HashSet, VecDeque},
    fs::{self, OpenOptions},
    io::{self, Write},
    path::PathBuf,
    process::Stdio,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use anyhow::{anyhow, bail, Context, Result};
use async_trait::async_trait;
use clap::Parser;
use hexgo_core::{
    Action, ActionCodec, Coord, MatchEngine, Observation, Player, RulesConfig, ScoreBreakdown,
    ScoreTotals, ScoringMode,
};
use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::time::{sleep, timeout};
use tokio::{io::AsyncWriteExt, process::Command};

const DEFAULT_BASE_URL: &str = "https://api.openai.com/v1";
const DEFAULT_API_KEY_ENV: &str = "OPENAI_API_KEY";
const DEFAULT_TIMEOUT_SECONDS: u64 = 60;
const DEFAULT_MAX_RETRIES: usize = 2;
const DEFAULT_RETRY_BACKOFF_MS: u64 = 1500;
const DEFAULT_COMMAND_TIMEOUT_SECONDS: u64 = 3;
const DEFAULT_MAX_COMMAND_OUTPUT_BYTES: usize = 64 * 1024;

#[derive(Debug, Parser)]
#[command(
    author,
    version,
    about = "Run headless HexGo model and code-strategy evaluations."
)]
struct Cli {
    #[arg(long)]
    black_model: Option<String>,

    #[arg(long)]
    white_model: Option<String>,

    #[arg(long)]
    black_command: Option<String>,

    #[arg(long)]
    white_command: Option<String>,

    #[arg(long)]
    black_name: Option<String>,

    #[arg(long)]
    white_name: Option<String>,

    #[arg(long, default_value = DEFAULT_BASE_URL)]
    base_url: String,

    #[arg(long, default_value = DEFAULT_API_KEY_ENV)]
    api_key_env: String,

    #[arg(long, default_value_t = 2)]
    games: usize,

    #[arg(long, default_value_t = 3)]
    board_radius: i32,

    #[arg(long, default_value_t = 0)]
    max_turns: usize,

    #[arg(long, default_value_t = 0.2)]
    temperature: f32,

    #[arg(long, default_value_t = 256)]
    max_output_tokens: u32,

    #[arg(long, default_value_t = 8)]
    candidate_count: usize,

    #[arg(long, default_value_t = DEFAULT_TIMEOUT_SECONDS)]
    timeout_seconds: u64,

    #[arg(long, default_value_t = DEFAULT_MAX_RETRIES)]
    max_retries: usize,

    #[arg(long, default_value_t = DEFAULT_RETRY_BACKOFF_MS)]
    retry_backoff_ms: u64,

    #[arg(long, default_value_t = 0)]
    decision_retries: usize,

    #[arg(long, default_value_t = DEFAULT_RETRY_BACKOFF_MS)]
    decision_retry_backoff_ms: u64,

    #[arg(long, default_value_t = DEFAULT_COMMAND_TIMEOUT_SECONDS)]
    command_timeout_seconds: u64,

    #[arg(long, default_value_t = DEFAULT_MAX_COMMAND_OUTPUT_BYTES)]
    max_command_output_bytes: usize,

    #[arg(long)]
    replay_invalid_games: bool,

    #[arg(long, default_value_t = 5)]
    max_game_attempts: usize,

    #[arg(long)]
    json_response_format: bool,

    #[arg(long)]
    curl_client: bool,

    #[arg(long)]
    out: Option<PathBuf>,
}

#[derive(Debug, Clone)]
struct AgentConfig {
    kind: AgentKind,
    name: String,
    model: Option<String>,
    command: Option<String>,
    argv: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AgentKind {
    Model,
    Command,
}

impl AgentKind {
    const fn as_str(self) -> &'static str {
        match self {
            AgentKind::Model => "model",
            AgentKind::Command => "command",
        }
    }
}

impl AgentConfig {
    fn model(model: String, name: Option<String>) -> Self {
        Self {
            kind: AgentKind::Model,
            name: name.unwrap_or_else(|| model.clone()),
            model: Some(model),
            command: None,
            argv: Vec::new(),
        }
    }

    fn command(command: String, name: Option<String>) -> Result<Self> {
        let argv = parse_command_argv(&command)
            .with_context(|| format!("failed to parse command: {command}"))?;
        if argv.is_empty() {
            bail!("strategy command must not be empty");
        }
        Ok(Self {
            kind: AgentKind::Command,
            name: name.unwrap_or_else(|| command.clone()),
            model: None,
            command: Some(command),
            argv,
        })
    }

    fn display_name(&self) -> &str {
        &self.name
    }
}

#[derive(Debug, Clone)]
struct EvalConfig {
    black_agent: AgentConfig,
    white_agent: AgentConfig,
    command_timeout: Duration,
    max_command_output_bytes: usize,
    board_radius: i32,
    games: usize,
    max_turns: usize,
    replay_invalid_games: bool,
    max_game_attempts: usize,
    decision_retries: usize,
    decision_retry_backoff: Duration,
}

#[derive(Debug, Clone)]
struct OpenAiConfig {
    base_url: String,
    api_key: String,
    temperature: f32,
    max_output_tokens: u32,
    candidate_count: usize,
    timeout: Duration,
    max_retries: usize,
    retry_backoff: Duration,
    json_response_format: bool,
    curl_client: bool,
}

#[derive(Debug)]
struct ChatRequestError {
    message: String,
    retryable: bool,
}

impl std::fmt::Display for ChatRequestError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for ChatRequestError {}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
struct AgentDecision {
    action_index: usize,
    reason: String,
}

#[async_trait]
trait AgentClient: Send + Sync {
    async fn choose_action(
        &self,
        agent: &AgentConfig,
        player: Player,
        observation: &Observation,
    ) -> Result<AgentDecision>;
}

struct EvalAgentClient {
    openai: Option<OpenAiAgentClient>,
    command_timeout: Duration,
    max_command_output_bytes: usize,
}

#[async_trait]
impl AgentClient for EvalAgentClient {
    async fn choose_action(
        &self,
        agent: &AgentConfig,
        player: Player,
        observation: &Observation,
    ) -> Result<AgentDecision> {
        match agent.kind {
            AgentKind::Model => {
                let model = agent
                    .model
                    .as_deref()
                    .ok_or_else(|| anyhow!("model agent {} is missing model id", agent.name))?;
                let openai = self
                    .openai
                    .as_ref()
                    .ok_or_else(|| anyhow!("model agent requires OpenAI-compatible config"))?;
                openai.choose_model_action(model, player, observation).await
            }
            AgentKind::Command => {
                choose_command_action(
                    agent,
                    player,
                    observation,
                    self.command_timeout,
                    self.max_command_output_bytes,
                )
                .await
            }
        }
    }
}

struct OpenAiAgentClient {
    http: Client,
    config: OpenAiConfig,
}

impl OpenAiAgentClient {
    fn new(config: OpenAiConfig) -> Result<Self> {
        let http = Client::builder()
            .http1_only()
            .timeout(config.timeout)
            .build()
            .context("failed to build HTTP client")?;
        Ok(Self { http, config })
    }

    async fn send_chat_request(
        &self,
        endpoint: &str,
        request_body: &Value,
    ) -> std::result::Result<String, ChatRequestError> {
        if self.config.curl_client {
            return self
                .send_chat_request_with_curl(endpoint, request_body)
                .await;
        }

        let response = self
            .http
            .post(endpoint)
            .bearer_auth(&self.config.api_key)
            .json(request_body)
            .send()
            .await
            .map_err(|error| ChatRequestError {
                retryable: error.is_timeout() || error.is_connect(),
                message: format!("chat completion request failed: {error}"),
            })?;
        let status = response.status();
        let response_text = response.text().await.map_err(|error| ChatRequestError {
            retryable: true,
            message: format!("chat completion response body could not be read: {error}"),
        })?;
        if !status.is_success() {
            return Err(ChatRequestError {
                retryable: is_retryable_status(status),
                message: format!(
                    "chat completion returned HTTP {}: {}",
                    status.as_u16(),
                    compact_snippet(&response_text, 300)
                ),
            });
        }
        Ok(response_text)
    }

    async fn send_chat_request_with_curl(
        &self,
        endpoint: &str,
        request_body: &Value,
    ) -> std::result::Result<String, ChatRequestError> {
        let body_path = temp_request_body_path();
        let body = serde_json::to_vec(request_body).map_err(|error| ChatRequestError {
            retryable: false,
            message: format!("chat completion request body could not be serialized: {error}"),
        })?;
        fs::write(&body_path, body).map_err(|error| ChatRequestError {
            retryable: false,
            message: format!("chat completion request body could not be written: {error}"),
        })?;

        let mut child = Command::new("curl")
            .arg("-sS")
            .arg("--max-time")
            .arg(self.config.timeout.as_secs().to_string())
            .arg("-K")
            .arg("-")
            .arg("-w")
            .arg("\n__HEXGO_HTTP_STATUS__:%{http_code}\n")
            .arg("--data-binary")
            .arg(format!("@{}", body_path.display()))
            .arg(endpoint)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|error| ChatRequestError {
                retryable: true,
                message: format!("curl chat completion request could not be started: {error}"),
            })?;

        if let Some(mut stdin) = child.stdin.take() {
            let curl_config = format!(
                "header = \"Authorization: Bearer {}\"\nheader = \"Content-Type: application/json\"\n",
                self.config.api_key
            );
            stdin
                .write_all(curl_config.as_bytes())
                .await
                .map_err(|error| ChatRequestError {
                    retryable: true,
                    message: format!("curl chat completion config could not be written: {error}"),
                })?;
        }

        let output = match timeout(self.config.timeout, child.wait_with_output()).await {
            Ok(result) => result.map_err(|error| ChatRequestError {
                retryable: true,
                message: format!("curl chat completion request failed: {error}"),
            }),
            Err(_) => Err(ChatRequestError {
                retryable: true,
                message: format!(
                    "curl chat completion timed out after {} seconds",
                    self.config.timeout.as_secs()
                ),
            }),
        };
        let _ = fs::remove_file(&body_path);
        let output = output?;
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);

        if !output.status.success() {
            return Err(ChatRequestError {
                retryable: true,
                message: format!(
                    "curl chat completion exited with {}: {}",
                    output.status,
                    compact_snippet(&stderr, 300)
                ),
            });
        }

        let (response_text, status) = split_curl_response(&stdout)?;
        if !status.is_success() {
            return Err(ChatRequestError {
                retryable: is_retryable_status(status),
                message: format!(
                    "chat completion returned HTTP {}: {}",
                    status.as_u16(),
                    compact_snippet(response_text, 300)
                ),
            });
        }
        Ok(response_text.to_string())
    }
}

impl OpenAiAgentClient {
    async fn choose_model_action(
        &self,
        model: &str,
        player: Player,
        observation: &Observation,
    ) -> Result<AgentDecision> {
        let endpoint = chat_completions_endpoint(&self.config.base_url);
        let candidate_actions =
            candidate_actions_for_prompt(observation, self.config.candidate_count);
        let candidate_action_indices = candidate_actions
            .iter()
            .filter_map(|action| action.get("action_index").and_then(Value::as_u64))
            .filter_map(|index| usize::try_from(index).ok())
            .collect::<Vec<_>>();
        let mut request_body = json!({
            "model": model,
            "temperature": self.config.temperature,
            "max_tokens": self.config.max_output_tokens,
            "messages": [
                {
                    "role": "system",
                    "content": system_prompt()
                },
                {
                    "role": "user",
                    "content": user_prompt(player, observation, &candidate_actions, &candidate_action_indices)?
                }
            ]
        });
        if self.config.json_response_format {
            request_body["response_format"] = json!({"type": "json_object"});
        }

        let response_text = self
            .send_chat_request_with_retries(&endpoint, &request_body)
            .await?;

        let response: OpenAiChatResponse =
            serde_json::from_str(&response_text).with_context(|| {
                format!(
                    "chat completion response was not valid JSON: {}",
                    compact_snippet(&response_text, 300)
                )
            })?;

        let content = response
            .choices
            .first()
            .map(|choice| choice.message.content.trim())
            .filter(|content| !content.is_empty())
            .ok_or_else(|| anyhow!("chat completion response had no message content"))?;

        parse_agent_decision_with_allowed(content, observation, &candidate_action_indices)
    }
}

impl OpenAiAgentClient {
    async fn send_chat_request_with_retries(
        &self,
        endpoint: &str,
        request_body: &Value,
    ) -> Result<String> {
        let attempts = self.config.max_retries + 1;
        for attempt in 0..attempts {
            let request_result = timeout(
                self.config.timeout,
                self.send_chat_request(endpoint, request_body),
            )
            .await;
            let chat_result = match request_result {
                Ok(result) => result,
                Err(_) => Err(ChatRequestError {
                    retryable: true,
                    message: format!(
                        "chat completion request timed out after {} seconds",
                        self.config.timeout.as_secs()
                    ),
                }),
            };
            match chat_result {
                Ok(response_text) => return Ok(response_text),
                Err(error) => {
                    let should_retry = error.retryable && attempt + 1 < attempts;
                    if !should_retry {
                        if attempt == 0 {
                            bail!("{error}");
                        }
                        bail!("chat completion failed after {attempts} attempts: {error}");
                    }
                    let multiplier = (attempt + 1) as u32;
                    sleep(self.config.retry_backoff * multiplier).await;
                }
            }
        }
        unreachable!("retry loop always returns or bails")
    }
}

#[derive(Debug, Deserialize)]
struct OpenAiChatResponse {
    choices: Vec<OpenAiChoice>,
}

#[derive(Debug, Deserialize)]
struct OpenAiChoice {
    message: OpenAiMessage,
}

#[derive(Debug, Deserialize)]
struct OpenAiMessage {
    content: String,
}

#[derive(Debug, Serialize)]
struct GameRecord {
    game_index: usize,
    attempt_index: usize,
    counted: bool,
    board_radius: i32,
    black_model: String,
    white_model: String,
    black_agent: SerializableAgent,
    white_agent: SerializableAgent,
    winner: String,
    margin: i32,
    scores: SerializableScores,
    score_breakdown: SerializableScoreBreakdown,
    move_count: usize,
    turn_count: usize,
    invalid_actions: InvalidActionCounts,
    replayed_attempts: Vec<GameAttemptSummary>,
    steps: Vec<StepRecord>,
}

#[derive(Debug, Serialize)]
struct StepRecord {
    turn: usize,
    player: String,
    model: String,
    agent_kind: String,
    requested_action_index: Option<usize>,
    applied_action_index: usize,
    decision_attempts: usize,
    action: SerializableAction,
    reason: String,
    invalid_action: bool,
    retry_errors: Vec<String>,
    error: Option<String>,
    accepted: bool,
    scores: SerializableScores,
}

#[derive(Debug, Clone, Serialize)]
struct GameAttemptSummary {
    attempt_index: usize,
    counted: bool,
    winner: String,
    move_count: usize,
    turn_count: usize,
    invalid_actions: InvalidActionCounts,
    first_error: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type")]
enum SerializableAction {
    Move { q: i32, r: i32 },
    Pass,
}

#[derive(Debug, Serialize)]
struct SerializableScores {
    black: u32,
    white: u32,
}

#[derive(Debug, Serialize)]
struct SerializableScoreBreakdown {
    black: SerializablePlayerBreakdown,
    white: SerializablePlayerBreakdown,
}

#[derive(Debug, Serialize)]
struct SerializablePlayerBreakdown {
    pieces: u32,
    territory: u32,
    total: u32,
}

#[derive(Debug, Serialize)]
struct SerializableAgent {
    kind: String,
    name: String,
    model: Option<String>,
    command: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
struct InvalidActionCounts {
    black: usize,
    white: usize,
}

impl InvalidActionCounts {
    fn total(&self) -> usize {
        self.black + self.white
    }
}

fn build_agent_config(
    side: &str,
    model: Option<String>,
    command: Option<String>,
    name: Option<String>,
) -> Result<AgentConfig> {
    match (model, command) {
        (Some(model), None) => Ok(AgentConfig::model(model, name)),
        (None, Some(command)) => AgentConfig::command(command, name),
        (None, None) => bail!("--{side}-model or --{side}-command is required"),
        (Some(_), Some(_)) => bail!("--{side}-model and --{side}-command are mutually exclusive"),
    }
}

fn parse_command_argv(command: &str) -> Result<Vec<String>> {
    let mut args = Vec::new();
    let mut current = String::new();
    let mut quote: Option<char> = None;
    let mut escaped = false;
    let mut started = false;

    for ch in command.chars() {
        if escaped {
            current.push(ch);
            started = true;
            escaped = false;
            continue;
        }

        if ch == '\\' {
            escaped = true;
            started = true;
            continue;
        }

        match quote {
            Some(quote_char) => {
                if ch == quote_char {
                    quote = None;
                } else {
                    current.push(ch);
                }
                started = true;
            }
            None => {
                if ch == '\'' || ch == '"' {
                    quote = Some(ch);
                    started = true;
                } else if ch.is_whitespace() {
                    if started {
                        args.push(std::mem::take(&mut current));
                        started = false;
                    }
                } else {
                    current.push(ch);
                    started = true;
                }
            }
        }
    }

    if escaped {
        bail!("command ends with an unfinished escape");
    }
    if let Some(quote_char) = quote {
        bail!("command has an unterminated {quote_char} quote");
    }
    if started {
        args.push(current);
    }
    Ok(args)
}

async fn choose_command_action(
    agent: &AgentConfig,
    player: Player,
    observation: &Observation,
    command_timeout: Duration,
    max_output_bytes: usize,
) -> Result<AgentDecision> {
    let executable = agent
        .argv
        .first()
        .ok_or_else(|| anyhow!("command agent {} has empty argv", agent.name))?;
    let payload = serde_json::to_vec(&build_strategy_request(player, observation))
        .context("failed to serialize strategy observation")?;

    let mut command = Command::new(executable);
    command
        .args(agent.argv.iter().skip(1))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);

    let mut child = command
        .spawn()
        .with_context(|| format!("failed to start strategy command {}", agent.display_name()))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(&payload)
            .await
            .with_context(|| format!("failed to write stdin for {}", agent.display_name()))?;
        stdin
            .write_all(b"\n")
            .await
            .with_context(|| format!("failed to finish stdin for {}", agent.display_name()))?;
    }

    let output = match timeout(command_timeout, child.wait_with_output()).await {
        Ok(result) => {
            result.with_context(|| format!("strategy command {} failed", agent.display_name()))?
        }
        Err(_) => bail!(
            "strategy command {} timed out after {} seconds",
            agent.display_name(),
            command_timeout.as_secs()
        ),
    };

    let total_output = output.stdout.len() + output.stderr.len();
    if total_output > max_output_bytes {
        bail!(
            "strategy command {} wrote {} bytes, exceeding --max-command-output-bytes {}",
            agent.display_name(),
            total_output,
            max_output_bytes
        );
    }

    let stderr_text = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() {
        bail!(
            "strategy command {} exited with {}: {}",
            agent.display_name(),
            output.status,
            compact_snippet(&stderr_text, 300)
        );
    }

    let stdout_text = String::from_utf8(output.stdout).with_context(|| {
        format!(
            "strategy command {} stdout was not UTF-8",
            agent.display_name()
        )
    })?;
    parse_agent_decision(&stdout_text, observation).with_context(|| {
        format!(
            "strategy command {} returned invalid action",
            agent.display_name()
        )
    })
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    if cli.games == 0 {
        bail!("--games must be greater than 0");
    }
    if cli.board_radius <= 0 {
        bail!("--board-radius must be greater than 0");
    }
    if cli.command_timeout_seconds == 0 {
        bail!("--command-timeout-seconds must be greater than 0");
    }
    if cli.max_command_output_bytes == 0 {
        bail!("--max-command-output-bytes must be greater than 0");
    }

    let black_agent =
        build_agent_config("black", cli.black_model, cli.black_command, cli.black_name)?;
    let white_agent =
        build_agent_config("white", cli.white_model, cli.white_command, cli.white_name)?;
    let uses_model_agent =
        black_agent.kind == AgentKind::Model || white_agent.kind == AgentKind::Model;

    let eval_config = EvalConfig {
        black_agent,
        white_agent,
        command_timeout: Duration::from_secs(cli.command_timeout_seconds),
        max_command_output_bytes: cli.max_command_output_bytes,
        board_radius: cli.board_radius,
        games: cli.games,
        max_turns: cli.max_turns,
        replay_invalid_games: cli.replay_invalid_games,
        max_game_attempts: cli.max_game_attempts,
        decision_retries: cli.decision_retries,
        decision_retry_backoff: Duration::from_millis(cli.decision_retry_backoff_ms),
    };
    let openai = if uses_model_agent {
        let api_key = std::env::var(&cli.api_key_env)
            .with_context(|| format!("environment variable {} is not set", cli.api_key_env))?;
        Some(OpenAiAgentClient::new(OpenAiConfig {
            base_url: cli.base_url,
            api_key,
            temperature: cli.temperature,
            max_output_tokens: cli.max_output_tokens,
            candidate_count: cli.candidate_count,
            timeout: Duration::from_secs(cli.timeout_seconds),
            max_retries: cli.max_retries,
            retry_backoff: Duration::from_millis(cli.retry_backoff_ms),
            json_response_format: cli.json_response_format,
            curl_client: cli.curl_client,
        })?)
    } else {
        None
    };
    let client = EvalAgentClient {
        openai,
        command_timeout: eval_config.command_timeout,
        max_command_output_bytes: eval_config.max_command_output_bytes,
    };

    let mut writer = open_output(cli.out.as_ref())?;
    for game_index in 0..eval_config.games {
        eprintln!(
            "game {} / {}: {} black vs {} white",
            game_index + 1,
            eval_config.games,
            eval_config.black_agent.display_name(),
            eval_config.white_agent.display_name()
        );
        let record = run_counted_game(game_index, &eval_config, &client).await?;
        serde_json::to_writer(&mut writer, &record).context("failed to serialize game record")?;
        writer
            .write_all(b"\n")
            .context("failed to write game record newline")?;
        writer.flush().context("failed to flush game record")?;
        eprintln!(
            "game {} written: counted={} winner={} turns={} replayed_attempts={}",
            game_index + 1,
            record.counted,
            record.winner,
            record.turn_count,
            record.replayed_attempts.len()
        );
    }

    Ok(())
}

async fn run_counted_game(
    game_index: usize,
    config: &EvalConfig,
    client: &dyn AgentClient,
) -> Result<GameRecord> {
    let max_attempts = config.max_game_attempts.max(1);
    let mut replayed_attempts = Vec::new();
    for attempt_index in 1..=max_attempts {
        eprintln!(
            "game {} attempt {} / {}",
            game_index + 1,
            attempt_index,
            max_attempts
        );
        let mut record = run_game_attempt(game_index, attempt_index, config, client).await?;
        if !config.replay_invalid_games || record.invalid_actions.total() == 0 {
            record.counted = true;
            record.replayed_attempts = replayed_attempts;
            return Ok(record);
        }

        let first_error = record
            .steps
            .iter()
            .find_map(|step| step.error.as_deref())
            .unwrap_or("unknown error");
        eprintln!(
            "game {} attempt {} replayed after invalid actions: black={} white={} first_error={}",
            game_index + 1,
            attempt_index,
            record.invalid_actions.black,
            record.invalid_actions.white,
            compact_snippet(first_error, 160)
        );
        replayed_attempts.push(attempt_summary(&record));
        if attempt_index == max_attempts {
            record.counted = false;
            record.replayed_attempts = replayed_attempts;
            return Ok(record);
        }
    }
    unreachable!("attempt loop always returns")
}

#[cfg(test)]
async fn run_game(
    game_index: usize,
    config: &EvalConfig,
    client: &dyn AgentClient,
) -> Result<GameRecord> {
    run_game_attempt(game_index, 1, config, client).await
}

async fn run_game_attempt(
    game_index: usize,
    attempt_index: usize,
    config: &EvalConfig,
    client: &dyn AgentClient,
) -> Result<GameRecord> {
    let rules = RulesConfig::new(config.board_radius, ScoringMode::AutoSettle);
    let mut engine = MatchEngine::new(rules);
    engine.consume_events();
    let codec = ActionCodec::new(&engine.board);
    let mut steps = Vec::new();
    let mut invalid_actions = InvalidActionCounts::default();
    let mut aborted_by_invalid_action = false;

    loop {
        let observation = engine.build_observation(Some(&codec));
        if observation.result.is_game_over {
            break;
        }
        if observation.legal_action_indices.is_empty() {
            bail!("game {game_index} has no legal actions before game over");
        }
        if config.max_turns > 0 && steps.len() >= config.max_turns {
            force_auto_settle(&mut engine);
            break;
        }

        let player = observation.current_player;
        let agent = agent_for_player(config, player);
        if steps.len() % 10 == 0 {
            eprintln!(
                "game {} attempt {} turn {}: {} ({}) thinking",
                game_index + 1,
                attempt_index,
                steps.len() + 1,
                player_name(player),
                agent.display_name()
            );
        }
        let decision_result = choose_action_with_decision_retries(
            client,
            agent,
            player,
            &observation,
            config.decision_retries,
            config.decision_retry_backoff,
        )
        .await;
        let (decision, decision_attempts, retry_errors, error) = match decision_result {
            Ok(outcome) => (
                outcome.decision,
                outcome.attempts,
                outcome.retry_errors,
                None,
            ),
            Err(outcome) => {
                let fallback_index = fallback_action_index(&observation);
                (
                    AgentDecision {
                        action_index: fallback_index,
                        reason: "fallback after invalid or unavailable agent response".to_string(),
                    },
                    outcome.attempts,
                    outcome.retry_errors,
                    outcome.error,
                )
            }
        };

        let invalid_action = error.is_some();
        if invalid_action {
            count_invalid_action(&mut invalid_actions, player);
            if config.replay_invalid_games {
                let fallback_action = codec
                    .decode_action_index(decision.action_index)
                    .unwrap_or(Action::Pass);
                steps.push(StepRecord {
                    turn: steps.len() + 1,
                    player: player_name(player).to_string(),
                    model: agent.display_name().to_string(),
                    agent_kind: agent.kind.as_str().to_string(),
                    requested_action_index: None,
                    applied_action_index: decision.action_index,
                    decision_attempts,
                    action: serialize_action(fallback_action),
                    reason: decision.reason,
                    invalid_action: true,
                    retry_errors,
                    error,
                    accepted: false,
                    scores: serialize_scores(observation.scores),
                });
                aborted_by_invalid_action = true;
                break;
            }
        }

        let action = codec
            .decode_action_index(decision.action_index)
            .ok_or_else(|| {
                anyhow!(
                    "fallback action index {} could not be decoded",
                    decision.action_index
                )
            })?;
        let step_result = engine.step_action(action, Some(&codec));
        let accepted = step_result.accepted;
        let scores = step_result.observation.scores;

        steps.push(StepRecord {
            turn: steps.len() + 1,
            player: player_name(player).to_string(),
            model: agent.display_name().to_string(),
            agent_kind: agent.kind.as_str().to_string(),
            requested_action_index: if invalid_action {
                None
            } else {
                Some(decision.action_index)
            },
            applied_action_index: decision.action_index,
            decision_attempts,
            action: serialize_action(action),
            reason: decision.reason,
            invalid_action,
            retry_errors,
            error,
            accepted,
            scores: serialize_scores(scores),
        });
    }

    let final_observation = engine.build_observation(Some(&codec));
    let winner = if aborted_by_invalid_action {
        "invalid".to_string()
    } else {
        final_observation
            .result
            .winner
            .map(player_name)
            .unwrap_or("draw")
            .to_string()
    };
    Ok(GameRecord {
        game_index,
        attempt_index,
        counted: !aborted_by_invalid_action,
        board_radius: config.board_radius,
        black_model: config.black_agent.display_name().to_string(),
        white_model: config.white_agent.display_name().to_string(),
        black_agent: serialize_agent(&config.black_agent),
        white_agent: serialize_agent(&config.white_agent),
        winner,
        margin: final_observation.result.margin,
        scores: serialize_scores(final_observation.scores),
        score_breakdown: serialize_score_breakdown(final_observation.score_breakdown),
        move_count: final_observation.move_count,
        turn_count: steps.len(),
        invalid_actions,
        replayed_attempts: Vec::new(),
        steps,
    })
}

#[derive(Debug)]
struct DecisionOutcome {
    decision: AgentDecision,
    attempts: usize,
    retry_errors: Vec<String>,
}

#[derive(Debug)]
struct DecisionFailure {
    attempts: usize,
    retry_errors: Vec<String>,
    error: Option<String>,
}

async fn choose_action_with_decision_retries(
    client: &dyn AgentClient,
    agent: &AgentConfig,
    player: Player,
    observation: &Observation,
    decision_retries: usize,
    retry_backoff: Duration,
) -> std::result::Result<DecisionOutcome, DecisionFailure> {
    let max_attempts = decision_retries + 1;
    let mut retry_errors = Vec::new();
    for attempt in 0..max_attempts {
        match client.choose_action(agent, player, observation).await {
            Ok(decision) => {
                return Ok(DecisionOutcome {
                    decision,
                    attempts: attempt + 1,
                    retry_errors,
                });
            }
            Err(error) => {
                let message = format_error_chain(&error);
                if attempt + 1 == max_attempts {
                    return Err(DecisionFailure {
                        attempts: attempt + 1,
                        retry_errors,
                        error: Some(message),
                    });
                }
                retry_errors.push(message);
                let multiplier = (attempt + 1) as u32;
                sleep(retry_backoff * multiplier).await;
            }
        }
    }
    unreachable!("decision retry loop always returns")
}

fn attempt_summary(record: &GameRecord) -> GameAttemptSummary {
    GameAttemptSummary {
        attempt_index: record.attempt_index,
        counted: record.counted,
        winner: record.winner.clone(),
        move_count: record.move_count,
        turn_count: record.turn_count,
        invalid_actions: record.invalid_actions.clone(),
        first_error: record.steps.iter().find_map(|step| step.error.clone()),
    }
}

fn parse_agent_decision(content: &str, observation: &Observation) -> Result<AgentDecision> {
    parse_agent_decision_with_allowed(content, observation, &observation.legal_action_indices)
}

fn parse_agent_decision_with_allowed(
    content: &str,
    observation: &Observation,
    allowed_action_indices: &[usize],
) -> Result<AgentDecision> {
    let parsed = parse_loose_json_object(content)?;
    let action_index = action_index_from_response(&parsed, observation)?;
    if !allowed_action_indices.contains(&action_index) {
        bail!("agent chose illegal action_index {action_index} outside allowed action indices");
    }
    let reason = parsed
        .get("reason")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    Ok(AgentDecision {
        action_index,
        reason,
    })
}

fn parse_loose_json_object(content: &str) -> Result<Value> {
    let trimmed = content.trim();
    let unfenced = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .and_then(|value| value.strip_suffix("```"))
        .map(str::trim)
        .unwrap_or(trimmed);

    let mut candidates = vec![trimmed.to_string(), unfenced.to_string()];
    if let Some(json_slice) = extract_first_json_object(unfenced) {
        candidates.push(json_slice.to_string());
    }

    for candidate in candidates.clone() {
        if let Some(repaired) = repair_missing_action_index_colon(&candidate) {
            candidates.push(repaired);
        }
    }

    for candidate in candidates {
        if let Ok(parsed) = serde_json::from_str::<Value>(&candidate) {
            if parsed.is_object() {
                return Ok(parsed);
            }
        }
    }

    bail!(
        "agent response did not contain a JSON object: {}",
        compact_snippet(content, 300)
    )
}

fn repair_missing_action_index_colon(content: &str) -> Option<String> {
    let marker = "\"action_index";
    let start = content.find(marker)?;
    let digit_start = start + marker.len();
    if content[digit_start..].starts_with("\":") {
        return None;
    }

    let mut digit_end = digit_start;
    for ch in content[digit_start..].chars() {
        if ch.is_ascii_digit() {
            digit_end += ch.len_utf8();
        } else {
            break;
        }
    }
    if digit_end == digit_start {
        return None;
    }

    let mut repaired = String::new();
    repaired.push_str(&content[..start]);
    repaired.push_str("\"action_index\":");
    repaired.push_str(&content[digit_start..digit_end]);
    repaired.push_str(&content[digit_end..]);
    Some(repaired)
}

fn extract_first_json_object(content: &str) -> Option<&str> {
    let start = content.find('{')?;
    let mut depth = 0usize;
    let mut in_string = false;
    let mut escaped = false;
    for (offset, ch) in content[start..].char_indices() {
        if in_string {
            if escaped {
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '"' {
                in_string = false;
            }
            continue;
        }

        match ch {
            '"' => in_string = true,
            '{' => depth += 1,
            '}' => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    let end = start + offset + ch.len_utf8();
                    return Some(&content[start..end]);
                }
            }
            _ => {}
        }
    }
    None
}

fn action_index_from_response(parsed: &Value, observation: &Observation) -> Result<usize> {
    let object = parsed
        .as_object()
        .ok_or_else(|| anyhow!("agent response JSON was not an object"))?;
    if let Some(action_object) = object.get("action").and_then(Value::as_object) {
        if action_object.contains_key("action_index")
            || action_object.contains_key("type")
            || action_object.contains_key("coord")
            || action_object.contains_key("q")
        {
            return action_index_from_object(action_object, observation);
        }
    }
    action_index_from_object(object, observation)
}

fn action_index_from_object(
    parsed: &serde_json::Map<String, Value>,
    observation: &Observation,
) -> Result<usize> {
    if let Some(value) = parsed.get("action_index") {
        return parse_action_index_value(value);
    }

    if parsed
        .get("type")
        .or_else(|| parsed.get("action"))
        .and_then(Value::as_str)
        .map(|value| value.eq_ignore_ascii_case("pass"))
        .unwrap_or(false)
    {
        return Ok(observation.pass_action_index);
    }

    if let Some(coord) = parsed.get("coord").and_then(Value::as_object) {
        return action_index_from_coord_values(coord.get("q"), coord.get("r"), observation);
    }

    action_index_from_coord_values(parsed.get("q"), parsed.get("r"), observation)
        .context("agent response is missing action_index, pass type, or q/r coord")
}

fn parse_action_index_value(value: &Value) -> Result<usize> {
    if let Some(index) = value.as_u64() {
        return Ok(index as usize);
    }
    if let Some(index_text) = value.as_str() {
        return index_text
            .trim()
            .parse::<usize>()
            .context("agent action_index string was not an integer");
    }
    bail!("agent action_index was not an integer or integer string")
}

fn action_index_from_coord_values(
    q: Option<&Value>,
    r: Option<&Value>,
    observation: &Observation,
) -> Result<usize> {
    let q = parse_i32_value(q.ok_or_else(|| anyhow!("missing q"))?).context("invalid q")?;
    let r = parse_i32_value(r.ok_or_else(|| anyhow!("missing r"))?).context("invalid r")?;
    observation
        .ordered_coords
        .iter()
        .position(|coord| coord.q == q && coord.r == r)
        .ok_or_else(|| anyhow!("coord {q},{r} is outside the board"))
}

fn parse_i32_value(value: &Value) -> Result<i32> {
    if let Some(number) = value.as_i64() {
        return i32::try_from(number).context("number is outside i32 range");
    }
    if let Some(text) = value.as_str() {
        return text
            .trim()
            .parse::<i32>()
            .context("string is not an integer");
    }
    bail!("value is not an integer")
}

fn force_auto_settle(engine: &mut MatchEngine) {
    if engine.phase.as_str() == "game_over" {
        return;
    }
    let _ = engine.record_pass();
    if engine.phase.as_str() != "game_over" {
        let _ = engine.record_pass();
    }
}

fn fallback_action_index(observation: &Observation) -> usize {
    if observation
        .legal_action_indices
        .contains(&observation.pass_action_index)
    {
        observation.pass_action_index
    } else {
        observation.legal_action_indices[0]
    }
}

fn count_invalid_action(counts: &mut InvalidActionCounts, player: Player) {
    match player {
        Player::Black => counts.black += 1,
        Player::White => counts.white += 1,
    }
}

fn agent_for_player(config: &EvalConfig, player: Player) -> &AgentConfig {
    match player {
        Player::Black => &config.black_agent,
        Player::White => &config.white_agent,
    }
}

fn chat_completions_endpoint(base_url: &str) -> String {
    let trimmed = base_url.trim_end_matches('/');
    if trimmed.ends_with("/chat/completions") {
        trimmed.to_string()
    } else {
        format!("{trimmed}/chat/completions")
    }
}

fn is_retryable_status(status: StatusCode) -> bool {
    status == StatusCode::REQUEST_TIMEOUT
        || status == StatusCode::TOO_MANY_REQUESTS
        || status.is_server_error()
}

fn format_error_chain(error: &anyhow::Error) -> String {
    error
        .chain()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(": ")
}

fn temp_request_body_path() -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    std::env::temp_dir().join(format!(
        "hexgo-eval-request-{}-{nanos}.json",
        std::process::id()
    ))
}

fn split_curl_response(output: &str) -> std::result::Result<(&str, StatusCode), ChatRequestError> {
    const STATUS_MARKER: &str = "\n__HEXGO_HTTP_STATUS__:";
    let (body, status_text) =
        output
            .rsplit_once(STATUS_MARKER)
            .ok_or_else(|| ChatRequestError {
                retryable: true,
                message: format!(
                    "curl chat completion response did not include HTTP status marker: {}",
                    compact_snippet(output, 300)
                ),
            })?;
    let status_code = status_text
        .trim()
        .parse::<u16>()
        .map_err(|error| ChatRequestError {
            retryable: true,
            message: format!("curl chat completion HTTP status was invalid: {error}"),
        })?;
    let status = StatusCode::from_u16(status_code).map_err(|error| ChatRequestError {
        retryable: true,
        message: format!("curl chat completion HTTP status was invalid: {error}"),
    })?;
    Ok((body, status))
}

fn compact_snippet(value: &str, limit: usize) -> String {
    let compact = value.split_whitespace().collect::<Vec<_>>().join(" ");
    if compact.chars().count() <= limit {
        return compact;
    }
    let mut snippet = compact.chars().take(limit).collect::<String>();
    snippet.push_str("...");
    snippet
}

fn system_prompt() -> &'static str {
    "You are playing HexGo on a hex grid. Pick exactly one action_index from candidate_action_indices. Reply only compact JSON: {\"action_index\": number, \"reason\": string}."
}

fn user_prompt(
    player: Player,
    observation: &Observation,
    candidate_actions: &[Value],
    candidate_action_indices: &[usize],
) -> Result<String> {
    let body = json!({
        "player": player_name(player),
        "objective": "Maximize final score: live stones plus controlled territory.",
        "strategy_hints": [
            "Prefer captures, high-liberty moves, central influence in the opening, and moves that connect friendly groups.",
            "Avoid low-liberty moves unless they capture or save a group.",
            "Do not pass early.",
            "If a pass candidate appears late and you are ahead or no move clearly improves score, passing can be best because two consecutive passes end the game."
        ],
        "rules_summary": [
            "HexGo uses axial hex coordinates (q,r) on the listed radius board.",
            "Neighbor deltas are (+1,0), (+1,-1), (0,-1), (-1,0), (-1,+1), (0,+1).",
            "A move places your stone on an empty legal coordinate.",
            "Connected same-color stones form groups; adjacent empty cells are liberties.",
            "After your move, opponent groups with zero liberties are captured.",
            "Suicide and repetition moves are already removed from legal_actions.",
            "Empty regions bordered by one color count as that color's territory.",
            "Passing is legal; two consecutive passes end the game and settle score.",
            "All candidate actions are legal; choose only from candidate_action_indices."
        ],
        "state": serialize_observation_for_prompt(observation),
        "candidate_actions": candidate_actions,
        "candidate_action_indices": candidate_action_indices,
        "required_response": {
            "action_index": "integer from candidate_action_indices",
            "reason": "brief"
        }
    });
    serde_json::to_string(&body).context("failed to serialize prompt observation")
}

fn build_strategy_request(player: Player, observation: &Observation) -> Value {
    json!({
        "protocol_version": observation.protocol_version,
        "player": player_name(player),
        "objective": "Maximize final score: live stones plus controlled territory.",
        "rules_summary": [
            "HexGo uses axial hex coordinates (q,r) on the listed radius board.",
            "Neighbor deltas are (+1,0), (+1,-1), (0,-1), (-1,0), (-1,+1), (0,+1).",
            "A move places your stone on an empty legal coordinate.",
            "Connected same-color stones form groups; adjacent empty cells are liberties.",
            "After your move, opponent groups with zero liberties are captured.",
            "Suicide and repetition moves are already removed from legal_actions.",
            "Empty regions bordered by one color count as that color's territory.",
            "Passing is legal; two consecutive passes end the game and settle score.",
            "Choose only one action_index from legal_action_indices."
        ],
        "state": serialize_observation_for_prompt(observation),
        "legal_actions": legal_actions_for_prompt(observation),
        "legal_action_indices": observation.legal_action_indices,
        "pass_action_index": observation.pass_action_index,
        "required_response": {
            "action_index": "integer from legal_action_indices",
            "reason": "brief"
        }
    })
}

fn serialize_observation_for_prompt(observation: &Observation) -> Value {
    let occupied_cells = observation
        .ordered_coords
        .iter()
        .zip(observation.cells.iter())
        .filter(|(_, cell)| cell_state_name(**cell) != "empty")
        .map(|(coord, cell)| {
            json!({
                "q": coord.q,
                "r": coord.r,
                "state": cell_state_name(*cell),
            })
        })
        .collect::<Vec<_>>();

    json!({
        "protocol_version": observation.protocol_version,
        "phase": observation.phase.as_str(),
        "board_radius": observation.board_radius,
        "scoring_mode": observation.rules.scoring_mode.as_str(),
        "current_player": player_name(observation.current_player),
        "move_count": observation.move_count,
        "consecutive_passes": observation.consecutive_passes,
        "pass_action_index": observation.pass_action_index,
        "scores": serialize_scores(observation.scores),
        "legal_action_indices": &observation.legal_action_indices,
        "board_rows": board_rows_for_prompt(observation),
        "occupied_cells": occupied_cells,
    })
}

fn board_rows_for_prompt(observation: &Observation) -> Vec<String> {
    let cell_by_coord = observation
        .ordered_coords
        .iter()
        .zip(observation.cells.iter())
        .map(|(coord, cell)| (*coord, *cell))
        .collect::<HashMap<_, _>>();
    let radius = observation.board_radius;
    (-radius..=radius)
        .map(|r| {
            let q_min = (-radius).max(-r - radius);
            let q_max = radius.min(-r + radius);
            let cells = (q_min..=q_max)
                .map(
                    |q| match cell_by_coord.get(&Coord::new(q, r)).copied().unwrap_or(0) {
                        1 => "B",
                        2 => "W",
                        _ => ".",
                    },
                )
                .collect::<Vec<_>>()
                .join(" ");
            format!("r={r} q={q_min}..{q_max}: {cells}")
        })
        .collect()
}

fn candidate_actions_for_prompt(observation: &Observation, limit: usize) -> Vec<Value> {
    let board = board_map_from_observation(observation);
    let own_state = cell_state_for_player(observation.current_player);
    let opponent_state = cell_state_for_player(observation.current_player.other());
    let early_bias = 1.0
        - (observation.move_count as f64 / observation.ordered_coords.len().max(1) as f64)
            .clamp(0.0, 1.0);

    let mut ranked = observation
        .legal_action_indices
        .iter()
        .filter(|action_index| **action_index != observation.pass_action_index)
        .filter_map(|action_index| {
            let coord = *observation.ordered_coords.get(*action_index)?;
            let stats = score_candidate_move(
                &board,
                coord,
                own_state,
                opponent_state,
                observation.board_radius,
                early_bias,
            );
            Some((
                stats.score,
                *action_index,
                json!({
                    "action_index": action_index,
                    "type": "move",
                    "q": coord.q,
                    "r": coord.r,
                    "captures": stats.captures,
                    "self_liberties": stats.self_liberties,
                    "friendly_neighbors": stats.friendly_neighbors,
                    "enemy_neighbors": stats.enemy_neighbors,
                    "pressure": stats.pressure,
                    "center_distance": coord_distance(coord),
                    "score": stats.score,
                }),
            ))
        })
        .collect::<Vec<_>>();

    ranked.sort_by(|a, b| b.0.total_cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    let mut candidates = ranked
        .into_iter()
        .take(limit.max(1))
        .map(|(_, _, value)| value)
        .collect::<Vec<_>>();

    if let Some(pass_score) = pass_candidate_score(observation, candidates.is_empty()) {
        candidates.push(json!({
            "action_index": observation.pass_action_index,
            "type": "pass",
            "score": pass_score,
            "endgame_hint": "Pass can be correct in the endgame, especially when ahead or after opponent pass.",
        }));
    }
    candidates
}

#[derive(Debug, Clone, Copy)]
struct CandidateStats {
    score: f64,
    captures: usize,
    self_liberties: usize,
    friendly_neighbors: usize,
    enemy_neighbors: usize,
    pressure: usize,
}

fn score_candidate_move(
    board: &HashMap<Coord, i32>,
    coord: Coord,
    own_state: i32,
    opponent_state: i32,
    radius: i32,
    early_bias: f64,
) -> CandidateStats {
    let mut after = board.clone();
    after.insert(coord, own_state);

    let mut captured = HashSet::new();
    let mut checked = HashSet::new();
    for neighbor in neighbor_coords(coord, radius) {
        if checked.contains(&neighbor) || after.get(&neighbor) != Some(&opponent_state) {
            continue;
        }
        let (group, liberties) = group_and_liberties(&after, neighbor, radius);
        checked.extend(group.iter().copied());
        if liberties.is_empty() {
            captured.extend(group);
        }
    }
    for captured_coord in &captured {
        after.remove(captured_coord);
    }

    let (_, self_liberties) = group_and_liberties(&after, coord, radius);
    let mut friendly_neighbors = 0;
    let mut enemy_neighbors = 0;
    let mut pressure = 0;
    for neighbor in neighbor_coords(coord, radius) {
        match board.get(&neighbor).copied() {
            Some(state) if state == own_state => friendly_neighbors += 1,
            Some(state) if state == opponent_state => {
                enemy_neighbors += 1;
                let (_, liberties) = group_and_liberties(board, neighbor, radius);
                if liberties.len() <= 2 {
                    pressure += 1;
                }
            }
            _ => {}
        }
    }

    let centrality = (radius - coord_distance(coord)).max(0) as f64;
    let mut score = 0.0;
    score += captured.len() as f64 * 120.0;
    score += self_liberties.len() as f64 * 8.0;
    score += friendly_neighbors as f64 * 5.0;
    score += enemy_neighbors as f64 * 1.8;
    score += pressure as f64 * 12.0;
    score += centrality * (5.0 * early_bias + 1.0);
    if captured.is_empty() && self_liberties.len() <= 1 {
        score -= 80.0;
    } else if captured.is_empty() && self_liberties.len() == 2 {
        score -= 12.0;
    }
    score += coord.q as f64 * 0.013 + coord.r as f64 * 0.007;

    CandidateStats {
        score,
        captures: captured.len(),
        self_liberties: self_liberties.len(),
        friendly_neighbors,
        enemy_neighbors,
        pressure,
    }
}

fn pass_candidate_score(observation: &Observation, no_move_candidates: bool) -> Option<f64> {
    if !observation
        .legal_action_indices
        .contains(&observation.pass_action_index)
    {
        return None;
    }
    let total_cells = observation.ordered_coords.len().max(1);
    if no_move_candidates {
        return Some(10_000.0);
    }

    let own_score = score_for_player(observation.scores, observation.current_player);
    let opponent_score = score_for_player(observation.scores, observation.current_player.other());
    let margin = own_score - opponent_score;
    let progress = observation.move_count as f64 / total_cells as f64;

    if observation.consecutive_passes > 0 {
        return Some(if margin >= 0 {
            800.0
        } else {
            80.0 + margin as f64
        });
    }
    if progress >= 0.90 {
        return Some(240.0 + margin as f64 * 4.0);
    }
    if progress >= 0.75 {
        return Some(90.0 + margin as f64 * 3.0);
    }
    if progress >= 0.60 && margin > 4 {
        return Some(45.0 + margin as f64 * 2.0);
    }
    None
}

fn score_for_player(scores: ScoreTotals, player: Player) -> i32 {
    match player {
        Player::Black => scores.black as i32,
        Player::White => scores.white as i32,
    }
}

fn board_map_from_observation(observation: &Observation) -> HashMap<Coord, i32> {
    observation
        .ordered_coords
        .iter()
        .zip(observation.cells.iter())
        .filter(|(_, cell)| **cell == 1 || **cell == 2)
        .map(|(coord, cell)| (*coord, *cell))
        .collect()
}

fn cell_state_for_player(player: Player) -> i32 {
    match player {
        Player::Black => 1,
        Player::White => 2,
    }
}

fn coord_distance(coord: Coord) -> i32 {
    coord.q.abs().max(coord.r.abs()).max(coord.s().abs())
}

fn neighbor_coords(coord: Coord, radius: i32) -> Vec<Coord> {
    coord
        .neighbors()
        .into_iter()
        .filter(|neighbor| coord_distance(*neighbor) <= radius)
        .collect()
}

fn group_and_liberties(
    board: &HashMap<Coord, i32>,
    start: Coord,
    radius: i32,
) -> (HashSet<Coord>, HashSet<Coord>) {
    let Some(color) = board.get(&start).copied() else {
        return (HashSet::new(), HashSet::new());
    };
    let mut group = HashSet::new();
    let mut liberties = HashSet::new();
    let mut queue = VecDeque::from([start]);
    group.insert(start);

    while let Some(coord) = queue.pop_front() {
        for neighbor in neighbor_coords(coord, radius) {
            match board.get(&neighbor).copied() {
                Some(state) if state == color && group.insert(neighbor) => {
                    queue.push_back(neighbor);
                }
                Some(_) => {}
                None => {
                    liberties.insert(neighbor);
                }
            }
        }
    }
    (group, liberties)
}

fn legal_actions_for_prompt(observation: &Observation) -> Vec<Value> {
    observation
        .legal_action_indices
        .iter()
        .filter_map(|action_index| {
            if *action_index == observation.pass_action_index {
                return Some(json!({
                    "action_index": action_index,
                    "type": "pass",
                }));
            }
            observation.ordered_coords.get(*action_index).map(|coord| {
                json!({
                    "action_index": action_index,
                    "type": "move",
                    "q": coord.q,
                    "r": coord.r,
                })
            })
        })
        .collect()
}

fn serialize_action(action: Action) -> SerializableAction {
    match action {
        Action::Move(Coord { q, r }) => SerializableAction::Move { q, r },
        Action::Pass => SerializableAction::Pass,
    }
}

fn serialize_agent(agent: &AgentConfig) -> SerializableAgent {
    SerializableAgent {
        kind: agent.kind.as_str().to_string(),
        name: agent.name.clone(),
        model: agent.model.clone(),
        command: agent.command.clone(),
    }
}

fn serialize_scores(scores: ScoreTotals) -> SerializableScores {
    SerializableScores {
        black: scores.black,
        white: scores.white,
    }
}

fn serialize_score_breakdown(breakdown: ScoreBreakdown) -> SerializableScoreBreakdown {
    SerializableScoreBreakdown {
        black: SerializablePlayerBreakdown {
            pieces: breakdown.black.pieces,
            territory: breakdown.black.territory,
            total: breakdown.black.total,
        },
        white: SerializablePlayerBreakdown {
            pieces: breakdown.white.pieces,
            territory: breakdown.white.territory,
            total: breakdown.white.total,
        },
    }
}

fn player_name(player: Player) -> &'static str {
    match player {
        Player::Black => "black",
        Player::White => "white",
    }
}

fn cell_state_name(value: i32) -> &'static str {
    match value {
        1 => "black",
        2 => "white",
        3 => "territory_black",
        4 => "territory_white",
        _ => "empty",
    }
}

fn open_output(path: Option<&PathBuf>) -> Result<Box<dyn Write>> {
    match path {
        Some(path) => {
            let file = OpenOptions::new()
                .create(true)
                .append(true)
                .open(path)
                .with_context(|| format!("failed to open output file {}", path.display()))?;
            Ok(Box::new(file))
        }
        None => Ok(Box::new(io::stdout())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Mutex,
    };
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEST_SCRIPT_COUNTER: AtomicUsize = AtomicUsize::new(0);

    struct MockAgentClient {
        decisions: Mutex<HashMap<String, Vec<Result<AgentDecision, String>>>>,
    }

    impl MockAgentClient {
        fn new(decisions: HashMap<String, Vec<Result<AgentDecision, String>>>) -> Self {
            Self {
                decisions: Mutex::new(decisions),
            }
        }
    }

    #[async_trait]
    impl AgentClient for MockAgentClient {
        async fn choose_action(
            &self,
            agent: &AgentConfig,
            player: Player,
            observation: &Observation,
        ) -> Result<AgentDecision> {
            if agent.kind == AgentKind::Command {
                return choose_command_action(
                    agent,
                    player,
                    observation,
                    Duration::from_secs(5),
                    DEFAULT_MAX_COMMAND_OUTPUT_BYTES,
                )
                .await;
            }

            let model = agent.display_name();
            let mut decisions = self.decisions.lock().unwrap();
            let queue = decisions
                .get_mut(model)
                .ok_or_else(|| anyhow!("missing mock model {model}"))?;
            if queue.is_empty() {
                bail!("mock model {model} has no remaining decisions");
            }
            queue.remove(0).map_err(|message: String| anyhow!(message))
        }
    }

    #[test]
    fn parse_command_argv_handles_quotes_and_escapes() {
        let argv = parse_command_argv(r#"python3 "my strategy.py" --name qwen\ code"#).unwrap();
        assert_eq!(
            argv,
            vec![
                "python3".to_string(),
                "my strategy.py".to_string(),
                "--name".to_string(),
                "qwen code".to_string()
            ]
        );
    }

    #[test]
    fn build_agent_config_requires_one_source() {
        let error = build_agent_config("black", None, None, None).unwrap_err();
        assert!(error
            .to_string()
            .contains("--black-model or --black-command"));
        let error = build_agent_config(
            "white",
            Some("model".to_string()),
            Some("cmd".to_string()),
            None,
        )
        .unwrap_err();
        assert!(error.to_string().contains("mutually exclusive"));
    }

    #[test]
    fn parse_agent_decision_rejects_illegal_action() {
        let observation = test_observation();
        let error = parse_agent_decision(r#"{"action_index": 99, "reason": "bad"}"#, &observation)
            .unwrap_err();
        assert!(error.to_string().contains("illegal action_index"));
    }

    #[test]
    fn parse_agent_decision_accepts_legal_action() {
        let observation = test_observation();
        let decision =
            parse_agent_decision(r#"{"action_index": 2, "reason": "center"}"#, &observation)
                .unwrap();
        assert_eq!(
            decision,
            AgentDecision {
                action_index: 2,
                reason: "center".to_string()
            }
        );
    }

    #[test]
    fn parse_agent_decision_accepts_markdown_json_and_string_index() {
        let observation = test_observation();
        let decision = parse_agent_decision(
            "```json\n{\"action_index\": \"2\", \"reason\": \"center\"}\n```",
            &observation,
        )
        .unwrap();
        assert_eq!(decision.action_index, 2);
    }

    #[test]
    fn parse_agent_decision_accepts_coord_response() {
        let observation = test_observation();
        let decision =
            parse_agent_decision(r#"{"q": 0, "r": 0, "reason": "center"}"#, &observation).unwrap();
        let center_index = observation
            .ordered_coords
            .iter()
            .position(|coord| coord.q == 0 && coord.r == 0)
            .unwrap();
        assert_eq!(decision.action_index, center_index);
    }

    #[tokio::test]
    async fn mock_clients_can_finish_a_game_with_double_pass() {
        let config = EvalConfig {
            black_agent: AgentConfig::model("black-mock".to_string(), None),
            white_agent: AgentConfig::model("white-mock".to_string(), None),
            command_timeout: Duration::from_secs(1),
            max_command_output_bytes: DEFAULT_MAX_COMMAND_OUTPUT_BYTES,
            board_radius: 1,
            games: 1,
            max_turns: 0,
            replay_invalid_games: false,
            max_game_attempts: 1,
            decision_retries: 0,
            decision_retry_backoff: Duration::from_millis(0),
        };
        let pass_index = ActionCodec::new(&hexgo_core::Board::new(1)).pass_action_index();
        let client = MockAgentClient::new(HashMap::from([
            (
                "black-mock".to_string(),
                vec![Ok(AgentDecision {
                    action_index: pass_index,
                    reason: "pass".to_string(),
                })],
            ),
            (
                "white-mock".to_string(),
                vec![Ok(AgentDecision {
                    action_index: pass_index,
                    reason: "pass".to_string(),
                })],
            ),
        ]));

        let record = run_game(0, &config, &client).await.unwrap();
        assert_eq!(record.turn_count, 2);
        assert_eq!(record.move_count, 2);
        assert_eq!(record.invalid_actions.black, 0);
        assert_eq!(record.invalid_actions.white, 0);
    }

    #[tokio::test]
    async fn invalid_response_falls_back_to_pass_and_is_counted() {
        let config = EvalConfig {
            black_agent: AgentConfig::model("black-mock".to_string(), None),
            white_agent: AgentConfig::model("white-mock".to_string(), None),
            command_timeout: Duration::from_secs(1),
            max_command_output_bytes: DEFAULT_MAX_COMMAND_OUTPUT_BYTES,
            board_radius: 1,
            games: 1,
            max_turns: 0,
            replay_invalid_games: false,
            max_game_attempts: 1,
            decision_retries: 0,
            decision_retry_backoff: Duration::from_millis(0),
        };
        let pass_index = ActionCodec::new(&hexgo_core::Board::new(1)).pass_action_index();
        let client = MockAgentClient::new(HashMap::from([
            ("black-mock".to_string(), vec![Err("bad json".to_string())]),
            (
                "white-mock".to_string(),
                vec![Ok(AgentDecision {
                    action_index: pass_index,
                    reason: "pass".to_string(),
                })],
            ),
        ]));

        let record = run_game(0, &config, &client).await.unwrap();
        assert_eq!(record.turn_count, 2);
        assert_eq!(record.invalid_actions.black, 1);
        assert_eq!(record.invalid_actions.white, 0);
        assert!(record.steps[0].invalid_action);
    }

    #[tokio::test]
    async fn replay_invalid_games_discards_failed_attempts() {
        let pass_index = ActionCodec::new(&hexgo_core::Board::new(1)).pass_action_index();
        let config = EvalConfig {
            black_agent: AgentConfig::model("black-mock".to_string(), None),
            white_agent: AgentConfig::model("white-mock".to_string(), None),
            command_timeout: Duration::from_secs(1),
            max_command_output_bytes: DEFAULT_MAX_COMMAND_OUTPUT_BYTES,
            board_radius: 1,
            games: 1,
            max_turns: 0,
            replay_invalid_games: true,
            max_game_attempts: 2,
            decision_retries: 0,
            decision_retry_backoff: Duration::from_millis(0),
        };
        let client = MockAgentClient::new(HashMap::from([
            (
                "black-mock".to_string(),
                vec![
                    Err("transient failure".to_string()),
                    Ok(AgentDecision {
                        action_index: pass_index,
                        reason: "pass".to_string(),
                    }),
                ],
            ),
            (
                "white-mock".to_string(),
                vec![Ok(AgentDecision {
                    action_index: pass_index,
                    reason: "pass".to_string(),
                })],
            ),
        ]));

        let record = run_counted_game(0, &config, &client).await.unwrap();
        assert!(record.counted);
        assert_eq!(record.attempt_index, 2);
        assert_eq!(record.replayed_attempts.len(), 1);
        assert_eq!(record.invalid_actions.total(), 0);
    }

    #[tokio::test]
    async fn command_agents_can_finish_a_game_with_double_pass() {
        let pass_script = write_strategy_script(
            "pass",
            r#"printf '%s\n' '{"action_index":7,"reason":"script pass"}'"#,
        );
        let config = command_vs_command_config(&pass_script, &pass_script, Duration::from_secs(5));
        let client = EvalAgentClient {
            openai: None,
            command_timeout: config.command_timeout,
            max_command_output_bytes: config.max_command_output_bytes,
        };

        let record = run_game(0, &config, &client).await.unwrap();
        assert_eq!(record.turn_count, 2);
        assert_eq!(record.invalid_actions.total(), 0);
        assert_eq!(record.steps[0].agent_kind, "command");
        assert_eq!(record.black_agent.kind, "command");
        assert_eq!(record.white_agent.kind, "command");
    }

    #[tokio::test]
    async fn command_agent_bad_json_falls_back_and_is_counted() {
        let bad_script = write_strategy_script("bad-json", r#"printf '%s\n' 'not json'"#);
        let pass_script = write_strategy_script(
            "pass",
            r#"printf '%s\n' '{"action_index":7,"reason":"script pass"}'"#,
        );
        let config = command_vs_command_config(&bad_script, &pass_script, Duration::from_secs(5));
        let client = EvalAgentClient {
            openai: None,
            command_timeout: config.command_timeout,
            max_command_output_bytes: config.max_command_output_bytes,
        };

        let record = run_game(0, &config, &client).await.unwrap();
        assert_eq!(record.invalid_actions.black, 1);
        assert_eq!(record.invalid_actions.white, 0);
        assert!(record.steps[0].invalid_action);
    }

    #[tokio::test]
    async fn command_agent_illegal_action_falls_back_and_is_counted() {
        let illegal_script = write_strategy_script(
            "illegal",
            r#"printf '%s\n' '{"action_index":99,"reason":"bad"}'"#,
        );
        let pass_script = write_strategy_script(
            "pass",
            r#"printf '%s\n' '{"action_index":7,"reason":"script pass"}'"#,
        );
        let config =
            command_vs_command_config(&illegal_script, &pass_script, Duration::from_secs(5));
        let client = EvalAgentClient {
            openai: None,
            command_timeout: config.command_timeout,
            max_command_output_bytes: config.max_command_output_bytes,
        };

        let record = run_game(0, &config, &client).await.unwrap();
        assert_eq!(record.invalid_actions.black, 1);
        assert!(record.steps[0]
            .error
            .as_deref()
            .unwrap_or("")
            .contains("illegal action_index"));
    }

    #[tokio::test]
    async fn command_agent_timeout_falls_back_and_is_counted() {
        let slow_script = write_strategy_script("slow", "sleep 1");
        let pass_script = write_strategy_script(
            "pass",
            r#"printf '%s\n' '{"action_index":7,"reason":"script pass"}'"#,
        );
        let config =
            command_vs_command_config(&slow_script, &pass_script, Duration::from_millis(50));
        let client = EvalAgentClient {
            openai: None,
            command_timeout: config.command_timeout,
            max_command_output_bytes: config.max_command_output_bytes,
        };

        let record = run_game(0, &config, &client).await.unwrap();
        assert_eq!(record.invalid_actions.black, 1);
        assert!(record.steps[0]
            .error
            .as_deref()
            .unwrap_or("")
            .contains("timed out"));
    }

    #[tokio::test]
    async fn mixed_model_and_command_agents_can_run() {
        let pass_script = write_strategy_script(
            "pass",
            r#"printf '%s\n' '{"action_index":7,"reason":"script pass"}'"#,
        );
        let config = EvalConfig {
            black_agent: AgentConfig::model("black-mock".to_string(), None),
            white_agent: AgentConfig::command(pass_script, Some("white-script".to_string()))
                .unwrap(),
            command_timeout: Duration::from_secs(1),
            max_command_output_bytes: DEFAULT_MAX_COMMAND_OUTPUT_BYTES,
            board_radius: 1,
            games: 1,
            max_turns: 0,
            replay_invalid_games: false,
            max_game_attempts: 1,
            decision_retries: 0,
            decision_retry_backoff: Duration::from_millis(0),
        };
        let client = MockAgentClient::new(HashMap::from([(
            "black-mock".to_string(),
            vec![Ok(AgentDecision {
                action_index: 7,
                reason: "mock pass".to_string(),
            })],
        )]));

        let record = run_game(0, &config, &client).await.unwrap();
        assert_eq!(record.turn_count, 2);
        assert_eq!(record.invalid_actions.total(), 0);
        assert_eq!(record.steps[0].agent_kind, "model");
        assert_eq!(record.steps[1].agent_kind, "command");
    }

    #[tokio::test]
    async fn command_agent_output_limit_is_enforced() {
        let noisy_script = write_strategy_script("noisy", "printf '%0100d' 0");
        let agent = AgentConfig::command(noisy_script, None).unwrap();
        let observation = test_observation();
        let error = choose_command_action(
            &agent,
            Player::Black,
            &observation,
            Duration::from_secs(5),
            16,
        )
        .await
        .unwrap_err();
        assert!(error.to_string().contains("max-command-output-bytes"));
    }

    #[test]
    fn parse_agent_decision_repairs_missing_action_index_colon() {
        let observation = test_observation();
        let decision =
            parse_agent_decision(r#"{"action_index2,"reason":"typo"}"#, &observation).unwrap();
        assert_eq!(decision.action_index, 2);
    }

    #[test]
    fn candidate_actions_are_limited_and_include_center_opening() {
        let observation = test_observation();
        let center_index = observation
            .ordered_coords
            .iter()
            .position(|coord| coord.q == 0 && coord.r == 0)
            .unwrap();
        let candidates = candidate_actions_for_prompt(&observation, 3);
        assert_eq!(candidates.len(), 3);
        assert!(candidates.iter().any(|candidate| {
            candidate.get("action_index").and_then(Value::as_u64) == Some(center_index as u64)
        }));
    }

    #[test]
    fn parse_agent_decision_rejects_legal_action_outside_candidates() {
        let observation = test_observation();
        let allowed = vec![observation.legal_action_indices[0]];
        let other_legal = observation
            .legal_action_indices
            .iter()
            .copied()
            .find(|index| *index != allowed[0])
            .unwrap();
        let error = parse_agent_decision_with_allowed(
            &format!(r#"{{"action_index": {other_legal}, "reason": "legal but not offered"}}"#),
            &observation,
            &allowed,
        )
        .unwrap_err();
        assert!(error.to_string().contains("outside allowed action indices"));
    }

    fn test_observation() -> Observation {
        let engine = MatchEngine::new(RulesConfig::new(1, ScoringMode::AutoSettle));
        let codec = ActionCodec::new(&engine.board);
        engine.build_observation(Some(&codec))
    }

    fn command_vs_command_config(
        black_command: &str,
        white_command: &str,
        command_timeout: Duration,
    ) -> EvalConfig {
        EvalConfig {
            black_agent: AgentConfig::command(
                black_command.to_string(),
                Some("black-script".to_string()),
            )
            .unwrap(),
            white_agent: AgentConfig::command(
                white_command.to_string(),
                Some("white-script".to_string()),
            )
            .unwrap(),
            command_timeout,
            max_command_output_bytes: DEFAULT_MAX_COMMAND_OUTPUT_BYTES,
            board_radius: 1,
            games: 1,
            max_turns: 0,
            replay_invalid_games: false,
            max_game_attempts: 1,
            decision_retries: 0,
            decision_retry_backoff: Duration::from_millis(0),
        }
    }

    fn write_strategy_script(name: &str, body: &str) -> String {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let counter = TEST_SCRIPT_COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "hexgo-eval-{name}-{}-{nonce}-{counter}.sh",
            std::process::id()
        ));
        fs::write(&path, format!("#!/bin/sh\n{body}\n")).unwrap();
        let mut permissions = fs::metadata(&path).unwrap().permissions();
        permissions.set_mode(0o700);
        fs::set_permissions(&path, permissions).unwrap();
        path.to_string_lossy().into_owned()
    }
}
