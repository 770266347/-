class_name TalentTree
extends Control
## Pannable four-direction talent network for the bottom tool panel.

const BASE_LOGICAL_WIDTH: float = 393.0
const HEADER_HEIGHT_PT: float = 36.0
const CANVAS_SIZE_PT: float = 500.0
const GRID_SPACING_PT: float = 60.0
const NODE_SIZE_PT: float = 46.0
const DRAG_THRESHOLD_PT: float = 8.0

const BRANCH_COLORS: Dictionary = {
	"core": Color(0.94, 0.72, 0.24, 1.0),
	"value": Color(0.92, 0.43, 0.36, 1.0),
	"spawn": Color(0.22, 0.67, 0.77, 1.0),
	"helper": Color(0.30, 0.71, 0.42, 1.0),
	"capacity": Color(0.34, 0.51, 0.84, 1.0),
}


class TalentLinkLayer extends Control:
	const LINK_BRANCH_COLORS: Dictionary = {
		"core": Color(0.94, 0.72, 0.24, 1.0),
		"value": Color(0.92, 0.43, 0.36, 1.0),
		"spawn": Color(0.22, 0.67, 0.77, 1.0),
		"helper": Color(0.30, 0.71, 0.42, 1.0),
		"capacity": Color(0.34, 0.51, 0.84, 1.0),
	}
	var rows: Array = []
	var node_centers: Dictionary = {}
	var node_states: Dictionary = {}

	func configure(new_rows: Array, centers: Dictionary, states: Dictionary) -> void:
		rows = new_rows
		node_centers = centers
		node_states = states
		queue_redraw()

	func _draw() -> void:
		for row in rows:
			var talent_id: String = String(row.get("id", ""))
			var end: Vector2 = node_centers.get(talent_id, Vector2.ZERO)
			var branch: String = String(row.get("branch", "core"))
			var branch_color: Color = LINK_BRANCH_COLORS.get(branch, Color.WHITE)
			var state: String = String(node_states.get(talent_id, "locked"))
			for required_id_variant in row.get("requires", []):
				var required_id: String = String(required_id_variant)
				if not node_centers.has(required_id):
					continue
				var start: Vector2 = node_centers.get(required_id, Vector2.ZERO)
				var color: Color = Color(0.38, 0.40, 0.42, 0.34)
				if state == "available":
					color = Color(branch_color.r, branch_color.g, branch_color.b, 0.72)
				elif state == "unlocked":
					color = branch_color
				draw_line(start, end, color, 5.0, true)
				draw_circle(start.lerp(end, 0.5), 3.0, color)


var header: Control
var title_label: Label
var points_label: Label
var status_label: Label
var reset_button: Button
var canvas_viewport: Control
var canvas_background: ColorRect
var canvas: Control
var links: TalentLinkLayer
var input_layer: Control
var preview_panel: PanelContainer
var preview_label: Label
var node_buttons: Dictionary = {}
var node_centers: Dictionary = {}
var _pan: Vector2 = Vector2.ZERO
var _pointer_active: bool = false
var _dragging: bool = false
var _pointer_start: Vector2 = Vector2.ZERO
var _pointer_last: Vector2 = Vector2.ZERO
var _press_talent_id: String = ""
var _press_elapsed: float = 0.0
var _long_press_triggered: bool = false
var _selected_talent_id: String = ""
var _has_centered: bool = false
var _status_override: String = ""


func _ready() -> void:
	_build()
	EventBus.bottle_changed.connect(func(_amount: int, _delta: int): refresh())
	EventBus.drop_collection_count_changed.connect(func(_id: String, _count: int, _delta: int): refresh())
	EventBus.talent_unlocked.connect(func(_talent_id: String): refresh())
	EventBus.talents_reset.connect(refresh)
	EventBus.save_loaded.connect(refresh)
	refresh()
	call_deferred("apply_layout", get_viewport_rect().size)


func _build() -> void:
	header = Control.new()
	add_child(header)

	title_label = Label.new()
	title_label.text = "天赋网"
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)

	points_label = Label.new()
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	points_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(points_label)

	reset_button = Button.new()
	reset_button.text = "重置"
	reset_button.tooltip_text = "重置已点亮的全部天赋，返还天赋点"
	reset_button.pressed.connect(_on_reset_pressed)
	header.add_child(reset_button)

	status_label = Label.new()
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(status_label)

	canvas_viewport = Control.new()
	canvas_viewport.clip_contents = true
	add_child(canvas_viewport)

	canvas_background = ColorRect.new()
	canvas_background.color = Color(0.12, 0.15, 0.16, 1.0)
	canvas_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_viewport.add_child(canvas_background)

	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_viewport.add_child(canvas)

	links = TalentLinkLayer.new()
	links.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(links)

	for row in ConfigDB.get_talents():
		var talent_id: String = String(row.get("id", ""))
		var button: Button = Button.new()
		button.text = String(row.get("short_name", row.get("name", "天赋")))
		button.tooltip_text = String(row.get("description", ""))
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.set_meta("talent_id", talent_id)
		canvas.add_child(button)
		node_buttons[talent_id] = button

	input_layer = Control.new()
	input_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	input_layer.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	input_layer.gui_input.connect(_on_canvas_input)
	canvas_viewport.add_child(input_layer)

	preview_panel = PanelContainer.new()
	preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_label = Label.new()
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview_panel.add_child(preview_label)
	canvas_viewport.add_child(preview_panel)


func refresh() -> void:
	if points_label == null:
		return
	var available: int = GameState.get_available_talent_points()
	var earned: int = GameState.get_talent_points_earned()
	points_label.text = "可用 %d / %d" % [available, earned]
	reset_button.disabled = GameState.get_talent_points_spent() <= 0
	if _status_override.is_empty():
		var next_milestone: int = GameState.get_next_talent_point_milestone()
		if next_milestone < 0:
			status_label.text = "累计里程碑已完成"
		else:
			status_label.text = "下个点 %s / %s 件" % [
				BigNumber.format(float(GameState.total_bottles)),
				BigNumber.format(float(next_milestone)),
			]
	else:
		status_label.text = _status_override
		_status_override = ""

	var states: Dictionary = {}
	var system: Node = _talent_system()
	for row in ConfigDB.get_talents():
		var talent_id: String = String(row.get("id", ""))
		var state: String = "locked"
		if GameState.is_talent_unlocked(talent_id):
			state = "unlocked"
		elif system != null and system.can_unlock(talent_id):
			state = "available"
		states[talent_id] = state
		_style_node(node_buttons.get(talent_id) as Button, row, state)
	if links != null:
		links.configure(ConfigDB.get_talents(), node_centers, states)
	_refresh_preview()


func _process(delta: float) -> void:
	if not _pointer_active or _dragging or _long_press_triggered or _press_talent_id.is_empty():
		return
	_press_elapsed += delta
	if _press_elapsed >= 1.0:
		_long_press_triggered = true
		_activate_talent(_press_talent_id)


func focus_center() -> void:
	_has_centered = false
	call_deferred("apply_layout", get_viewport_rect().size)


func apply_layout(viewport_size: Vector2) -> void:
	if header == null:
		return
	var scale: float = _ui_scale(viewport_size)
	var header_height: float = HEADER_HEIGHT_PT * scale
	header.position = Vector2.ZERO
	header.size = Vector2(size.x, header_height)
	title_label.position = Vector2(7.0 * scale, 0.0)
	title_label.size = Vector2(72.0 * scale, 19.0 * scale)
	title_label.add_theme_font_size_override("font_size", int(13.0 * scale))
	title_label.add_theme_color_override("font_color", Color(0.22, 0.17, 0.28, 1.0))
	points_label.position = Vector2(size.x - 158.0 * scale, 0.0)
	points_label.size = Vector2(105.0 * scale, 19.0 * scale)
	points_label.add_theme_font_size_override("font_size", int(12.0 * scale))
	points_label.add_theme_color_override("font_color", Color(0.16, 0.42, 0.28, 1.0))
	reset_button.position = Vector2(size.x - 50.0 * scale, 1.0 * scale)
	reset_button.size = Vector2(44.0 * scale, 18.0 * scale)
	reset_button.add_theme_font_size_override("font_size", int(10.0 * scale))
	reset_button.add_theme_color_override("font_color", Color(0.40, 0.22, 0.20, 1.0))
	reset_button.add_theme_stylebox_override("normal", _reset_style(Color(0.96, 0.84, 0.80, 1.0), scale))
	reset_button.add_theme_stylebox_override("disabled", _reset_style(Color(0.83, 0.82, 0.82, 1.0), scale))
	status_label.position = Vector2(7.0 * scale, 17.0 * scale)
	status_label.size = Vector2(maxf(0.0, size.x - 14.0 * scale), 18.0 * scale)
	status_label.add_theme_font_size_override("font_size", int(10.0 * scale))
	status_label.add_theme_color_override("font_color", Color(0.36, 0.32, 0.4, 1.0))

	canvas_viewport.position = Vector2(0.0, header_height)
	canvas_viewport.size = Vector2(size.x, maxf(0.0, size.y - header_height))
	canvas_background.position = Vector2.ZERO
	canvas_background.size = canvas_viewport.size
	input_layer.position = Vector2.ZERO
	input_layer.size = canvas_viewport.size
	preview_panel.position = Vector2(5.0 * scale, 4.0 * scale)
	preview_panel.size = Vector2(maxf(0.0, canvas_viewport.size.x - 10.0 * scale), 44.0 * scale)
	preview_label.add_theme_font_size_override("font_size", int(9.0 * scale))
	preview_label.custom_minimum_size = Vector2(0.0, 36.0 * scale)
	preview_label.add_theme_color_override("font_color", Color(0.88, 0.91, 0.9, 1.0))
	preview_panel.add_theme_stylebox_override("panel", _preview_style(scale))

	canvas.size = Vector2.ONE * CANVAS_SIZE_PT * scale
	links.position = Vector2.ZERO
	links.size = canvas.size
	var center: Vector2 = canvas.size * 0.5
	var node_size: Vector2 = Vector2.ONE * NODE_SIZE_PT * scale
	node_centers.clear()
	for row in ConfigDB.get_talents():
		var talent_id: String = String(row.get("id", ""))
		var button: Button = node_buttons.get(talent_id) as Button
		if button == null:
			continue
		var node_center: Vector2 = center + Vector2(
			float(row.get("grid_x", 0)),
			float(row.get("grid_y", 0))
		) * GRID_SPACING_PT * scale
		node_centers[talent_id] = node_center
		button.position = node_center - node_size * 0.5
		button.size = node_size
		button.add_theme_font_size_override("font_size", int(11.0 * scale))
	if not _has_centered and canvas_viewport.size.x > 0.0 and canvas_viewport.size.y > 0.0:
		_pan = canvas_viewport.size * 0.5 - center
		_has_centered = true
	_set_pan(_pan)
	refresh()


func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_set_pan(_pan + Vector2(0.0, 48.0 * _ui_scale(get_viewport_rect().size)))
			input_layer.accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_set_pan(_pan - Vector2(0.0, 48.0 * _ui_scale(get_viewport_rect().size)))
			input_layer.accept_event()
			return
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_begin_pointer(mouse_button.position)
		else:
			_finish_pointer(mouse_button.position)
		input_layer.accept_event()
	elif event is InputEventMouseMotion and _pointer_active:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_pointer(motion.position)
			input_layer.accept_event()
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_begin_pointer(touch.position)
		else:
			_finish_pointer(touch.position)
		input_layer.accept_event()
	elif event is InputEventScreenDrag and _pointer_active:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_move_pointer(drag.position)
		input_layer.accept_event()


func _begin_pointer(position: Vector2) -> void:
	_pointer_active = true
	_dragging = false
	_pointer_start = position
	_pointer_last = position
	_press_elapsed = 0.0
	_long_press_triggered = false
	_press_talent_id = _talent_at_position(position)
	if not _press_talent_id.is_empty():
		_selected_talent_id = _press_talent_id
		refresh()


func _move_pointer(position: Vector2) -> void:
	if not _dragging:
		var threshold: float = DRAG_THRESHOLD_PT * _ui_scale(get_viewport_rect().size)
		if position.distance_to(_pointer_start) < threshold:
			return
		_dragging = true
		_press_talent_id = ""
	var delta: Vector2 = position - _pointer_last
	_pointer_last = position
	_set_pan(_pan + delta)


func _finish_pointer(position: Vector2) -> void:
	if not _pointer_active:
		return
	var should_click: bool = not _dragging
	_pointer_active = false
	_dragging = false
	_press_talent_id = ""
	_press_elapsed = 0.0
	_long_press_triggered = false
	if not should_click:
		return


func _talent_at_position(viewport_position: Vector2) -> String:
	var canvas_position: Vector2 = viewport_position - _pan
	var rows: Array = ConfigDB.get_talents()
	for index in range(rows.size() - 1, -1, -1):
		var row: Dictionary = rows[index]
		var talent_id: String = String(row.get("id", ""))
		var button: Button = node_buttons.get(talent_id) as Button
		if button != null and Rect2(button.position, button.size).has_point(canvas_position):
			return talent_id
	return ""


func _activate_talent(talent_id: String) -> void:
	var row: Dictionary = ConfigDB.get_talent(talent_id)
	var system: Node = _talent_system()
	if GameState.is_talent_unlocked(talent_id):
		_status_override = "%s：%s" % [row.get("name", "天赋"), row.get("description", "")]
	elif system != null and bool(system.call("unlock", talent_id)):
		_status_override = "已点亮%s：%s" % [row.get("name", "天赋"), row.get("description", "")]
	elif system != null:
		_status_override = String(system.call("get_lock_reason", talent_id))
	refresh()


func _on_reset_pressed() -> void:
	var system: Node = _talent_system()
	if system == null or not bool(system.call("reset")):
		return
	_selected_talent_id = ""
	_status_override = "天赋网已重置，天赋点已返还"
	refresh()


func _refresh_preview() -> void:
	if preview_panel == null:
		return
	if _selected_talent_id.is_empty():
		preview_panel.visible = false
		return
	var row: Dictionary = ConfigDB.get_talent(_selected_talent_id)
	if row.is_empty():
		preview_panel.visible = false
		return
	var system: Node = _talent_system()
	var state: String = "未点亮"
	var action_hint: String = "条件未满足"
	if GameState.is_talent_unlocked(_selected_talent_id):
		state = "已点亮"
		action_hint = "已点亮"
	elif system != null:
		state = String(system.call("get_lock_reason", _selected_talent_id))
		if bool(system.call("can_unlock", _selected_talent_id)):
			action_hint = "长按 1 秒点亮"
	var requirement: Dictionary = row.get("requires_collection", {})
	var condition: String = ""
	if not requirement.is_empty():
		var drop_id: String = String(requirement.get("drop_id", ""))
		condition = "｜%s %d/%d" % [
			ConfigDB.get_drop_name(drop_id),
			GameState.get_drop_collection_count(drop_id),
			int(requirement.get("amount", 0)),
		]
	preview_label.text = "%s｜%s\n%s%s｜%s" % [
			String(row.get("name", "天赋")),
			state,
			String(row.get("description", "")),
			condition,
			action_hint,
		]
	preview_panel.visible = true


func _set_pan(value: Vector2) -> void:
	var minimum: Vector2 = Vector2(
		minf(0.0, canvas_viewport.size.x - canvas.size.x),
		minf(0.0, canvas_viewport.size.y - canvas.size.y)
	)
	_pan = Vector2(
		clampf(value.x, minimum.x, 0.0),
		clampf(value.y, minimum.y, 0.0)
	)
	canvas.position = _pan


func _style_node(button: Button, row: Dictionary, state: String) -> void:
	if button == null:
		return
	var branch: String = String(row.get("branch", "core"))
	var branch_color: Color = BRANCH_COLORS.get(branch, Color.WHITE)
	var fill: Color = Color(0.25, 0.28, 0.29, 1.0)
	var border: Color = Color(0.43, 0.46, 0.47, 1.0)
	var font: Color = Color(0.68, 0.7, 0.7, 1.0)
	if state == "available":
		fill = branch_color.darkened(0.3)
		border = branch_color.lightened(0.18)
		font = Color.WHITE
	elif state == "unlocked":
		fill = branch_color
		border = branch_color.lightened(0.34)
		font = Color(0.08, 0.1, 0.1, 1.0)
	button.add_theme_color_override("font_color", font)
	button.add_theme_color_override("font_disabled_color", font)
	button.add_theme_stylebox_override("normal", _node_style(fill, border))
	button.add_theme_stylebox_override("hover", _node_style(fill.lightened(0.08), border.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", _node_style(fill.darkened(0.08), border))


func _node_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _preview_style(scale: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.20, 0.21, 0.96)
	style.border_color = Color(0.57, 0.72, 0.69, 0.9)
	style.set_border_width_all(maxi(1, int(scale)))
	style.set_corner_radius_all(int(5.0 * scale))
	style.content_margin_left = 7.0 * scale
	style.content_margin_right = 7.0 * scale
	style.content_margin_top = 3.0 * scale
	style.content_margin_bottom = 3.0 * scale
	return style


func _reset_style(fill: Color, scale: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(0.55, 0.42, 0.42, 1.0)
	style.set_border_width_all(maxi(1, int(scale)))
	style.set_corner_radius_all(int(4.0 * scale))
	return style


func _talent_system() -> Node:
	return get_tree().root.get_node_or_null("Main/Systems/TalentSystem")


func _ui_scale(viewport_size: Vector2) -> float:
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)
