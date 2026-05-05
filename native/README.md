# Native Core Workspace

这个目录是方案三的第一阶段落点：把规则内核抽成一个共享的原生库，再由 Godot 和 Python 分别接入。

当前目录结构：

- `crates/hexgo-core`: 纯规则内核，不依赖 Godot 或 Python
- `crates/hexgo-eval`: 基于共享内核的 headless LLM 对战评测 CLI
- `crates/hexgo-godot`: 未来的 Godot GDExtension 壳层
- `crates/hexgo-py`: 未来的 Python 绑定壳层

第一阶段已经落下来的约束：

- 动作空间统一为 `action_index`，最后一个索引恒为 `pass`
- 观测结构、事件结构和 replay/parity fixture 统一走协议化字段
- `hexgo-core` 先覆盖棋盘、提子、领地、计分、回合推进和 `manual_review / auto_settle`
- Godot 现有逻辑继续保留，先作为 parity fixture 的参考实现

本地准备好 Rust 工具链后，可以先跑：

```bash
cargo test --manifest-path native/Cargo.toml -p hexgo-core
```

## LLM 对战评测

`hexgo-eval` 可以绕开 Godot，直接用 `hexgo-core` 跑模型或外部代码策略对局。模型代理会先用和
Godot LLM agent 相同的思路筛出启发式 top-K 候选动作，默认 `--candidate-count 8`，再调用
OpenAI-compatible `/chat/completions` 接口。模型只需要从 `candidate_action_indices` 里选一个动作：

```json
{"action_index": 0, "reason": "short explanation"}
```

示例：

```bash
export OPENAI_API_KEY="..."
cargo run --manifest-path native/Cargo.toml -p hexgo-eval -- \
  --black-model gpt-4.1-mini \
  --white-model other-openai-compatible-model \
  --base-url https://api.openai.com/v1 \
  --games 2 \
  --board-radius 3 \
  --max-turns 120 \
  --candidate-count 8 \
  --timeout-seconds 180 \
  --max-retries 0 \
  --out native/eval-results.jsonl
```

也可以把某一方换成外部命令策略。评测器每回合会启动一次命令，把 observation JSON 写入 stdin，
并从 stdout 读取动作 JSON：

```bash
cargo run --manifest-path native/Cargo.toml -p hexgo-eval -- \
  --black-command "python3 native/examples/simple_strategy.py" \
  --black-name simple-python \
  --white-model glm-5.1 \
  --base-url https://ark.ap-southeast.bytepluses.com/api/coding/v3 \
  --api-key-env ARK_API_KEY \
  --games 2 \
  --board-radius 3 \
  --max-turns 120 \
  --out native/eval-results.jsonl
```

代码策略必须在 stdout 输出紧凑 JSON：

```json
{"action_index": 0, "reason": "short explanation"}
```

stdin 输入包含 `player`、`state`、`legal_actions`、`legal_action_indices` 和 `pass_action_index`。
`native/examples/simple_strategy.py` 是最小 Python 示例；它会优先走中心点，否则选择第一个合法落子。
命令参数按引号拆成 argv 后直接执行，不经过 shell。路径或参数含空格时要加引号，例如
`--black-command "python3 'native/my strategies/qwen.py'"`。

外部策略默认每步最多运行 `3` 秒，stdout+stderr 最多 `65536` 字节，可用
`--command-timeout-seconds` 和 `--max-command-output-bytes` 调整。V1 没有 Docker/podman 级沙箱，
只运行你信任的策略代码；如果比赛规则要求禁网，需要在运行环境层面限制。

Qwen Code 适合用来生成参赛策略，但不由评测器自动调用。可以先让不同模型写出策略文件，再把策略文件交给
`hexgo-eval` 对战：

```bash
qwen -m glm-5.1 -p "根据 HexGo stdin/stdout 协议写一个 Python 策略，只输出代码。"
qwen -m kimi-k2.5 -p "根据 HexGo stdin/stdout 协议写一个 Python 策略，只输出代码。"
qwen -m dola-seed-2.0-pro -p "根据 HexGo stdin/stdout 协议写一个 Python 策略，只输出代码。"
qwen -m glm-4.7 -p "根据 HexGo stdin/stdout 协议写一个 Python 策略，只输出代码。"
qwen -m gpt-oss-120b -p "根据 HexGo stdin/stdout 协议写一个 Python 策略，只输出代码。"
```

每盘会输出一行 JSONL，包含胜者、分差、最终分数、非法动作次数和逐步动作日志。建议评测时使用偶数盘并交换黑白模型，降低先手偏差。
JSONL 继续保留旧的 `black_model`、`white_model` 和 step 内 `model` 字段；同时新增结构化
`black_agent`、`white_agent` 和 step 内 `agent_kind`，用于区分模型代理和命令策略。

默认请求不会发送 `response_format`，以兼容不完整支持 OpenAI 参数的模型网关。如果目标服务明确支持
JSON mode，可以额外加 `--json-response-format`。解析器会尽量兼容模型返回的 Markdown 代码块、字符串
`action_index`、`q/r` 坐标或 `{"type":"pass"}`，但仍会记录不合法动作和接口异常，方便后续分析。
模型代理默认只接受候选集里的动作；外部命令策略仍接收完整 `legal_actions`，适合写搜索/启发式程序。
网络超时、连接失败、HTTP 429/408/5xx 会按 `--max-retries` 和 `--retry-backoff-ms` 重试；模型返回非法动作不会重试，而是作为模型响应质量问题记录。
长 prompt 棋局建议把 `--timeout-seconds` 设到 `180` 或更高，避免把慢模型误判为失败。
如果超时已经足够长，建议把 `--max-retries` 设为 `0`，避免单步动作在慢模型上等待过久。
Ark 脚本默认使用 `--curl-client`、关闭 `response_format`，并可用 `MODELS_CSV=glm-5.1,glm-4.7` 指定参赛模型。

Godot 的 GDExtension 配置默认不启用，避免未构建原生库时启动项目报错。
如果要启用 Godot 原生桥接，先构建动态库，再复制本地配置：

```bash
cargo build --manifest-path native/Cargo.toml -p hexgo-godot
cp native/hexgo_native.gdextension.example native/hexgo_native.gdextension
```

同时建议先导出一版当前 GDScript 规则夹具：

```bash
godot --path . --headless -s tests/export_shared_engine_fixtures.gd
```

生成的 parity fixtures 会写到 `tests/fixtures/shared_engine/parity_cases.json`，后续 Rust、Godot 壳层和 Python 环境都要对齐它。
