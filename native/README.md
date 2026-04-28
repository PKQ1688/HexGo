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

`hexgo-eval` 可以绕开 Godot，直接用 `hexgo-core` 跑 LLM vs LLM 对局。它默认调用 OpenAI-compatible
`/chat/completions` 接口，要求模型返回：

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
  --timeout-seconds 180 \
  --max-retries 2 \
  --out native/eval-results.jsonl
```

每盘会输出一行 JSONL，包含胜者、分差、最终分数、非法动作次数和逐步动作日志。建议评测时使用偶数盘并交换黑白模型，降低先手偏差。

默认请求不会发送 `response_format`，以兼容不完整支持 OpenAI 参数的模型网关。如果目标服务明确支持
JSON mode，可以额外加 `--json-response-format`。解析器会尽量兼容模型返回的 Markdown 代码块、字符串
`action_index`、`q/r` 坐标或 `{"type":"pass"}`，但仍会记录不合法动作和接口异常，方便后续分析。
网络超时、连接失败、HTTP 429/408/5xx 会按 `--max-retries` 和 `--retry-backoff-ms` 重试；模型返回非法动作不会重试，而是作为模型响应质量问题记录。
长 prompt 棋局建议把 `--timeout-seconds` 设到 `180` 或更高，避免把慢模型误判为失败。
如果超时已经足够长，建议把 `--max-retries` 设为 `0`，避免单步动作在慢模型上等待过久。

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
