extends Control
## Root scene. Holds system nodes and global input shortcuts.

const IPHONE16_LOGICAL_SIZE: Vector2i = Vector2i(393, 852)
const BASE_LOGICAL_WIDTH: float = 393.0
const MARGIN_PT: float = 16.0
const TOP_HEIGHT_PT: float = 122.0
const BOTTLE_TOP_PT: float = 0.0
const BOTTOM_PANEL_HEIGHT_PT: float = 218.0
const BOTTOM_NAV_HEIGHT_PT: float = 44.0
const TOAST_SIZE_PT: Vector2 = Vector2(260.0, 74.0)


func _ready() -> void:
	if PlatformBridge.is_desktop():
		call_deferred("_fit_desktop_test_window")
	get_tree().root.size_changed.connect(_on_size_changed)
	call_deferred("_apply_layout")


func _on_size_changed() -> void:
	_apply_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			SaveManager.save_game()
		elif event.keycode == KEY_F9:
			SaveManager.delete_save()
			GameState.reset_to_default()
			EventBus.toast.emit("存档已重置")
			get_tree().reload_current_scene()


func _apply_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = _ui_scale(viewport_size)
	var margin: float = MARGIN_PT * scale
	var top_height: float = TOP_HEIGHT_PT * scale
	var bottle_top: float = BOTTLE_TOP_PT * scale
	var bottom_panel_height: float = BOTTOM_PANEL_HEIGHT_PT * scale
	var bottom_nav_height: float = BOTTOM_NAV_HEIGHT_PT * scale
	var toast_size: Vector2 = TOAST_SIZE_PT * scale
	var hud: Control = $HUD as Control
	var bottle_area: Control = $BottleArea as Control
	var generator_panel: Control = $GeneratorPanel as Control
	var upgrade_panel: Control = $UpgradePanel as Control
	var toast_bar: Control = $ToastBar as Control

	hud.position = Vector2.ZERO
	hud.size = viewport_size
	if hud.has_method("apply_layout"):
		hud.apply_layout(viewport_size)

	var panel_height: float = minf(bottom_panel_height, maxf(190.0 * scale, viewport_size.y * 0.255))
	var panel_top: float = maxf(top_height + 360.0 * scale, viewport_size.y - panel_height - margin)
	var bottle_height: float = maxf(430.0 * scale, panel_top - bottle_top - bottom_nav_height)
	bottle_area.position = Vector2.ZERO
	bottle_area.size = Vector2(viewport_size.x, bottle_height)
	if bottle_area.has_method("apply_layout"):
		bottle_area.apply_layout(viewport_size)

	var panel_width: float = maxf(160.0 * scale, (viewport_size.x - margin * 3.0) * 0.5)
	generator_panel.position = Vector2(margin, panel_top)
	generator_panel.size = Vector2(panel_width, panel_height)
	if generator_panel.has_method("apply_layout"):
		generator_panel.apply_layout(viewport_size)
	upgrade_panel.position = Vector2(margin * 2.0 + panel_width, panel_top)
	upgrade_panel.size = Vector2(panel_width, panel_height)
	if upgrade_panel.has_method("apply_layout"):
		upgrade_panel.apply_layout(viewport_size)

	toast_bar.position = Vector2(
		maxf(margin, (viewport_size.x - toast_size.x) * 0.5),
		maxf(margin, panel_top - toast_size.y - margin)
	)
	toast_bar.size = toast_size


func _fit_desktop_test_window() -> void:
	get_window().size = IPHONE16_LOGICAL_SIZE


func _ui_scale(viewport_size: Vector2) -> float:
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)
