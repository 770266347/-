extends Control
## Debug-only currency controls. Toggle with F1.

const BASE_LOGICAL_WIDTH: float = 393.0

var overlay: ColorRect
var panel: PanelContainer
var cash_label: Label
var amount_input: SpinBox
var status_label: Label
var close_button: Button
var preset_buttons: Array[Button] = []
var add_button: Button


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	z_index = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	set_process_unhandled_key_input(true)
	get_tree().root.size_changed.connect(_on_viewport_size_changed)
	EventBus.currency_changed.connect(_on_currency_changed)
	call_deferred("apply_layout", get_viewport_rect().size)


func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var keycode: Key = key_event.keycode if key_event.keycode != KEY_NONE else key_event.physical_keycode
	if keycode == KEY_F1:
		_set_open(not visible)
		get_viewport().set_input_as_handled()
	elif keycode == KEY_ESCAPE and visible:
		_set_open(false)
		get_viewport().set_input_as_handled()


func _build() -> void:
	overlay = ColorRect.new()
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.color = Color(0.03, 0.04, 0.05, 0.66)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	panel.add_child(box)

	var title_row: HBoxContainer = HBoxContainer.new()
	box.add_child(title_row)

	var title: Label = Label.new()
	title.text = "GM 调试面板"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title)

	close_button = Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "关闭 GM 面板"
	close_button.pressed.connect(func(): _set_open(false))
	title_row.add_child(close_button)

	cash_label = Label.new()
	cash_label.text = "当前现金：0 元"
	box.add_child(cash_label)

	var amount_row: HBoxContainer = HBoxContainer.new()
	box.add_child(amount_row)

	var amount_label: Label = Label.new()
	amount_label.text = "自定义金额"
	amount_row.add_child(amount_label)

	amount_input = SpinBox.new()
	amount_input.min_value = 1.0
	amount_input.max_value = 1000000000000.0
	amount_input.step = 100.0
	amount_input.value = 1000.0
	amount_input.allow_greater = true
	amount_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(amount_input)

	var preset_row: HBoxContainer = HBoxContainer.new()
	box.add_child(preset_row)
	var presets: Array = [100.0, 1000.0, 10000.0, 1000000.0]
	for preset in presets:
		var amount: float = float(preset)
		var btn: Button = Button.new()
		btn.text = "+%s" % BigNumber.format(amount)
		btn.tooltip_text = "增加 %s 元" % BigNumber.format(amount)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_add_money.bind(amount))
		preset_row.add_child(btn)
		preset_buttons.append(btn)

	add_button = Button.new()
	add_button.text = "增加自定义金额"
	add_button.pressed.connect(_on_add_custom_pressed)
	box.add_child(add_button)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = "F1 开关面板，Esc 关闭"
	box.add_child(status_label)


func _set_open(is_open: bool) -> void:
	visible = is_open
	if not is_open:
		return
	_refresh_cash()
	status_label.text = "F1 开关面板，Esc 关闭"
	call_deferred("_focus_amount_input")
	call_deferred("apply_layout", get_viewport_rect().size)


func _on_add_custom_pressed() -> void:
	_add_money(float(amount_input.value))


func _add_money(amount: float) -> void:
	if amount <= 0.0:
		status_label.text = "金额必须大于 0"
		return
	GameState.add_currency(amount)
	SaveManager.save_game()
	status_label.text = "已增加 %s 元" % BigNumber.format(amount)
	_refresh_cash()


func _refresh_cash() -> void:
	if cash_label != null:
		cash_label.text = "当前现金：%s 元" % BigNumber.format(GameState.currency)


func _focus_amount_input() -> void:
	if amount_input == null:
		return
	var line_edit: LineEdit = amount_input.get_line_edit()
	line_edit.grab_focus()
	line_edit.select_all()


func _on_currency_changed(_new_amount: float, _delta: float) -> void:
	if visible:
		_refresh_cash()


func _on_viewport_size_changed() -> void:
	apply_layout(get_viewport_rect().size)


func apply_layout(viewport_size: Vector2) -> void:
	if panel == null:
		return
	var scale: float = maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)
	var panel_width: float = minf(340.0 * scale, viewport_size.x - 32.0 * scale)
	var panel_height: float = 250.0 * scale
	panel.size = Vector2(panel_width, panel_height)
	panel.position = (viewport_size - panel.size) * 0.5
	panel.add_theme_stylebox_override("panel", _panel_style(scale))
	close_button.custom_minimum_size = Vector2(30.0 * scale, 30.0 * scale)
	close_button.add_theme_font_size_override("font_size", int(13.0 * scale))
	cash_label.add_theme_font_size_override("font_size", int(15.0 * scale))
	amount_input.custom_minimum_size = Vector2(0.0, 34.0 * scale)
	add_button.custom_minimum_size = Vector2(0.0, 36.0 * scale)
	add_button.add_theme_font_size_override("font_size", int(13.0 * scale))
	status_label.add_theme_font_size_override("font_size", int(11.0 * scale))
	for btn in preset_buttons:
		btn.custom_minimum_size = Vector2(0.0, 32.0 * scale)
		btn.add_theme_font_size_override("font_size", int(11.0 * scale))


func _panel_style(scale: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.97, 0.94, 0.99)
	style.border_color = Color(0.24, 0.3, 0.28, 1.0)
	style.set_border_width_all(int(2.0 * scale))
	style.set_corner_radius_all(int(8.0 * scale))
	style.content_margin_left = 14.0 * scale
	style.content_margin_right = 14.0 * scale
	style.content_margin_top = 12.0 * scale
	style.content_margin_bottom = 12.0 * scale
	return style
