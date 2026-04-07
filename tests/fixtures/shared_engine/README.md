# Shared Engine Fixtures

这个目录放共享原生内核的 parity fixtures。它们的职责不是给 UI 用，而是保证三套入口在相同规则下得到一致结果：

- GDScript 参考实现
- Rust `hexgo-core`
- 后续的 Godot GDExtension / Python 绑定

生成命令：

```bash
godot --path . --headless -s tests/export_shared_engine_fixtures.gd
```

导出后会生成：

- `parity_cases.json`

当前脚本会覆盖这些基础场景：

- `initial_radius_2`
- `opening_center_move`
- `single_capture`
- `double_pass_to_scoring`
- `toggle_dead_group_after_scoring`
