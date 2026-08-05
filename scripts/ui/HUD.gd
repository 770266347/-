extends Control
## 顶部 HUD。
##
## 显示现金、累计回收物、当前场景、场景切换和街区防守入口；
## 回收统计弹窗也由此管理，因为它与顶部回收物数字共享同一份分类数据。

const BASE_LOGICAL_WIDTH: float = 393.0

var cash_label: Label
var bottle_button: Button
var top_panel: PanelContainer
var top_row: HBoxContainer
var challenge_panel: PanelContainer
var challenge_title_label: Label
var challenge_subtitle_label: Label
var left_scene_button: Button
var right_scene_button: Button
var defense_mode_button: Button
var stats_layer: Control
var stats_overlay: ColorRect
var stats_panel: PanelContainer
var stats_summary_label: Label
var stats_list: VBoxContainer
var stats_close_button: Button
var stats_count_labels: Dictionary = {}
var _scene_transitioning: bool = false


func _ready() -> void:
    ## 先建 UI 再订阅事件，避免初始化阶段收到事件时控件尚未存在。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.currency_changed.connect(_on_currency_changed)
	EventBus.bottle_changed.connect(_on_bottle_changed)
	EventBus.drop_collection_count_changed.connect(_on_drop_collection_count_changed)
	EventBus.scene_changed.connect(_on_scene_changed)
	EventBus.scene_unlocked.connect(func(_id: String): _refresh_scene())
	EventBus.upgrade_purchased.connect(func(_id, _level: int): _refresh_scene())
	EventBus.scene_transition_started.connect(_on_scene_transition_started)
	EventBus.scene_transition_finished.connect(_on_scene_transition_finished)
	_refresh()
	_refresh_scene()
	call_deferred("apply_layout", get_viewport_rect().size)


func _build() -> void:
    ## 创建资源栏、场景标题、左右切换按钮和防守入口。
	top_panel = PanelContainer.new()
	top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top_panel)

	top_row = HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_panel.add_child(top_row)

	cash_label = Label.new()
	cash_label.text = "现金 0"
	cash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cash_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_row.add_child(cash_label)

	bottle_button = Button.new()
	bottle_button.text = "回收物 0"
	bottle_button.tooltip_text = "查看回收统计"
	bottle_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottle_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottle_button.focus_mode = Control.FOCUS_NONE
	bottle_button.pressed.connect(_open_collection_stats)
	top_row.add_child(bottle_button)

	challenge_panel = PanelContainer.new()
	challenge_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(challenge_panel)

	var challenge_box: VBoxContainer = VBoxContainer.new()
	challenge_panel.add_child(challenge_box)

	challenge_title_label = Label.new()
	challenge_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenge_box.add_child(challenge_title_label)

	challenge_subtitle_label = Label.new()
	challenge_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenge_box.add_child(challenge_subtitle_label)

	left_scene_button = Button.new()
	left_scene_button.text = "<"
	left_scene_button.mouse_filter = Control.MOUSE_FILTER_STOP
	left_scene_button.pressed.connect(_on_left_scene_pressed)
	add_child(left_scene_button)

	right_scene_button = Button.new()
	right_scene_button.text = ">"
	right_scene_button.mouse_filter = Control.MOUSE_FILTER_STOP
	right_scene_button.pressed.connect(_on_right_scene_pressed)
	add_child(right_scene_button)

	defense_mode_button = Button.new()
	defense_mode_button.text = "街区防守"
	defense_mode_button.tooltip_text = "进入街区防守"
	defense_mode_button.mouse_filter = Control.MOUSE_FILTER_STOP
	defense_mode_button.pressed.connect(func(): EventBus.defense_mode_requested.emit())
	add_child(defense_mode_button)

	_build_collection_stats()


func _build_collection_stats() -> void:
    ## 构建隐藏的统计层；具体产物行在打开弹窗时按配置动态生成。
	stats_layer = Control.new()
	stats_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_layer.z_index = 4000
	stats_layer.visible = false
	add_child(stats_layer)

	stats_overlay = ColorRect.new()
	stats_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats_overlay.color = Color(0.03, 0.04, 0.05, 0.68)
	stats_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	stats_overlay.gui_input.connect(_on_stats_overlay_input)
	stats_layer.add_child(stats_overlay)

	stats_panel = PanelContainer.new()
	stats_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	stats_layer.add_child(stats_panel)

	var box: VBoxContainer = VBoxContainer.new()
	stats_panel.add_child(box)

	var title_row: HBoxContainer = HBoxContainer.new()
	box.add_child(title_row)

	var title_label: Label = Label.new()
	title_label.text = "回收统计"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.set_meta("stats_title", true)
	title_row.add_child(title_label)

	stats_close_button = Button.new()
	stats_close_button.text = "X"
	stats_close_button.tooltip_text = "关闭"
	stats_close_button.pressed.connect(_close_collection_stats)
	title_row.add_child(stats_close_button)

	stats_summary_label = Label.new()
	stats_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_summary_label.set_meta("stats_summary", true)
	box.add_child(stats_summary_label)

	var separator: HSeparator = HSeparator.new()
	box.add_child(separator)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)

	stats_list = VBoxContainer.new()
	stats_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stats_list)


func _refresh() -> void:
    ## 只更新顶部两个高频资源文本，不重建场景按钮。
	cash_label.text = "现金 %s" % BigNumber.format(GameState.currency)
	bottle_button.text = "回收物 %s" % BigNumber.format(float(GameState.bottles), 0)


func _refresh_scene() -> void:
    ## 根据当前场景、解锁状态和过场状态更新标题及按钮可用性。
	challenge_title_label.text = ConfigDB.get_scene_name(GameState.current_scene_id)
	challenge_subtitle_label.text = _scene_subtitle()
	if left_scene_button != null:
		left_scene_button.disabled = _scene_transitioning or not GameState.can_switch_scene_by_offset(-1)
	if right_scene_button != null:
		right_scene_button.disabled = _scene_transitioning or not GameState.can_switch_scene_by_offset(1)
	if defense_mode_button != null:
		defense_mode_button.visible = _defense_mode_unlocked()
		defense_mode_button.disabled = _scene_transitioning


func _scene_subtitle() -> String:
    ## 将过场、下一场景未解锁和普通状态转换为短副标题。
	if _scene_transitioning:
		return "帮手正在通过传送门"
	var next_scene_id: String = ConfigDB.get_scene_id_at_offset(GameState.current_scene_id, 1)
	if not next_scene_id.is_empty() and not GameState.is_scene_unlocked(next_scene_id):
		return "%s未解锁" % ConfigDB.get_scene_name(next_scene_id)
	return "当前场景"


func _on_currency_changed(_new_amount: float, _delta: float) -> void:
    ## 现金变化只需刷新资源栏。
	_refresh()


func _on_bottle_changed(_new_amount: int, _delta: int) -> void:
    ## 总回收量变化只需刷新资源栏，分类弹窗另有独立信号。
	_refresh()


func _on_drop_collection_count_changed(drop_id: String, new_amount: int, _delta: int) -> void:
    ## 弹窗打开时只更新受影响的那一行，避免重建整个统计列表。
	if stats_layer == null or not stats_layer.visible:
		return
	var count_label: Label = stats_count_labels.get(drop_id) as Label
	if count_label != null:
		count_label.text = "%d 个" % new_amount
	_refresh_stats_summary()


func _on_scene_changed(_scene_id: String) -> void:
    ## GameState 切场景后刷新标题和左右按钮状态。
	_refresh_scene()


func _on_scene_transition_started() -> void:
    ## 过场期间锁定重复切换。
	_scene_transitioning = true
	_refresh_scene()


func _on_scene_transition_finished(_scene_id: String) -> void:
    ## 传送门过场结束后恢复切换入口。
	_scene_transitioning = false
	_refresh_scene()


func _on_left_scene_pressed() -> void:
    ## 通过 EventBus 请求向左切换，动画由 BottleSpawnArea 执行。
	EventBus.scene_switch_requested.emit(-1)


func _on_right_scene_pressed() -> void:
    ## 通过 EventBus 请求向右切换，动画由 BottleSpawnArea 执行。
	EventBus.scene_switch_requested.emit(1)


func _defense_mode_unlocked() -> bool:
    ## 防守入口只有在配置中的全部场景解锁后才显示。
	var scenes: Array = ConfigDB.get_scenes()
	if scenes.size() < 5:
		return false
	for scene in scenes:
		if not GameState.is_scene_unlocked(String(scene.get("id", ""))):
			return false
	return true


func _open_collection_stats() -> void:
    ## 打开前重建分类列表，确保新增产物或最新数量立即可见。
	_refresh_collection_stats()
	stats_layer.visible = true
	apply_layout(get_viewport_rect().size)


func _close_collection_stats() -> void:
    ## 只隐藏弹窗，不清除分类标签缓存，下一次打开会重新构建。
	stats_layer.visible = false


func _on_stats_overlay_input(event: InputEvent) -> void:
    ## 点击或触摸遮罩区域关闭统计弹窗，弹窗本体不受影响。
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
		_close_collection_stats()
		stats_overlay.accept_event()
		return
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.pressed:
		_close_collection_stats()
		stats_overlay.accept_event()


func _refresh_collection_stats() -> void:
    ## 按场景和产物配置重建统计列表，顺序与场景页签保持一致。
	for child in stats_list.get_children():
		child.queue_free()
	stats_count_labels.clear()
	var scale: float = _ui_scale(get_viewport_rect().size)
	for scene in ConfigDB.get_scenes():
		var scene_id: String = String(scene.get("id", ""))
		var heading: Label = Label.new()
		heading.text = String(scene.get("name", scene_id))
		heading.custom_minimum_size = Vector2(0.0, 28.0 * scale)
		heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		heading.add_theme_font_size_override("font_size", int(14.0 * scale))
		heading.add_theme_color_override("font_color", Color(1.0, 0.83, 0.38, 1.0))
		stats_list.add_child(heading)
		for drop in scene.get("drops", []):
			_add_stats_drop_row(drop, scale)
	_refresh_stats_summary()


func _add_stats_drop_row(drop: Dictionary, scale: float) -> void:
    ## 创建一行产物图标、名称和终身收集数量，并登记数量 Label 以便增量更新。
	var drop_id: String = String(drop.get("id", ""))
	var row_panel: PanelContainer = PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0.0, 52.0 * scale)
	row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.19, 0.21, 0.22, 0.96), Color(0.38, 0.41, 0.42, 1.0), 1.0, 5.0, scale))
	stats_list.add_child(row_panel)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_panel.add_child(row)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(38.0, 44.0) * scale
	icon.texture = load(String(drop.get("sprite", ""))) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var name_label: Label = Label.new()
	name_label.text = String(drop.get("name", drop_id))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", int(13.0 * scale))
	name_label.add_theme_color_override("font_color", Color(0.94, 0.94, 0.9, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)

	var count_label: Label = Label.new()
	count_label.text = "%d 个" % GameState.get_drop_collection_count(drop_id)
	count_label.custom_minimum_size = Vector2(90.0, 0.0) * scale
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", int(14.0 * scale))
	count_label.add_theme_color_override("font_color", Color(0.62, 0.94, 0.72, 1.0))
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count_label)
	stats_count_labels[drop_id] = count_label


func _refresh_stats_summary() -> void:
    ## 汇总全部产物的终身数量和已收集种类数。
	var total: int = 0
	var collected_types: int = 0
	var type_count: int = 0
	for scene in ConfigDB.get_scenes():
		for drop in scene.get("drops", []):
			type_count += 1
			var amount: int = GameState.get_drop_collection_count(String(drop.get("id", "")))
			total += amount
			if amount > 0:
				collected_types += 1
	stats_summary_label.text = "累计 %d 件｜已收集 %d/%d 种" % [total, collected_types, type_count]


func apply_layout(viewport_size: Vector2) -> void:
    ## 同时布局顶部 HUD、场景切换条、防守入口和统计弹窗。
	var scale: float = _ui_scale(viewport_size)
	var margin: float = 10.0 * scale

	top_panel.position = Vector2(margin, 10.0 * scale)
	top_panel.size = Vector2(viewport_size.x - margin * 2.0, 42.0 * scale)
	top_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.13, 0.15, 0.18, 0.78), Color(0.95, 0.78, 0.36, 0.9), 2.0, 15.0, scale))

	if top_row != null:
		top_row.add_theme_constant_override("separation", 0)
	cash_label.custom_minimum_size = Vector2(0.0, 30.0 * scale)
	bottle_button.custom_minimum_size = Vector2(0.0, 30.0 * scale)
	cash_label.add_theme_font_size_override("font_size", int(14.0 * scale))
	bottle_button.add_theme_font_size_override("font_size", int(14.0 * scale))
	_set_control_font_color(cash_label, Color(0.98, 1.0, 0.9, 1.0))
	_set_control_font_color(bottle_button, Color(0.85, 0.96, 1.0, 1.0))
	bottle_button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.54, 1.0))
	bottle_button.add_theme_stylebox_override("normal", _rounded_style(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0.0, 8.0, scale))
	bottle_button.add_theme_stylebox_override("hover", _rounded_style(Color(1.0, 1.0, 1.0, 0.08), Color(1.0, 0.82, 0.36, 0.45), 1.0, 8.0, scale))
	bottle_button.add_theme_stylebox_override("pressed", _rounded_style(Color(0.0, 0.0, 0.0, 0.18), Color(1.0, 0.82, 0.36, 0.7), 1.0, 8.0, scale))

	var scene_panel_width: float = minf(222.0 * scale, viewport_size.x - 112.0 * scale)
	var scene_button_size: Vector2 = Vector2(34.0 * scale, 50.0 * scale)
	var scene_group_width: float = scene_button_size.x * 2.0 + scene_panel_width + 14.0 * scale
	var scene_group_left: float = maxf(margin, (viewport_size.x - scene_group_width) * 0.5)
	var scene_top: float = 62.0 * scale

	left_scene_button.position = Vector2(scene_group_left, scene_top + 4.0 * scale)
	left_scene_button.size = scene_button_size
	left_scene_button.add_theme_font_size_override("font_size", int(18.0 * scale))
	left_scene_button.add_theme_stylebox_override("normal", _rounded_style(Color(0.2, 0.19, 0.28, 0.9), Color(1.0, 0.8, 0.28, 0.85), 2.0, 10.0, scale))
	left_scene_button.add_theme_stylebox_override("disabled", _rounded_style(Color(0.18, 0.18, 0.2, 0.38), Color(0.6, 0.6, 0.6, 0.4), 1.0, 10.0, scale))

	challenge_panel.position = Vector2(scene_group_left + scene_button_size.x + 7.0 * scale, scene_top)
	challenge_panel.size = Vector2(scene_panel_width, 58.0 * scale)
	challenge_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.2, 0.19, 0.28, 0.92), Color(1.0, 0.8, 0.28, 1.0), 3.0, 13.0, scale))
	challenge_title_label.add_theme_font_size_override("font_size", int(19.0 * scale))
	challenge_subtitle_label.add_theme_font_size_override("font_size", int(11.0 * scale))
	_set_control_font_color(challenge_title_label, Color(1.0, 0.97, 0.75, 1.0))
	_set_control_font_color(challenge_subtitle_label, Color(0.82, 0.95, 1.0, 1.0))

	right_scene_button.position = Vector2(challenge_panel.position.x + scene_panel_width + 7.0 * scale, scene_top + 4.0 * scale)
	right_scene_button.size = scene_button_size
	right_scene_button.add_theme_font_size_override("font_size", int(18.0 * scale))
	right_scene_button.add_theme_stylebox_override("normal", _rounded_style(Color(0.2, 0.19, 0.28, 0.9), Color(1.0, 0.8, 0.28, 0.85), 2.0, 10.0, scale))
	right_scene_button.add_theme_stylebox_override("disabled", _rounded_style(Color(0.18, 0.18, 0.2, 0.38), Color(0.6, 0.6, 0.6, 0.4), 1.0, 10.0, scale))

	defense_mode_button.position = Vector2(viewport_size.x - 144.0 * scale, 168.0 * scale)
	defense_mode_button.size = Vector2(132.0, 38.0) * scale
	defense_mode_button.add_theme_font_size_override("font_size", int(13.0 * scale))
	defense_mode_button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.76, 1.0))
	defense_mode_button.add_theme_stylebox_override("normal", _rounded_style(Color(0.22, 0.2, 0.27, 0.94), Color(0.96, 0.72, 0.2, 1.0), 2.0, 7.0, scale))
	defense_mode_button.add_theme_stylebox_override("hover", _rounded_style(Color(0.31, 0.27, 0.36, 0.98), Color(1.0, 0.83, 0.34, 1.0), 2.0, 7.0, scale))

	stats_layer.position = Vector2.ZERO
	stats_layer.size = viewport_size
	stats_overlay.position = Vector2.ZERO
	stats_overlay.size = viewport_size
	var stats_height: float = minf(650.0 * scale, viewport_size.y - 80.0 * scale)
	stats_panel.size = Vector2(minf(350.0 * scale, viewport_size.x - 32.0 * scale), stats_height)
	stats_panel.position = (viewport_size - stats_panel.size) * 0.5
	stats_panel.add_theme_stylebox_override("panel", _rounded_style(Color(0.12, 0.14, 0.15, 0.99), Color(0.96, 0.73, 0.25, 1.0), 3.0, 7.0, scale))
	stats_close_button.custom_minimum_size = Vector2(38.0, 36.0) * scale
	stats_close_button.add_theme_font_size_override("font_size", int(15.0 * scale))
	stats_summary_label.add_theme_font_size_override("font_size", int(13.0 * scale))
	stats_summary_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.78, 1.0))
	stats_list.add_theme_constant_override("separation", int(5.0 * scale))
	for child in stats_panel.find_children("*", "Label", true, false):
		var label: Label = child as Label
		if label != null and bool(label.get_meta("stats_title", false)):
			label.add_theme_font_size_override("font_size", int(20.0 * scale))
			label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.66, 1.0))


func _ui_scale(viewport_size: Vector2) -> float:
    ## 以 iPhone 16 的 393pt 逻辑宽度作为 UI 缩放基准。
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)


func _rounded_style(bg: Color, border: Color, border_width: float, radius: float, scale: float) -> StyleBoxFlat:
    ## 生成 HUD 和统计弹窗共用的圆角样式。
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


func _set_control_font_color(control: Control, color: Color) -> void:
    ## 统一设置 Label/Button 的主题颜色，避免重复写主题覆盖调用。
	control.add_theme_color_override("font_color", color)
