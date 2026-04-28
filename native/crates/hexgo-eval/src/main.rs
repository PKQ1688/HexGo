use std::{
    fs::OpenOptions,
    io::{self, Write},
    path::PathBuf,
    time::Duration,
};

use anyhow::{anyhow, bail, Context, Result};
use async_trait::async_trait;
use clap::Parser;
use hexgo_core::{
    Action, ActionCodec, Coord, MatchEngine, Observation, Player, RulesConfig, ScoringMode,
    ScoreBreakdown, ScoreTotals,
};
use reqwest::{Client, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::time::sleep;

const DEFAULT_BASE_URL: &str = "https://api.openai.com/v1";
const DEFAULT_API_KEY_ENV: &str = "OPENAI_API_KEY";
const DEFAULT_TIMEOUT_SECONDS: u64 = 60;
const DEFAULT_MAX_RETRIES: usize = 2;
const DEFAULT_RETRY_BACKOFF_MS: u64 = 1500;

#[derive(Debug, Parser)]
#[command(author, version, about = "Run headless HexGo LLM-vs-LLM evaluations.")]
struct Cli {
    #[arg(long)]
    black_model: String,

    #[arg(long)]
    white_model: String,

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

    #[arg(long, default_value_t = DEFAULT_TIMEOUT_SECONDS)]
    timeout_seconds: u64,

    #[arg(long, default_value_t = DEFAULT_MAX_RETRIES)]
    max_retries: usize,

    #[arg(long, default_value_t = DEFAULT_RETRY_BACKOFF_MS)]
    retry_backoff_ms: u64,

    #[arg(long)]
    json_response_format: bool,

    #[arg(long)]
    out: Option<PathBuf>,
}

#[derive(Debug, Clone)]
struct AgentConfig {
    model: String,
}

#[derive(Debug, Clone)]
struct EvalConfig {
    black_agent: AgentConfig,
    white_agent: AgentConfig,
    board_radius: i32,
    games: usize,
    max_turns: usize,
}

#[derive(Debug, Clone)]
struct OpenAiConfig {
    base_url: String,
    api_key: String,
    temperature: f32,
    timeout: Duration,
    max_retries: usize,
    retry_backoff: Duration,
    json_response_format: bool,
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
        model: &str,
        player: Player,
        observation: &Observation,
    ) -> Result<AgentDecision>;
}

struct OpenAiAgentClient {
    http: Client,
    config: OpenAiConfig,
}

impl OpenAiAgentClient {
    fn new(config: OpenAiConfig) -> Result<Self> {
        let http = Client::builder()
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
}

#[async_trait]
impl AgentClient for OpenAiAgentClient {
    async fn choose_action(
        &self,
        model: &str,
        player: Player,
        observation: &Observation,
    ) -> Result<AgentDecision> {
        let endpoint = chat_completions_endpoint(&self.config.base_url);
        let mut request_body = json!({
            "model": model,
            "temperature": self.config.temperature,
            "messages": [
                {
                    "role": "system",
                    "content": system_prompt()
                },
                {
                    "role": "user",
                    "content": user_prompt(player, observation)?
                }
            ]
        });
        if self.config.json_response_format {
            request_body["response_format"] = json!({"type": "json_object"});
        }

        let response_text = self
            .send_chat_request_with_retries(&endpoint, &request_body)
            .await?;

        let response: OpenAiChatResponse = serde_json::from_str(&response_text)
            .with_context(|| {
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

        parse_agent_decision(content, observation)
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
            match self.send_chat_request(endpoint, request_body).await {
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
    board_radius: i32,
    black_model: String,
    white_model: String,
    winner: String,
    margin: i32,
    scores: SerializableScores,
    score_breakdown: SerializableScoreBreakdown,
    move_count: usize,
    turn_count: usize,
    invalid_actions: InvalidActionCounts,
    steps: Vec<StepRecord>,
}

#[derive(Debug, Serialize)]
struct StepRecord {
    turn: usize,
    player: String,
    model: String,
    requested_action_index: Option<usize>,
    applied_action_index: usize,
    action: SerializableAction,
    reason: String,
    invalid_action: bool,
    error: Option<String>,
    accepted: bool,
    scores: SerializableScores,
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

#[derive(Debug, Default, Serialize)]
struct InvalidActionCounts {
    black: usize,
    white: usize,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let api_key = std::env::var(&cli.api_key_env)
        .with_context(|| format!("environment variable {} is not set", cli.api_key_env))?;
    if cli.games == 0 {
        bail!("--games must be greater than 0");
    }
    if cli.board_radius <= 0 {
        bail!("--board-radius must be greater than 0");
    }

    let eval_config = EvalConfig {
        black_agent: AgentConfig {
            model: cli.black_model,
        },
        white_agent: AgentConfig {
            model: cli.white_model,
        },
        board_radius: cli.board_radius,
        games: cli.games,
        max_turns: cli.max_turns,
    };
    let client = OpenAiAgentClient::new(OpenAiConfig {
        base_url: cli.base_url,
        api_key,
        temperature: cli.temperature,
        timeout: Duration::from_secs(cli.timeout_seconds),
        max_retries: cli.max_retries,
        retry_backoff: Duration::from_millis(cli.retry_backoff_ms),
        json_response_format: cli.json_response_format,
    })?;

    let mut writer = open_output(cli.out.as_ref())?;
    for game_index in 0..eval_config.games {
        let record = run_game(game_index, &eval_config, &client).await?;
        serde_json::to_writer(&mut writer, &record).context("failed to serialize game record")?;
        writer
            .write_all(b"\n")
            .context("failed to write game record newline")?;
        writer.flush().context("failed to flush game record")?;
    }

    Ok(())
}

async fn run_game(
    game_index: usize,
    config: &EvalConfig,
    client: &dyn AgentClient,
) -> Result<GameRecord> {
    let rules = RulesConfig::new(config.board_radius, ScoringMode::AutoSettle);
    let mut engine = MatchEngine::new(rules);
    engine.consume_events();
    let codec = ActionCodec::new(&engine.board);
    let mut steps = Vec::new();
    let mut invalid_actions = InvalidActionCounts::default();

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
        let model = model_for_player(config, player);
        let decision_result = client.choose_action(model, player, &observation).await;
        let (decision, error) = match decision_result {
            Ok(decision) => (decision, None),
            Err(error) => {
                let fallback_index = fallback_action_index(&observation);
                (
                    AgentDecision {
                        action_index: fallback_index,
                        reason: "fallback after invalid or unavailable LLM response".to_string(),
                    },
                    Some(format_error_chain(&error)),
                )
            }
        };

        let invalid_action = error.is_some();
        if invalid_action {
            count_invalid_action(&mut invalid_actions, player);
        }

        let action = codec
            .decode_action_index(decision.action_index)
            .ok_or_else(|| anyhow!("fallback action index {} could not be decoded", decision.action_index))?;
        let step_result = engine.step_action(action, Some(&codec));
        let accepted = step_result.accepted;
        let scores = step_result.observation.scores;

        steps.push(StepRecord {
            turn: steps.len() + 1,
            player: player_name(player).to_string(),
            model: model.to_string(),
            requested_action_index: if invalid_action {
                None
            } else {
                Some(decision.action_index)
            },
            applied_action_index: decision.action_index,
            action: serialize_action(action),
            reason: decision.reason,
            invalid_action,
            error,
            accepted,
            scores: serialize_scores(scores),
        });
    }

    let final_observation = engine.build_observation(Some(&codec));
    Ok(GameRecord {
        game_index,
        board_radius: config.board_radius,
        black_model: config.black_agent.model.clone(),
        white_model: config.white_agent.model.clone(),
        winner: final_observation
            .result
            .winner
            .map(player_name)
            .unwrap_or("draw")
            .to_string(),
        margin: final_observation.result.margin,
        scores: serialize_scores(final_observation.scores),
        score_breakdown: serialize_score_breakdown(final_observation.score_breakdown),
        move_count: final_observation.move_count,
        turn_count: steps.len(),
        invalid_actions,
        steps,
    })
}

fn parse_agent_decision(content: &str, observation: &Observation) -> Result<AgentDecision> {
    let parsed = parse_loose_json_object(content)?;
    let action_index = action_index_from_response(&parsed, observation)?;
    if !observation.legal_action_indices.contains(&action_index) {
        bail!("LLM chose illegal action_index {action_index}");
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
    if let Ok(parsed) = serde_json::from_str::<Value>(trimmed) {
        if parsed.is_object() {
            return Ok(parsed);
        }
    }

    let unfenced = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .and_then(|value| value.strip_suffix("```"))
        .map(str::trim)
        .unwrap_or(trimmed);
    if let Ok(parsed) = serde_json::from_str::<Value>(unfenced) {
        if parsed.is_object() {
            return Ok(parsed);
        }
    }

    if let Some(json_slice) = extract_first_json_object(unfenced) {
        let parsed: Value =
            serde_json::from_str(json_slice).context("extracted JSON object was invalid")?;
        if parsed.is_object() {
            return Ok(parsed);
        }
    }

    bail!(
        "LLM response did not contain a JSON object: {}",
        compact_snippet(content, 300)
    )
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
    if let Some(value) = parsed.get("action_index") {
        if let Some(index) = value.as_u64() {
            return Ok(index as usize);
        }
        if let Some(index_text) = value.as_str() {
            return index_text
                .trim()
                .parse::<usize>()
                .context("LLM action_index string was not an integer");
        }
    }

    if parsed
        .get("type")
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
        .context("LLM response is missing action_index, pass type, or q/r coord")
}

fn action_index_from_coord_values(q: Option<&Value>, r: Option<&Value>, observation: &Observation) -> Result<usize> {
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
        return text.trim().parse::<i32>().context("string is not an integer");
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

fn model_for_player(config: &EvalConfig, player: Player) -> &str {
    match player {
        Player::Black => &config.black_agent.model,
        Player::White => &config.white_agent.model,
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
    "You are playing HexGo, a hex-grid Go-like game. Choose exactly one legal action from the supplied legal_actions. Prefer returning an action_index. Reply with only JSON in this shape: {\"action_index\": number, \"reason\": string}."
}

fn user_prompt(player: Player, observation: &Observation) -> Result<String> {
    let body = json!({
        "player": player_name(player),
        "objective": "Maximize your final total score. Black and white score pieces plus territory.",
        "rules": {
            "board_radius": observation.board_radius,
            "scoring_mode": observation.rules.scoring_mode.as_str(),
            "pass_action_index": observation.pass_action_index,
            "double_pass_ends_game": true
        },
        "state": serialize_observation_for_prompt(observation),
        "legal_actions": legal_actions_for_prompt(observation),
        "required_response": {
            "action_index": "one integer from legal_action_indices",
            "alternative": "you may return {\"q\": number, \"r\": number, \"reason\": string} or {\"type\": \"pass\", \"reason\": string}",
            "reason": "short explanation"
        }
    });
    serde_json::to_string(&body).context("failed to serialize prompt observation")
}

fn serialize_observation_for_prompt(observation: &Observation) -> Value {
    let cells = observation
        .ordered_coords
        .iter()
        .zip(observation.cells.iter())
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
        "current_player": player_name(observation.current_player),
        "move_count": observation.move_count,
        "consecutive_passes": observation.consecutive_passes,
        "scores": serialize_scores(observation.scores),
        "legal_action_indices": &observation.legal_action_indices,
        "cells": cells,
    })
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
    use std::sync::Mutex;

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
            model: &str,
            _player: Player,
            _observation: &Observation,
        ) -> Result<AgentDecision> {
            let mut decisions = self.decisions.lock().unwrap();
            let queue = decisions
                .get_mut(model)
                .ok_or_else(|| anyhow!("missing mock model {model}"))?;
            if queue.is_empty() {
                bail!("mock model {model} has no remaining decisions");
            }
            queue
                .remove(0)
                .map_err(|message: String| anyhow!(message))
        }
    }

    #[test]
    fn parse_agent_decision_rejects_illegal_action() {
        let observation = test_observation();
        let error =
            parse_agent_decision(r#"{"action_index": 99, "reason": "bad"}"#, &observation)
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
            parse_agent_decision(r#"{"q": 0, "r": 0, "reason": "center"}"#, &observation)
                .unwrap();
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
            black_agent: AgentConfig {
                model: "black-mock".to_string(),
            },
            white_agent: AgentConfig {
                model: "white-mock".to_string(),
            },
            board_radius: 1,
            games: 1,
            max_turns: 0,
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
            black_agent: AgentConfig {
                model: "black-mock".to_string(),
            },
            white_agent: AgentConfig {
                model: "white-mock".to_string(),
            },
            board_radius: 1,
            games: 1,
            max_turns: 0,
        };
        let pass_index = ActionCodec::new(&hexgo_core::Board::new(1)).pass_action_index();
        let client = MockAgentClient::new(HashMap::from([
            (
                "black-mock".to_string(),
                vec![Err("bad json".to_string())],
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
        assert_eq!(record.invalid_actions.black, 1);
        assert_eq!(record.invalid_actions.white, 0);
        assert!(record.steps[0].invalid_action);
    }

    fn test_observation() -> Observation {
        let engine = MatchEngine::new(RulesConfig::new(1, ScoringMode::AutoSettle));
        let codec = ActionCodec::new(&engine.board);
        engine.build_observation(Some(&codec))
    }
}
