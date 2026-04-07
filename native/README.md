# Native Core Workspace

这个目录是方案三的第一阶段落点：把规则内核抽成一个共享的原生库，再由 Godot 和 Python 分别接入。

当前目录结构：

- `crates/hexgo-core`: 纯规则内核，不依赖 Godot 或 Python
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

同时建议先导出一版当前 GDScript 规则夹具：

```bash
godot --path . --headless -s tests/export_shared_engine_fixtures.gd
```

生成的 parity fixtures 会写到 `tests/fixtures/shared_engine/parity_cases.json`，后续 Rust、Godot 壳层和 Python 环境都要对齐它。
