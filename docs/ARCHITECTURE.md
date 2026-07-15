# 架构说明

本项目复制 `HappyFish` 的组织方式，但按《垃圾收集者》这种小体量增量游戏做了减法。

开发前先看 [GAME_DESIGN_PLAN.md](GAME_DESIGN_PLAN.md)，后续功能优先按策划案里的阶段推进。

## Autoload

- `EventBus`：全局信号总线，系统和 UI 只通过信号沟通。
- `ConfigDB`：启动时读取 `data/generators.json` 和 `data/upgrades.json`。
- `GameState`：保存资源、生产器等级、升级等级、派生倍率。
- `PlatformBridge`：平台边界层，集中判断 PC / Web / 移动端 / 小游戏壳，并提供存档读写入口。
- `SaveManager`：负责存档加载、自动保存和版本迁移入口，具体读写交给 `PlatformBridge`。
- `AudioManager`：音频接口桩，后续接入音效时不用改业务代码。

## Systems

- `ProductionSystem`：处理点击瓶子和每秒自动捡瓶收益。
- `GeneratorSystem`：购买自动捡瓶帮手。
- `UpgradeSystem`：购买升级并触发属性重算。

## UI

- `HUD`：顶部现金、塑料瓶、每秒产出、保存/重置按钮。
- `BottleSpawnArea`：中间瓶子生成区，负责刷出可点击的塑料瓶。
- `GeneratorPanel`：底部帮手购买列表。
- `UpgradePanel`：底部升级购买列表。
- `ToastBar`：底部提示。

## 后续扩展建议

- 新增资源类型时，优先扩展 `GameState`，再让 `EventBus` 发对应变化信号。
- 新增系统时，放在 `scripts/systems`，再挂到 `Main.tscn/Systems`。
- 新增配置表时，放在 `data/`，由 `ConfigDB` 统一加载。
- 不建议让 UI 直接改 `GameState`，UI 应调用系统方法。
- 接入小游戏平台能力时，优先扩展 `PlatformBridge`，再让业务层通过普通方法或信号使用它。
