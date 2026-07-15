extends Control
## Overlay HUD: resources, challenge banner, and bottom tabs.

const BASE_LOGICAL_WIDTH: float = 393.0

var cash_label: Label
var bottle_label: Label
var rate_label: Label
var level_label: Label
var top_panel: PanelContainer
var challenge_panel: PanelContainer
var challenge_title_label: Label
var challenge_subtitle_label: Label
var bottom_nav: HBoxContainer
var save_button: Button
var reset_button: Button
var item_tab: Button
var skill_tab: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.bottle_changed.connect(_on_bottle_changed)
	EventBus.production_changed.connect(_on_production_changed)
	EventBus.save_written.connect(func(): EventBus.toast.emit("已保存"))
	_refresh()
	call_deferred("apply_layout", get_viewport_rect().size)


func _build() -> void:
	top_panel = PanelContainer.new()
	top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top_panel)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_panel.add_child(top_row)

	level_label = Label.new()
	level_label.text = "成长 1"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_row.add_child(level_label)

	cash_label = Label.new()
	cash_label.text = "现金 0"
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_row.add_child(cash_label)

	bottle_label = Label.new()
	bottle_label.text = "瓶子 0"
	bottle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_row.add_child(bottle_label)

	rate_label = Label.new()
	rate_label.text = "0 / 秒"
	rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_row.add_child(rate_label)

	challenge_panel = PanelContainer.new()
	challenge_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(challenge_panel)

	var challenge_box: VBoxContainer = VBoxContainer.new()
	challenge_panel.add_child(challenge_box)

	challenge_title_label = Label.new()
	challenge_title_label.text = "进入挑战"
	challenge_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenge_box.add_child(challenge_title_label)

	challenge_subtitle_label = Label.new()
	challenge_subtitle_label.text = "街道回收称号晋升"
	challenge_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenge_box.add_child(challenge_subtitle_label)

	bottom_nav = HBoxContainer.new()
	bottom_nav.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bottom_nav)

	item_tab = Button.new()
	item_tab.text = "物品"
	bottom_nav.add_child(item_tab)

	skill_tab = Button.new()
	skill_tab.text = "技能"
	bottom_nav.add_child(skill_tab)

	save_button = Button.new()
	save_button.text = "保存"
	save_button.pressed.connect(func(): SaveManager.save_game())
	add_child(save_button)

	reset_button = Button.new()
	reset_button.text = "重置"
	reset_button.pressed.connect(_on_reset_pressed)
	add_child(reset_button)


func _refresh() -> void:
	cash_label.text = "现金 %s" % BigNumber.format(GameState.currency)
	bottle_label.text = "瓶子 %s" % BigNumber.format(float(GameState.bottles), 0)
	rate_label.text = "%s / 秒" % BigNumber.format(GameState.get_production_per_second())


func _on_currency_changed(_new_amount: float, _delta: float) -> void:
	_refresh()


func _on_bottle_changed(_new_amount: int, _delta: int) -> void:
	_refresh()


func _on_production_changed(_per_second: float) -> void:
	_refresh()


func _on_reset_pressed() -> void:
	SaveManager.delete_save()
	GameState.reset_to_default()
	EventBus.toast.emit("已重置")
	get_tree().reload_current_scene()


func apply_layout(viewport_size: Vector2) -> void:
	var scale: float = _ui_scale(viewport_size)
	var margin: float = 10.0 * scale
	var panel_top: float = _bottom_panel_top(viewport_size, scale)

	top_panel.position = Vector2(margin, 10.0 * scale)
	top_panel.size = Vector2(viewport_size.x - margin * 2.0, 42.0 * scale)
	top_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.13, 0.15, 0.18, 0.78), Color(0.95, 0.78, 0.36, 0.9), 2.0, 15.0, scale))

	level_label.custom_minimum_size = Vector2(72.0 * scale, 30.0 * scale)
	cash_label.custom_minimum_size = Vector2(104.0 * scale, 30.0 * scale)
	bottle_label.custom_minimum_size = Vector2(104.0 * scale, 30.0 * scale)
	rate_label.custom_minimum_size = Vector2(78.0 * scale, 30.0 * scale)
	level_label.add_theme_font_size_override("font_size", int(12.0 * scale))
	cash_label.add_theme_font_size_override("font_size", int(14.0 * scale))
	bottle_label.add_theme_font_size_override("font_size", int(14.0 * scale))
	rate_label.add_theme_font_size_override("font_size", int(12.0 * scale))
	_set_label_color(level_label, Color(1.0, 0.93, 0.58, 1.0))
	_set_label_color(cash_label, Color(0.98, 1.0, 0.9, 1.0))
	_set_label_color(bottle_label, Color(0.85, 0.96, 1.0, 1.0))
	_set_label_color(rate_label, Color(0.9, 1.0, 0.9, 1.0))

	challenge_panel.position = Vector2(84.0 * scale, 62.0 * scale)
	challenge_panel.size = Vector2(222.0 * scale, 58.0 * scale)
	challenge_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.2, 0.19, 0.28, 0.92), Color(1.0, 0.8, 0.28, 1.0), 3.0, 13.0, scale))
	challenge_title_label.add_theme_font_size_override("font_size", int(19.0 * scale))
	challenge_subtitle_label.add_theme_font_size_override("font_size", int(11.0 * scale))
	_set_label_color(challenge_title_label, Color(1.0, 0.97, 0.75, 1.0))
	_set_label_color(challenge_subtitle_label, Color(0.82, 0.95, 1.0, 1.0))

	bottom_nav.position = Vector2(0.0, panel_top - 42.0 * scale)
	bottom_nav.size = Vector2(190.0 * scale, 42.0 * scale)
	item_tab.custom_minimum_size = Vector2(96.0 * scale, 42.0 * scale)
	skill_tab.custom_minimum_size = Vector2(92.0 * scale, 42.0 * scale)
	item_tab.add_theme_font_size_override("font_size", int(18.0 * scale))
	skill_tab.add_theme_font_size_override("font_size", int(17.0 * scale))
	item_tab.add_theme_stylebox_override("normal", _rounded_style(Color(1.0, 0.86, 0.36, 1.0), Color(0.22, 0.18, 0.16, 1.0), 2.0, 7.0, scale))
	skill_tab.add_theme_stylebox_override("normal", _rounded_style(Color(0.16, 0.15, 0.18, 0.96), Color(0.22, 0.18, 0.16, 1.0), 2.0, 7.0, scale))
	skill_tab.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))

	save_button.position = Vector2(margin, 56.0 * scale)
	reset_button.position = Vector2(margin + 62.0 * scale, 56.0 * scale)
	save_button.custom_minimum_size = Vector2(56.0 * scale, 28.0 * scale)
	reset_button.custom_minimum_size = Vector2(56.0 * scale, 28.0 * scale)
	save_button.add_theme_font_size_override("font_size", int(10.0 * scale))
	reset_button.add_theme_font_size_override("font_size", int(10.0 * scale))


func _bottom_panel_top(viewport_size: Vector2, scale: float) -> float:
	var margin: float = 16.0 * scale
	var panel_height: float = minf(218.0 * scale, maxf(190.0 * scale, viewport_size.y * 0.255))
	return viewport_size.y - panel_height - margin


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
