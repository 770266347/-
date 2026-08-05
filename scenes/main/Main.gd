extends Control
## 主场景协调器。
##
## 负责系统节点与 UI 层的组合、iPhone 16 逻辑尺寸布局，以及普通回收模式与
## 街区防守模式之间的可见性切换。具体玩法仍由各自系统和 UI 脚本承担。

# 所有布局常量使用逻辑点，_ui_scale 负责转换到实际视口像素。

const IPHONE16_LOGICAL_SIZE: Vector2i = Vector2i(393, 852)
const BASE_LOGICAL_WIDTH: float = 393.0
const MARGIN_PT: float = 16.0
const TOP_HEIGHT_PT: float = 122.0
const BOTTLE_TOP_PT: float = 0.0
const BOTTOM_PANEL_HEIGHT_PT: float = 238.0

var _defense_mode_active: bool = false


func _ready() -> void:
	## 桌面端使用手机大小测试窗口，并连接全局模式切换事件。
	if PlatformBridge.is_desktop():
		call_deferred("_fit_desktop_test_window")
	get_tree().root.size_changed.connect(_on_size_changed)
	EventBus.defense_mode_requested.connect(_open_defense_mode)
	EventBus.defense_mode_exit_requested.connect(_close_defense_mode)
	call_deferred("_apply_layout")


func _on_size_changed() -> void:
	## 窗口、旋转或小游戏容器尺寸变化时重新计算全部区域。
	_apply_layout()


func _apply_layout() -> void:
	## 自上而下确定 HUD、回收区、底部工具面板和全屏防守层的边界。
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = _ui_scale(viewport_size)
	var margin: float = MARGIN_PT * scale
	var top_height: float = TOP_HEIGHT_PT * scale
	var bottle_top: float = BOTTLE_TOP_PT * scale
	var bottom_panel_height: float = BOTTOM_PANEL_HEIGHT_PT * scale
	var hud: Control = $HUD as Control
	var bottle_area: Control = $BottleArea as Control
	var upgrade_panel: Control = $UpgradePanel as Control
	var defense_mode: Control = $DefenseMode as Control

	hud.position = Vector2.ZERO
	hud.size = viewport_size
	if hud.has_method("apply_layout"):
		hud.apply_layout(viewport_size)

	var panel_height: float = minf(bottom_panel_height, maxf(190.0 * scale, viewport_size.y * 0.28))
	var panel_top: float = maxf(top_height + 360.0 * scale, viewport_size.y - panel_height - margin)
	var bottle_height: float = maxf(430.0 * scale, panel_top - bottle_top)
	bottle_area.position = Vector2.ZERO
	bottle_area.size = Vector2(viewport_size.x, bottle_height)
	if bottle_area.has_method("apply_layout"):
		bottle_area.apply_layout(viewport_size)

	upgrade_panel.position = Vector2(margin, panel_top)
	upgrade_panel.size = Vector2(viewport_size.x - margin * 2.0, panel_height)
	if upgrade_panel.has_method("apply_layout"):
		upgrade_panel.apply_layout(viewport_size)

	defense_mode.position = Vector2.ZERO
	defense_mode.size = viewport_size
	if defense_mode.has_method("apply_layout"):
		defense_mode.apply_layout(viewport_size)


func _open_defense_mode() -> void:
	## 进入防守玩法时隐藏常规 HUD，并暂停回收场景交互。
	if _defense_mode_active or not _defense_mode_unlocked():
		return
	_defense_mode_active = true
	$HUD.visible = false
	$UpgradePanel.visible = false
	$BottleArea.visible = false
	if $BottleArea.has_method("set_defense_mode_active"):
		$BottleArea.set_defense_mode_active(true)
	if $DefenseMode.has_method("open_mode"):
		$DefenseMode.open_mode()


func _close_defense_mode() -> void:
	## 恢复普通回收界面和产物生成，不重建主场景节点。
	if not _defense_mode_active:
		return
	_defense_mode_active = false
	if $DefenseMode.has_method("close_mode"):
		$DefenseMode.close_mode()
	$BottleArea.visible = true
	$HUD.visible = true
	$UpgradePanel.visible = true
	if $BottleArea.has_method("set_defense_mode_active"):
		$BottleArea.set_defense_mode_active(false)


func _defense_mode_unlocked() -> bool:
	## 当前规则要求配置中的五个场景全部解锁后才能进入防守玩法。
	var scenes: Array = ConfigDB.get_scenes()
	if scenes.size() < 5:
		return false
	for scene in scenes:
		if not GameState.is_scene_unlocked(String(scene.get("id", ""))):
			return false
	return true


func _fit_desktop_test_window() -> void:
	## PC 只调整测试窗口外观，项目仍按 iPhone 16 视口配置渲染。
	get_window().size = IPHONE16_LOGICAL_SIZE


func _ui_scale(viewport_size: Vector2) -> float:
	## 以 393pt 为基准，并禁止窄窗口把点击区域缩得更小。
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)
