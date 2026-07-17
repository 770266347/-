extends Control
## Root scene. Holds system nodes and responsive layout.

const IPHONE16_LOGICAL_SIZE: Vector2i = Vector2i(393, 852)
const BASE_LOGICAL_WIDTH: float = 393.0
const MARGIN_PT: float = 16.0
const TOP_HEIGHT_PT: float = 122.0
const BOTTLE_TOP_PT: float = 0.0
const BOTTOM_PANEL_HEIGHT_PT: float = 238.0


func _ready() -> void:
	if PlatformBridge.is_desktop():
		call_deferred("_fit_desktop_test_window")
	get_tree().root.size_changed.connect(_on_size_changed)
	call_deferred("_apply_layout")


func _on_size_changed() -> void:
	_apply_layout()


func _apply_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = _ui_scale(viewport_size)
	var margin: float = MARGIN_PT * scale
	var top_height: float = TOP_HEIGHT_PT * scale
	var bottle_top: float = BOTTLE_TOP_PT * scale
	var bottom_panel_height: float = BOTTOM_PANEL_HEIGHT_PT * scale
	var hud: Control = $HUD as Control
	var bottle_area: Control = $BottleArea as Control
	var upgrade_panel: Control = $UpgradePanel as Control

	hud.position = Vector2.ZERO
	hud.size = viewport_size
	if hud.has_method("apply_layout"):
		hud.apply_layout(viewport_size)

	var panel_height: float = minf(bottom_panel_height, maxf(190.0 * scale, viewport_size.y * 0.255))
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


func _fit_desktop_test_window() -> void:
	get_window().size = IPHONE16_LOGICAL_SIZE


func _ui_scale(viewport_size: Vector2) -> float:
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)
