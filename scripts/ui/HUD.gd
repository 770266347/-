extends Control
## Overlay HUD: resources and scene switch banner.

const BASE_LOGICAL_WIDTH: float = 393.0

var cash_label: Label
var bottle_label: Label
var top_panel: PanelContainer
var challenge_panel: PanelContainer
var challenge_title_label: Label
var challenge_subtitle_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.bottle_changed.connect(_on_bottle_changed)
	EventBus.scene_changed.connect(_on_scene_changed)
	_refresh()
	_refresh_scene()
	call_deferred("apply_layout", get_viewport_rect().size)


func _build() -> void:
	top_panel = PanelContainer.new()
	top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top_panel)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_panel.add_child(top_row)

	cash_label = Label.new()
	cash_label.text = "现金 0"
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_row.add_child(cash_label)

	bottle_label = Label.new()
	bottle_label.text = "回收物 0"
	bottle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_row.add_child(bottle_label)

	challenge_panel = PanelContainer.new()
	challenge_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	challenge_panel.gui_input.connect(_on_scene_switch_input)
	add_child(challenge_panel)

	var challenge_box: VBoxContainer = VBoxContainer.new()
	challenge_panel.add_child(challenge_box)

	challenge_title_label = Label.new()
	challenge_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenge_box.add_child(challenge_title_label)

	challenge_subtitle_label = Label.new()
	challenge_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenge_box.add_child(challenge_subtitle_label)


func _refresh() -> void:
	cash_label.text = "现金 %s" % BigNumber.format(GameState.currency)
	bottle_label.text = "回收物 %s" % BigNumber.format(float(GameState.bottles), 0)


func _refresh_scene() -> void:
	var next_scene_id: String = ConfigDB.get_next_scene_id(GameState.current_scene_id)
	challenge_title_label.text = ConfigDB.get_scene_name(GameState.current_scene_id)
	challenge_subtitle_label.text = "点击切换到%s" % ConfigDB.get_scene_name(next_scene_id)


func _on_currency_changed(_new_amount: float, _delta: float) -> void:
	_refresh()


func _on_bottle_changed(_new_amount: int, _delta: int) -> void:
	_refresh()


func _on_scene_changed(_scene_id: String) -> void:
	_refresh_scene()


func _on_scene_switch_input(event: InputEvent) -> void:
	var pressed: bool = false
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = event.pressed
	if pressed:
		GameState.cycle_scene()


func apply_layout(viewport_size: Vector2) -> void:
	var scale: float = _ui_scale(viewport_size)
	var margin: float = 10.0 * scale

	top_panel.position = Vector2(margin, 10.0 * scale)
	top_panel.size = Vector2(viewport_size.x - margin * 2.0, 42.0 * scale)
	top_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.13, 0.15, 0.18, 0.78), Color(0.95, 0.78, 0.36, 0.9), 2.0, 15.0, scale))

	cash_label.custom_minimum_size = Vector2((viewport_size.x - margin * 2.0) * 0.5, 30.0 * scale)
	bottle_label.custom_minimum_size = Vector2((viewport_size.x - margin * 2.0) * 0.5, 30.0 * scale)
	cash_label.add_theme_font_size_override("font_size", int(14.0 * scale))
	bottle_label.add_theme_font_size_override("font_size", int(14.0 * scale))
	_set_label_color(cash_label, Color(0.98, 1.0, 0.9, 1.0))
	_set_label_color(bottle_label, Color(0.85, 0.96, 1.0, 1.0))

	challenge_panel.position = Vector2(84.0 * scale, 62.0 * scale)
	challenge_panel.size = Vector2(222.0 * scale, 58.0 * scale)
	challenge_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.2, 0.19, 0.28, 0.92), Color(1.0, 0.8, 0.28, 1.0), 3.0, 13.0, scale))
	challenge_title_label.add_theme_font_size_override("font_size", int(19.0 * scale))
	challenge_subtitle_label.add_theme_font_size_override("font_size", int(11.0 * scale))
	_set_label_color(challenge_title_label, Color(1.0, 0.97, 0.75, 1.0))
	_set_label_color(challenge_subtitle_label, Color(0.82, 0.95, 1.0, 1.0))


func _ui_scale(viewport_size: Vector2) -> float:
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)


func _rounded_style(bg: Color, border: Color, border_width: float, radius: float, scale: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(int(border_width * scale))
	style.set_corner_radius_all(int(radius * scale))
	style.content_margin_left = 8.0 * scale
	style.content_margin_right = 8.0 * scale
	style.content_margin_top = 4.0 * scale
	style.content_margin_bottom = 4.0 * scale
	return style


func _set_label_color(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
