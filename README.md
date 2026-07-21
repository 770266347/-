# 垃圾收集者

Godot 4.7 小体量增量游戏骨架，结构参考 `HappyFish`，但已放到当前工作区作为《垃圾收集者》的起步项目。

## 快速开始

1. 用 Godot 4.7+ 导入 `project.godot`
2. 运行主场景：`res://scenes/main/Main.tscn`
3. 中间区域会自动生成塑料瓶，点击瓶子获得塑料瓶和现金，底部购买帮手与升级

## 目录结构

```text
res://
├── autoload/        # 全局单例：事件、配置、运行时状态、平台桥、存档、音频桩
├── data/            # JSON 配置表
├── scenes/          # Godot 场景
├── scripts/
│   ├── systems/     # 纯逻辑系统：生产、生成器、升级
│   ├── ui/          # UI 脚本
│   └── utils/       # BigNumber 等工具
├── docs/            # 架构说明
├── tests/           # 预留测试
└── assets/          # 美术/音频资源
```

## 架构原则

- `ConfigDB` 冷启动读取 `data/*.json`
- `GameState` 只保存运行时状态和派生属性
- `PlatformBridge` 集中处理平台判断和存档读写入口
- `SaveManager` 通过 `PlatformBridge` 自动读写 `user://garbage_collector_save_v1.json`
- `EventBus` 负责系统和 UI 解耦
- `scripts/systems` 只做业务逻辑，不直接写 UI
- UI 只监听事件、刷新显示、调用系统方法

## 小游戏发行准备

- 项目已切到 Godot Compatibility 渲染路线，先避免 Forward Plus / D3D12 绑定。
- 已开启鼠标和触摸互相模拟，PC 上可以继续用鼠标测试点击玩法。
- 当前 UI 按 iPhone 16 竖屏物理分辨率 `1179x2556` 起步，窗口变化时会重新布局瓶子区域和底部面板。
- 平台登录、广告、分享、排行榜、云存档等 SDK 逻辑后续优先接入 `PlatformBridge`，不要写进玩法系统。
- 小程序发行建议先做 Web 导出可运行验证，再接目标平台的小游戏外壳或适配器。

## 当前玩法骨架

- 中间区域自动刷新塑料瓶
- 点击塑料瓶获得 `+1 塑料瓶` 和 `+1 元` 基础现金
- 帮手持续自动捡瓶并折算现金
- 升级提高每瓶收益或自动捡瓶效率
- 15 秒自动保存；调试构建可在 `F1` GM 面板中二次确认后重置全部数据
