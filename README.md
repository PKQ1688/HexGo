# HexGo

HexGo 是一个基于 **Godot 4.5+** 开发的六边形棋盘围棋风格原型项目。它把落子、提子、领地判定和终局数子放在六边形网格上实现，并提供人机对战、双人对战、AI 对 AI、死子标记、悬停气数预览和威胁高亮等功能。

项目入口场景是 `res://scenes/Main.tscn`，当前默认窗口大小为 `1280x720`，默认棋盘半径为 `5`。

## 功能特性

- 六边形棋盘上的围地与提子玩法
- 支持 `玩家 vs 玩家`、`玩家 vs AI`、`AI vs 玩家`、`AI vs AI`
- 双方连续 `Pass` 后进入计分阶段
- 计分阶段可点击整串棋子切换死活标记
- 可在计分阶段选择继续对局，或确认结算直接结束
- HUD 实时显示黑白双方的 `棋子 / 领地 / 总分`
- 悬停空点时预览当前落子是否合法、会剩几气、能提几子
- 悬停棋串时显示该串当前气数
- 对受威胁棋串显示可视化危险提示
- 内置简单 / 中等 / 困难三档 AI

## 运行方式

确保本机已安装 **Godot 4.5 或更高版本**，然后在项目根目录执行：

```bash
godot --path .
```

启动后会先弹出对局设置面板：

- 黑方和白方都可以设置为 `玩家` 或 `AI`
- AI 难度可选 `简单`、`中等`、`困难`
- 点击 `开始` 后进入对局

## 基本玩法

### 对局阶段

- 点击空位落子
- `Pass` 按钮用于弃手
- 非法落子会被拒绝，例如占用已有棋位或自杀手
- HUD 会显示当前轮到哪一方，以及双方实时分数

### 预览与提示

- 鼠标悬停空位时，会显示该手是否合法、预估气数与提子数
- 鼠标悬停已有棋串时，会显示该串当前气数
- 普通对局阶段会显示非安全棋串的威胁提示

### 计分阶段

- 双方连续两次 `Pass` 后进入计分阶段
- 点击棋串可整串标记为死子，再次点击可取消
- 计分阶段可以选择继续对局，或确认计分结束对局

### 终局结算

确认计分后，结算面板会显示：

- 黑方和白方最终胜负
- 双方 `棋子 / 领地 / 合计`

当前实现采用项目内的分数拆解逻辑，结算数据由 `ScoreCalculator.gd` 和 `TerritoryResolver.gd` 驱动。

## AI 说明

- `简单`：从启发式评分最高的前几手里随机选择
- `中等`：直接选择启发式评分最佳的着手，必要时会主动 `Pass`
- `困难`：在启发式候选基础上做更深一层的搜索评估，优先级更稳定

AI 相关代码位于 `scripts/ai/`，由 `AIController.gd` 统一调度。

## 测试

项目自带可无界面运行的测试脚本。推荐在修改后按最小相关范围先跑：

```bash
godot --path . --headless -s tests/test_core.gd
godot --path . --headless -s tests/test_smoke.gd
godot --path . --headless -s tests/test_game_flow.gd
godot --path . --headless -s tests/test_ai.gd
```

各测试覆盖范围如下：

- `tests/test_core.gd`：棋盘、提子、领地、计分、威胁分析等核心规则
- `tests/test_smoke.gd`：主场景实例化与关键渲染/交互链路
- `tests/test_game_flow.gd`：回合推进、Pass、计分阶段、恢复对局、终局
- `tests/test_ai.gd`：AI 策略、AI 控制器和人机回合流转

测试脚本结束时会输出明确的通过提示。

## 项目结构

```text
scenes/                 可直接运行的场景
scenes/UI/              HUD、对局设置、终局弹窗等 UI 场景
scripts/core/           纯规则与状态管理，不依赖场景节点
scripts/render/         棋盘、棋子、领地、预览与威胁的可视化
scripts/input/          鼠标输入与落点映射
scripts/ui/             HUD、Pass、对局设置、结算面板逻辑
scripts/ai/             AI 控制器与难度策略
tests/                  headless 测试脚本
```

## 开发说明

- 目标引擎版本：**Godot 4.5+**
- 脚本语言：**GDScript 2.0**
- 核心规则尽量放在 `scripts/core/`
- UI、输入、渲染层通过信号响应状态变化，避免直接耦合修改核心状态
- `.godot/` 为编辑器生成缓存，不应手动修改

## 后续可扩展方向

- 添加贴目、悔棋、复盘与棋谱导出
- 提供更多棋盘尺寸与开局配置
- 为 AI 增加更强的搜索或评估函数
- 补充截图、GIF 或录屏到 README

## Native Core Bootstrap

仓库里现在已经新增 `native/` 工作区，用来承载“同一套规则内核，多种外壳”的方案：

- `native/crates/hexgo-core`：共享原生规则内核
- `native/crates/hexgo-godot`：未来的 Godot GDExtension 壳层
- `native/crates/hexgo-py`：未来的 Python 绑定壳层

当前阶段的重点不是替换现有 Godot 逻辑，而是先冻结共享协议并建立 parity 基线：

```bash
godot --path . --headless -s tests/export_shared_engine_fixtures.gd
cargo test --manifest-path native/Cargo.toml -p hexgo-core
```

第一条命令会导出 `tests/fixtures/shared_engine/parity_cases.json`，后续 Rust、Godot 壳层和 Python 环境都需要对齐这份规则夹具。

在 Godot 侧，`GameState.gd` 现在已经切成“native 优先，GDScript 回退”的桥接模式：

- 如果未来注册了 `HexGoNativeEngine` 或 `HexGoNativeMatchEngine` 这类 GDExtension 类，`GameState` 会优先使用它
- 如果原生桥不可用，`GameState` 会自动回退到当前的 GDScript 规则实现
- 回退状态可以通过 `GameState.get_engine_backend_info()` 或 `MatchRuntime.get_engine_backend_info()` 读取
