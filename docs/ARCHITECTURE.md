# 架构说明

本项目复制 `HappyFish` 的组织方式，但按《垃圾收集者》这种小体量增量游戏做了减法。

开发前先看 [GAME_DESIGN_PLAN.md](GAME_DESIGN_PLAN.md)，后续功能优先按策划案里的阶段推进。

## Autoload

- `EventBus`：全局信号总线，系统和 UI 只通过信号沟通。
- `ConfigDB`：启动时读取场景和产物解锁升级配置。
- `GameState`：保存资源、当前场景、升级等级和已解锁产物。
- `PlatformBridge`：平台边界层，集中判断 PC / Web / 移动端 / 小游戏壳，并提供存档读写入口。
- `SaveManager`：负责存档加载、自动保存和版本迁移入口，具体读写交给 `PlatformBridge`。
- `AudioManager`：音频接口桩，后续接入音效时不用改业务代码。

## Systems

- `ProductionSystem`：处理玩家点击产物后的统一收益发放。
- `UpgradeSystem`：购买通用升级、场景产物升级和帮手。

## UI

- `HUD`：顶部现金、回收物数量和场景切换入口。
- `BottleSpawnArea`：中间产物生成区，按当前场景和已解锁产物刷出可点击目标。
- `UpgradePanel`：底部升级、场景和帮手页签，以及升级子页签。
- `GMPanel`：仅调试构建启用，按 `F1` 打开，可快捷或自定义增加现金。

## 后续扩展建议

- 新增资源类型时，优先扩展 `GameState`，再让 `EventBus` 发对应变化信号。
- 新增系统时，放在 `scripts/systems`，再挂到 `Main.tscn/Systems`。
- 新增配置表时，放在 `data/`，由 `ConfigDB` 统一加载。
- 不建议让 UI 直接改 `GameState`，UI 应调用系统方法。
- 接入小游戏平台能力时，优先扩展 `PlatformBridge`，再让业务层通过普通方法或信号使用它。
