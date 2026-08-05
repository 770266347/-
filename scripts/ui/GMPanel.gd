extends Control
## Debug-only currency controls. Toggle with F1.

const BASE_LOGICAL_WIDTH: float = 393.0

var overlay: ColorRect
var panel: PanelContainer
var panel_box: VBoxContainer
var title_label: Label
var cash_label: Label
var amount_label: Label
var amount_input: SpinBox
var status_label: Label
var close_button: Button
var preset_buttons: Array[Button] = []
var add_button: Button
var reset_button: Button
var reset_confirmation: ConfirmationDialog


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	z_index = 4096
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

	panel_box = VBoxContainer.new()
	panel.add_child(panel_box)

	var title_row: HBoxContainer = HBoxContainer.new()
	panel_box.add_child(title_row)

	title_label = Label.new()
	title_label.text = "GM 调试面板"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title_label)

	close_button = Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "关闭 GM 面板"
	close_button.pressed.connect(func(): _set_open(false))
	title_row.add_child(close_button)

	cash_label = Label.new()
	cash_label.text = "当前现金：0 元"
	panel_box.add_child(cash_label)

	var amount_row: HBoxContainer = HBoxContainer.new()
	panel_box.add_child(amount_row)

	amount_label = Label.new()
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
	panel_box.add_child(preset_row)
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
	panel_box.add_child(add_button)

	var separator: HSeparator = HSeparator.new()
	panel_box.add_child(separator)

	reset_button = Button.new()
	reset_button.text = "重置全部数据"
	reset_button.tooltip_text = "清空现金、回收物、升级、场景、帮手、天赋和场景库存"
	reset_button.pressed.connect(_on_reset_requested)
	panel_box.add_child(reset_button)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = "F1 开关面板，Esc 关闭"
	panel_box.add_child(status_label)

	reset_confirmation = ConfirmationDialog.new()
	reset_confirmation.title = "确认重置"
	reset_confirmation.dialog_text = "确定要清空全部游戏数据吗？\n此操作无法撤销。"
	reset_confirmation.ok_button_text = "确认重置"
	reset_confirmation.cancel_button_text = "取消"
	reset_confirmation.confirmed.connect(_reset_all_data)
	add_child(reset_confirmation)


func _set_open(is_open: bool) -> void:
	visible = is_open
	if not is_open:
		if reset_confirmation != null:
			reset_confirmation.hide()
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


func _on_reset_requested() -> void:
	if reset_confirmation == null:
		return
	var scale: float = maxf(1.0, get_viewport_rect().size.x / BASE_LOGICAL_WIDTH)
	reset_confirmation.popup_centered(Vector2i(int(330.0 * scale), int(190.0 * scale)))


func _reset_all_data() -> void:
	SaveManager.delete_save()
	GameState.reset_to_default()
	SaveManager.save_game()
	amount_input.value = 1000.0
	status_label.text = "所有游戏数据已重置"
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
	var panel_width: float = minf(370.0 * scale, viewport_size.x - 20.0 * scale)
	var panel_height: float = 370.0 * scale
	panel.size = Vector2(panel_width, panel_height)
	panel.position = (viewport_size - panel.size) * 0.5
	panel.add_theme_stylebox_override("panel", _panel_style(scale))
	panel_box.add_theme_constant_override("separation", int(8.0 * scale))
	title_label.add_theme_font_size_override("font_size", int(20.0 * scale))
	title_label.add_theme_color_override("font_color", Color(0.1, 0.16, 0.14, 1.0))
	close_button.custom_minimum_size = Vector2(38.0 * scale, 38.0 * scale)
	close_button.add_theme_font_size_override("font_size", int(16.0 * scale))
	cash_label.add_theme_font_size_override("font_size", int(18.0 * scale))
	cash_label.add_theme_color_override("font_color", Color(0.14, 0.2, 0.18, 1.0))
	amount_label.add_theme_font_size_override("font_size", int(16.0 * scale))
	amount_label.add_theme_color_override("font_color", Color(0.18, 0.23, 0.21, 1.0))
	amount_input.custom_minimum_size = Vector2(0.0, 44.0 * scale)
	amount_input.add_theme_font_size_override("font_size", int(16.0 * scale))
	amount_input.get_line_edit().add_theme_font_size_override("font_size", int(16.0 * scale))
	add_button.custom_minimum_size = Vector2(0.0, 44.0 * scale)
	add_button.add_theme_font_size_override("font_size", int(16.0 * scale))
	reset_button.custom_minimum_size = Vector2(0.0, 44.0 * scale)
	reset_button.add_theme_font_size_override("font_size", int(16.0 * scale))
	reset_button.add_theme_color_override("font_color", Color(0.55, 0.08, 0.08, 1.0))
	reset_button.add_theme_color_override("font_hover_color", Color(0.72, 0.05, 0.05, 1.0))
	status_label.add_theme_font_size_override("font_size", int(14.0 * scale))
	status_label.add_theme_color_override("font_color", Color(0.28, 0.32, 0.3, 1.0))
	reset_confirmation.add_theme_font_size_override("font_size", int(16.0 * scale))
	for btn in preset_buttons:
		btn.custom_minimum_size = Vector2(0.0, 40.0 * scale)
		btn.add_theme_font_size_override("font_size", int(14.0 * scale))


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
