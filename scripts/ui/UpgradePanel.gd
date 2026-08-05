extends Control
## Bottom panel: compact upgrade, scene, helper, and talent tabs.

const BASE_LOGICAL_WIDTH: float = 393.0
const TAB_PRICE: String = "price"
const TAB_SCENE: String = "scene"
const TAB_HELPER: String = "helper"
const TAB_TALENT: String = "talent"
const UPGRADE_SCOPE_GLOBAL: String = "global"
const SUBTAB_DRAG_THRESHOLD_PT: float = 8.0
const LIST_DRAG_THRESHOLD_PT: float = 8.0
const LIST_CLICK_DEDUP_MS: int = 90
const TALENT_TREE_SCRIPT: Script = preload("res://scripts/ui/TalentTree.gd")

var panel_container: PanelContainer
var tab_bar: HBoxContainer
var price_tab_button: Button
var scene_tab_button: Button
var helper_tab_button: Button
var talent_tab_button: Button
var upgrade_subtab_viewport: Control
var upgrade_subtab_scroll: ScrollContainer
var upgrade_subtab_bar: HBoxContainer
var upgrade_subtab_input_layer: Control
var upgrade_subtab_buttons: Dictionary = {}
var list_viewport: Control
var list_scroll: ScrollContainer
var list_input_layer: Control
var list: VBoxContainer
var talent_tree: Control
var _selected_tab: String = TAB_PRICE
var _selected_upgrade_scope: String = UPGRADE_SCOPE_GLOBAL
var _subtab_pointer_active: bool = false
var _subtab_dragging: bool = false
var _subtab_pointer_start_x: float = 0.0
var _subtab_pointer_last_x: float = 0.0
var _list_pointer_active: bool = false
var _list_dragging: bool = false
var _list_pointer_start: Vector2 = Vector2.ZERO
var _list_pointer_last_y: float = 0.0
var _last_list_click_msec: int = -LIST_CLICK_DEDUP_MS
var _scene_transitioning: bool = false


func _ready() -> void:
	_build()
	EventBus.currency_changed.connect(func(_a: float, _d: float): _refresh())
	EventBus.upgrade_purchased.connect(func(_id, _lv: int): _refresh())
	EventBus.unlocked_drops_changed.connect(func(): _refresh())
	EventBus.scene_unlocked.connect(func(_id: String): _refresh())
	EventBus.helper_purchased.connect(func(_id: String): _refresh())
	EventBus.helper_active_changed.connect(func(_id: String, _active: bool): _refresh())
	EventBus.scene_changed.connect(func(_id: String): _refresh())
	EventBus.scene_transition_started.connect(_on_scene_transition_started)
	EventBus.scene_transition_finished.connect(_on_scene_transition_finished)
	_refresh()


func _build() -> void:
	panel_container = PanelContainer.new()
	panel_container.anchor_right = 1.0
	panel_container.anchor_bottom = 1.0
	add_child(panel_container)

	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_container.add_child(box)

	tab_bar = HBoxContainer.new()
	box.add_child(tab_bar)

	price_tab_button = Button.new()
	price_tab_button.text = "升级"
	price_tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_tab_button.pressed.connect(func(): _select_tab(TAB_PRICE))
	tab_bar.add_child(price_tab_button)

	scene_tab_button = Button.new()
	scene_tab_button.text = "场景"
	scene_tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_tab_button.pressed.connect(func(): _select_tab(TAB_SCENE))
	tab_bar.add_child(scene_tab_button)

	helper_tab_button = Button.new()
	helper_tab_button.text = "帮手"
	helper_tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	helper_tab_button.pressed.connect(func(): _select_tab(TAB_HELPER))
	tab_bar.add_child(helper_tab_button)

	talent_tab_button = Button.new()
	talent_tab_button.text = "天赋"
	talent_tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talent_tab_button.pressed.connect(func(): _select_tab(TAB_TALENT))
	tab_bar.add_child(talent_tab_button)

	upgrade_subtab_viewport = Control.new()
	upgrade_subtab_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(upgrade_subtab_viewport)

	upgrade_subtab_scroll = ScrollContainer.new()
	upgrade_subtab_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	upgrade_subtab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	upgrade_subtab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	upgrade_subtab_viewport.add_child(upgrade_subtab_scroll)

	upgrade_subtab_bar = HBoxContainer.new()
	upgrade_subtab_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	upgrade_subtab_scroll.add_child(upgrade_subtab_bar)
	_build_upgrade_subtabs()

	upgrade_subtab_input_layer = Control.new()
	upgrade_subtab_input_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	upgrade_subtab_input_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	upgrade_subtab_input_layer.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	upgrade_subtab_input_layer.gui_input.connect(_on_upgrade_subtab_overlay_input)
	upgrade_subtab_viewport.add_child(upgrade_subtab_input_layer)

	list_viewport = Control.new()
	list_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list_viewport)

	list_scroll = ScrollContainer.new()
	list_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_viewport.add_child(list_scroll)

	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list)

	list_input_layer = Control.new()
	list_input_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	list_input_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	list_input_layer.gui_input.connect(_on_list_overlay_input)
	list_viewport.add_child(list_input_layer)

	talent_tree = TALENT_TREE_SCRIPT.new()
	talent_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	talent_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	talent_tree.visible = false
	box.add_child(talent_tree)


func _build_upgrade_subtabs() -> void:
	upgrade_subtab_buttons.clear()
	_add_upgrade_subtab(UPGRADE_SCOPE_GLOBAL, "通用")
	for scene in ConfigDB.get_scenes():
		var scene_id: String = String(scene.get("id", ""))
		if not scene_id.is_empty():
			_add_upgrade_subtab(scene_id, String(scene.get("name", scene_id)))


func _add_upgrade_subtab(scope_id: String, label: String) -> void:
	var btn: Button = Button.new()
	btn.text = label
	btn.tooltip_text = "轻点切换，按住可左右拖动"
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_subtab_bar.add_child(btn)
	upgrade_subtab_buttons[scope_id] = btn


func _select_tab(tab_id: String) -> void:
	if _selected_tab == tab_id:
		return
	_selected_tab = tab_id
	_refresh()
	if tab_id == TAB_TALENT and talent_tree != null:
		talent_tree.focus_center()


func _select_upgrade_scope(scope_id: String) -> void:
	if _selected_upgrade_scope == scope_id:
		return
	_selected_upgrade_scope = scope_id
	_refresh()


func _on_upgrade_subtab_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_scroll_upgrade_subtabs_by(-40.0 * _ui_scale(get_viewport_rect().size))
			upgrade_subtab_input_layer.accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_scroll_upgrade_subtabs_by(40.0 * _ui_scale(get_viewport_rect().size))
			upgrade_subtab_input_layer.accept_event()
			return
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		var pointer_position: Vector2 = mouse_button.position
		if mouse_button.pressed:
			_begin_upgrade_subtab_pointer(pointer_position.x)
		else:
			_finish_upgrade_subtab_pointer(pointer_position)
		upgrade_subtab_input_layer.accept_event()
	elif event is InputEventMouseMotion and _subtab_pointer_active:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		if mouse_motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_upgrade_subtab_pointer(mouse_motion.position.x)
			upgrade_subtab_input_layer.accept_event()
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_begin_upgrade_subtab_pointer(touch.position.x)
		else:
			_finish_upgrade_subtab_pointer(touch.position)
		upgrade_subtab_input_layer.accept_event()
	elif event is InputEventScreenDrag and _subtab_pointer_active:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_move_upgrade_subtab_pointer(drag.position.x)
		upgrade_subtab_input_layer.accept_event()


func _begin_upgrade_subtab_pointer(pointer_x: float) -> void:
	_subtab_pointer_active = true
	_subtab_dragging = false
	_subtab_pointer_start_x = pointer_x
	_subtab_pointer_last_x = pointer_x


func _move_upgrade_subtab_pointer(pointer_x: float) -> void:
	if not _subtab_dragging:
		var threshold: float = SUBTAB_DRAG_THRESHOLD_PT * _ui_scale(get_viewport_rect().size)
		if absf(pointer_x - _subtab_pointer_start_x) < threshold:
			return
		_subtab_dragging = true
	var delta_x: float = pointer_x - _subtab_pointer_last_x
	_subtab_pointer_last_x = pointer_x
	_scroll_upgrade_subtabs_by(-delta_x)


func _finish_upgrade_subtab_pointer(pointer_position: Vector2) -> void:
	if not _subtab_pointer_active:
		return
	var should_select: bool = not _subtab_dragging
	_subtab_pointer_active = false
	_subtab_dragging = false
	if should_select:
		var scope_id: String = _upgrade_scope_at_local_position(pointer_position)
		if not scope_id.is_empty():
			_select_upgrade_scope(scope_id)


func _upgrade_scope_at_local_position(pointer_position: Vector2) -> String:
	var content_position: Vector2 = pointer_position + Vector2(float(upgrade_subtab_scroll.scroll_horizontal), 0.0)
	for scope_id in upgrade_subtab_buttons.keys():
		var btn: Button = upgrade_subtab_buttons.get(scope_id) as Button
		if btn != null and btn.visible and Rect2(btn.position, btn.size).has_point(content_position):
			return String(scope_id)
	return ""


func _scroll_upgrade_subtabs_by(delta_x: float) -> void:
	if upgrade_subtab_scroll == null:
		return
	var horizontal_bar: HScrollBar = upgrade_subtab_scroll.get_h_scroll_bar()
	var max_scroll: float = maxf(0.0, horizontal_bar.max_value - horizontal_bar.page)
	var target: float = clampf(float(upgrade_subtab_scroll.scroll_horizontal) + delta_x, 0.0, max_scroll)
	upgrade_subtab_scroll.scroll_horizontal = int(round(target))


func _on_list_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_scroll_list_by(-48.0 * _ui_scale(get_viewport_rect().size))
			list_input_layer.accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_scroll_list_by(48.0 * _ui_scale(get_viewport_rect().size))
			list_input_layer.accept_event()
			return
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_begin_list_pointer(mouse_button.position)
		else:
			_finish_list_pointer(mouse_button.position)
		list_input_layer.accept_event()
	elif event is InputEventMouseMotion and _list_pointer_active:
		var mouse_motion: InputEventMouseMotion = event as InputEventMouseMotion
		if mouse_motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move_list_pointer(mouse_motion.position)
			list_input_layer.accept_event()
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_begin_list_pointer(touch.position)
		else:
			_finish_list_pointer(touch.position)
		list_input_layer.accept_event()
	elif event is InputEventScreenDrag and _list_pointer_active:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		_move_list_pointer(drag.position)
		list_input_layer.accept_event()


func _begin_list_pointer(pointer_position: Vector2) -> void:
	_list_pointer_active = true
	_list_dragging = false
	_list_pointer_start = pointer_position
	_list_pointer_last_y = pointer_position.y


func _move_list_pointer(pointer_position: Vector2) -> void:
	if not _list_dragging:
		var threshold: float = LIST_DRAG_THRESHOLD_PT * _ui_scale(get_viewport_rect().size)
		if pointer_position.distance_to(_list_pointer_start) < threshold:
			return
		_list_dragging = true
	var delta_y: float = pointer_position.y - _list_pointer_last_y
	_list_pointer_last_y = pointer_position.y
	_scroll_list_by(-delta_y)


func _finish_list_pointer(pointer_position: Vector2) -> void:
	if not _list_pointer_active:
		return
	var should_click: bool = not _list_dragging
	_list_pointer_active = false
	_list_dragging = false
	if not should_click:
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_list_click_msec < LIST_CLICK_DEDUP_MS:
		return
	var button: Button = _list_button_at_position(pointer_position)
	if button == null or button.disabled:
		return
	_last_list_click_msec = now_msec
	button.pressed.emit()


func _list_button_at_position(pointer_position: Vector2) -> Button:
	var content_position: Vector2 = pointer_position + Vector2(
		float(list_scroll.scroll_horizontal),
		float(list_scroll.scroll_vertical)
	)
	return _button_at_position_in_control(list, content_position)


func _button_at_position_in_control(parent: Control, position_in_parent: Vector2) -> Button:
	var children: Array[Node] = parent.get_children()
	for index in range(children.size() - 1, -1, -1):
		var control: Control = children[index] as Control
		if control == null or not control.visible or control.is_queued_for_deletion():
			continue
		var local_position: Vector2 = position_in_parent - control.position
		if not Rect2(Vector2.ZERO, control.size).has_point(local_position):
			continue
		var button: Button = control as Button
		if button != null:
			return button
		button = _button_at_position_in_control(control, local_position)
		if button != null:
			return button
	return null


func _scroll_list_by(delta_y: float) -> void:
	if list_scroll == null:
		return
	var vertical_bar: VScrollBar = list_scroll.get_v_scroll_bar()
	var max_scroll: float = maxf(0.0, vertical_bar.max_value - vertical_bar.page)
	var target: float = clampf(float(list_scroll.scroll_vertical) + delta_y, 0.0, max_scroll)
	list_scroll.scroll_vertical = int(round(target))


func _refresh() -> void:
	if list == null:
		return
	_clear_list()
	_refresh_tabs()
	if upgrade_subtab_viewport != null:
		upgrade_subtab_viewport.visible = _selected_tab == TAB_PRICE
	if list_viewport != null:
		list_viewport.visible = _selected_tab != TAB_TALENT
	if talent_tree != null:
		talent_tree.visible = _selected_tab == TAB_TALENT
	_refresh_upgrade_subtabs()
	match _selected_tab:
		TAB_SCENE:
			_build_scene_buttons()
		TAB_HELPER:
			_build_helper_buttons()
		TAB_TALENT:
			talent_tree.refresh()
		_:
			_build_upgrade_buttons()
	apply_layout(get_viewport_rect().size)


func _build_upgrade_buttons() -> void:
	var rows: Array = _upgrades_for_selected_scope()
	for row in rows:
		var id = row.get("id", "")
		var btn: Button = _make_list_button(_upgrade_button_text(row, false))
		btn.disabled = _upgrade_system() == null or not _upgrade_system().can_buy(id)
		btn.pressed.connect(_on_buy_upgrade_pressed.bind(id))
		list.add_child(btn)


func _build_scene_buttons() -> void:
	for row in _scene_unlocks():
		var id = row.get("id", "")
		var btn: Button = _make_list_button(_upgrade_button_text(row))
		btn.disabled = _upgrade_system() == null or not _upgrade_system().can_buy(id)
		btn.pressed.connect(_on_buy_upgrade_pressed.bind(id))
		list.add_child(btn)


func _build_helper_buttons() -> void:
	for row in ConfigDB.get_helpers():
		var id: String = String(row.get("id", ""))
		if GameState.has_helper(id):
			_add_owned_helper_row(row)
			continue
		var btn: Button = _make_list_button(_helper_button_text(row))
		btn.disabled = _upgrade_system() == null or not _upgrade_system().can_buy_helper(id)
		btn.pressed.connect(_on_buy_helper_pressed.bind(id))
		list.add_child(btn)


func _add_owned_helper_row(row: Dictionary) -> void:
	var helper_id: String = String(row.get("id", ""))
	var row_container: HBoxContainer = HBoxContainer.new()
	row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_container.set_meta("helper_list_row", true)
	list.add_child(row_container)

	var info_button: Button = _make_list_button(_helper_button_text(row))
	info_button.disabled = true
	info_button.set_meta("helper_info", true)
	row_container.add_child(info_button)

	var active: bool = GameState.is_helper_active(helper_id)
	var toggle_button: Button = Button.new()
	toggle_button.text = "下阵" if active else "上阵"
	toggle_button.tooltip_text = "让该帮手停止工作" if active else "让该帮手进入当前场景工作"
	toggle_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle_button.disabled = _scene_transitioning
	toggle_button.set_meta("helper_toggle", true)
	toggle_button.set_meta("helper_active", active)
	toggle_button.pressed.connect(_on_helper_active_pressed.bind(helper_id))
	row_container.add_child(toggle_button)


func _make_list_button(text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return btn


func _on_buy_upgrade_pressed(upgrade_id) -> void:
	var system: UpgradeSystem = _upgrade_system()
	if system != null:
		system.buy(upgrade_id)


func _on_buy_helper_pressed(helper_id: String) -> void:
	var system: UpgradeSystem = _upgrade_system()
	if system != null:
		system.buy_helper(helper_id)


func _on_helper_active_pressed(helper_id: String) -> void:
	GameState.set_helper_active(helper_id, not GameState.is_helper_active(helper_id))


func _on_scene_transition_started() -> void:
	_scene_transitioning = true
	_refresh()


func _on_scene_transition_finished(_scene_id: String) -> void:
	_scene_transitioning = false
	_refresh()


func _upgrade_button_text(row: Dictionary, include_scope: bool = true) -> String:
	var id: String = String(row.get("id", ""))
	var display_name: String = _upgrade_display_name(row)
	var level: int = GameState.get_upgrade_level(id)
	var max_level: int = int(row.get("max_level", 1))
	var system: UpgradeSystem = _upgrade_system()
	var cost: float = ConfigDB.get_upgrade_cost(id, level + 1)
	if system != null:
		cost = system.get_next_cost(id)
	var status: String = "%s 元" % BigNumber.format(cost)
	if _is_upgrade_target_unlocked(row):
		status = "已解锁"
	elif level >= max_level:
		status = "Lv.%d 已满级" % level
	elif not _requirements_met(row):
		status = "需 %s" % _requirement_names(row)
	elif not GameState.can_afford(cost):
		status = "Lv.%d｜差钱 %s" % [level, BigNumber.format(cost)] if max_level > 1 else "差钱 %s" % BigNumber.format(cost)
	elif max_level > 1:
		status = "Lv.%d→%d｜%s 元" % [level, level + 1, BigNumber.format(cost)]
	if include_scope:
		return "%s｜%s｜%s" % [_upgrade_scope_name(row), display_name, status]
	return "%s｜%s" % [display_name, status]


func _upgrade_display_name(row: Dictionary) -> String:
	var name: String = String(row.get("name", "升级"))
	var effect: float = float(row.get("effect_per_level", 0.0))
	match String(row.get("type", "")):
		"global_value":
			return "%s +%d%%/级" % [name, roundi(effect * 100.0)]
		"global_spawn":
			return "刷新间隔 -%d%%/级" % roundi(effect * 100.0)
		"global_capacity":
			return "%s +%d/级" % [name, roundi(effect)]
	return name


func _upgrade_scope_name(row: Dictionary) -> String:
	if String(row.get("scope", "")) == UPGRADE_SCOPE_GLOBAL:
		return "通用"
	return ConfigDB.get_scene_name(_upgrade_scene_id(row))


func _helper_button_text(row: Dictionary) -> String:
	var helper_id: String = String(row.get("id", ""))
	var cost: float = float(row.get("cost", 0.0))
	var status: String = "%s 元" % BigNumber.format(cost)
	if GameState.has_helper(helper_id):
		status = _helper_owned_status(row)
	elif not GameState.can_afford(cost):
		status = "差钱 %s" % BigNumber.format(cost)
	return "%s｜%s｜%s" % [
		_scene_names(row.get("scenes", [])),
		String(row.get("name", "帮手")),
		status
	]


func _helper_owned_status(row: Dictionary) -> String:
	var helper_id: String = String(row.get("id", ""))
	if GameState.is_helper_active(helper_id):
		return "工作中"
	return "已下阵"


func _upgrades_for_selected_scope() -> Array:
	var out: Array = []
	for row in ConfigDB.get_upgrades():
		if String(row.get("type", "")) == "unlock_scene":
			continue
		var scope: String = String(row.get("scope", "scene"))
		if _selected_upgrade_scope == UPGRADE_SCOPE_GLOBAL:
			if scope == UPGRADE_SCOPE_GLOBAL:
				out.append(row)
		elif scope != UPGRADE_SCOPE_GLOBAL and _upgrade_scene_id(row) == _selected_upgrade_scope:
			out.append(row)
	return out


func _scene_unlocks() -> Array:
	var out: Array = []
	for row in ConfigDB.get_upgrades():
		if String(row.get("type", "")) == "unlock_scene":
			out.append(row)
	return out


func _upgrade_scene_id(row: Dictionary) -> String:
	var configured_scene_id: String = String(row.get("scene_id", ""))
	if not configured_scene_id.is_empty():
		return configured_scene_id
	if String(row.get("type", "")) == "unlock_scene":
		return String(row.get("unlock_scene_id", ""))
	var drop: Dictionary = ConfigDB.get_drop(String(row.get("unlock_drop_id", "")))
	return String(drop.get("scene_id", ""))


func _is_upgrade_target_unlocked(row: Dictionary) -> bool:
	match String(row.get("type", "")):
		"unlock_drop":
			return GameState.is_drop_unlocked(String(row.get("unlock_drop_id", "")))
		"unlock_scene":
			return GameState.is_scene_unlocked(String(row.get("unlock_scene_id", "")))
	return false


func _requirements_met(row: Dictionary) -> bool:
	for required_upgrade_id in row.get("requires", []):
		if GameState.get_upgrade_level(required_upgrade_id) <= 0:
			return false
	return true


func _requirement_names(row: Dictionary) -> String:
	var names: Array = []
	for required_upgrade_id in row.get("requires", []):
		var required_row: Dictionary = ConfigDB.get_upgrade(required_upgrade_id)
		names.append(String(required_row.get("name", required_upgrade_id)))
	return "、".join(names)


func _scene_names(scene_ids: Array) -> String:
	if scene_ids.is_empty():
		return "全场景"
	var names: Array = []
	for scene_id in scene_ids:
		names.append(ConfigDB.get_scene_name(String(scene_id)))
	return "、".join(names)


func _clear_list() -> void:
	for child in list.get_children():
		child.queue_free()


func _refresh_tabs() -> void:
	if price_tab_button == null or scene_tab_button == null or helper_tab_button == null or talent_tab_button == null:
		return
	price_tab_button.disabled = _selected_tab == TAB_PRICE
	scene_tab_button.disabled = _selected_tab == TAB_SCENE
	helper_tab_button.disabled = _selected_tab == TAB_HELPER
	talent_tab_button.disabled = _selected_tab == TAB_TALENT


func _refresh_upgrade_subtabs() -> void:
	for scope_id in upgrade_subtab_buttons.keys():
		var btn: Button = upgrade_subtab_buttons.get(scope_id) as Button
		if btn != null:
			btn.set_meta("selected_subtab", String(scope_id) == _selected_upgrade_scope)


func _upgrade_system() -> UpgradeSystem:
	return get_tree().root.get_node_or_null("Main/Systems/UpgradeSystem") as UpgradeSystem


func apply_layout(viewport_size: Vector2) -> void:
	var scale: float = _ui_scale(viewport_size)
	if panel_container != null:
		panel_container.add_theme_stylebox_override("panel", _panel_style(scale))
	if tab_bar != null:
		tab_bar.add_theme_constant_override("separation", int(5.0 * scale))
	if upgrade_subtab_viewport != null:
		upgrade_subtab_viewport.custom_minimum_size = Vector2(0.0, 28.0 * scale)
	if upgrade_subtab_bar != null:
		upgrade_subtab_bar.add_theme_constant_override("separation", int(4.0 * scale))
		for child in upgrade_subtab_bar.get_children():
			var subtab: Button = child as Button
			if subtab != null:
				_style_upgrade_subtab_button(subtab, scale)
	if price_tab_button != null:
		_style_tab_button(price_tab_button, scale)
	if scene_tab_button != null:
		_style_tab_button(scene_tab_button, scale)
	if helper_tab_button != null:
		_style_tab_button(helper_tab_button, scale)
	if talent_tab_button != null:
		_style_tab_button(talent_tab_button, scale)
	if talent_tree != null:
		talent_tree.apply_layout(viewport_size)
	if list != null:
		list.add_theme_constant_override("separation", int(5.0 * scale))
	for child in list.get_children():
		var btn: Button = child as Button
		if btn != null:
			_style_list_button(btn, scale)
			continue
		var helper_row: HBoxContainer = child as HBoxContainer
		if helper_row == null or not bool(helper_row.get_meta("helper_list_row", false)):
			continue
		helper_row.custom_minimum_size = Vector2(0.0, 38.0 * scale)
		helper_row.add_theme_constant_override("separation", int(5.0 * scale))
		for row_child in helper_row.get_children():
			var row_button: Button = row_child as Button
			if row_button != null:
				_style_list_button(row_button, scale)


func _style_list_button(btn: Button, scale: float) -> void:
	var is_toggle: bool = bool(btn.get_meta("helper_toggle", false))
	btn.custom_minimum_size = Vector2(56.0 * scale if is_toggle else 0.0, 38.0 * scale)
	btn.add_theme_font_size_override("font_size", int((11.0 if is_toggle else 12.0) * scale))
	btn.add_theme_color_override("font_color", Color(0.18, 0.15, 0.13, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.38, 0.34, 0.31, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.22, 0.14, 1.0))
	if is_toggle:
		var active: bool = bool(btn.get_meta("helper_active", false))
		var normal_color: Color = Color(0.95, 0.72, 0.62, 1.0) if active else Color(0.63, 0.88, 0.68, 1.0)
		var hover_color: Color = Color(1.0, 0.8, 0.7, 1.0) if active else Color(0.72, 0.96, 0.76, 1.0)
		btn.add_theme_stylebox_override("normal", _button_style(normal_color, Color(0.38, 0.35, 0.29, 1.0), scale))
		btn.add_theme_stylebox_override("hover", _button_style(hover_color, Color(0.3, 0.38, 0.26, 1.0), scale))
		btn.add_theme_stylebox_override("pressed", _button_style(Color(0.82, 0.82, 0.68, 1.0), Color(0.3, 0.34, 0.28, 1.0), scale))
		btn.add_theme_stylebox_override("disabled", _button_style(Color(0.72, 0.7, 0.68, 1.0), Color(0.5, 0.48, 0.46, 1.0), scale))
		return
	btn.add_theme_stylebox_override("normal", _button_style(Color(1.0, 0.96, 0.76, 1.0), Color(0.5, 0.4, 0.24, 1.0), scale))
	btn.add_theme_stylebox_override("hover", _button_style(Color(1.0, 0.9, 0.5, 1.0), Color(0.55, 0.42, 0.18, 1.0), scale))
	btn.add_theme_stylebox_override("disabled", _button_style(Color(0.78, 0.76, 0.7, 1.0), Color(0.54, 0.52, 0.48, 1.0), scale))


func _style_tab_button(btn: Button, scale: float) -> void:
	btn.custom_minimum_size = Vector2(0.0, 30.0 * scale)
	btn.add_theme_font_size_override("font_size", int(12.0 * scale))
	btn.add_theme_color_override("font_color", Color(0.16, 0.13, 0.18, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.95, 0.9, 1.0, 1.0))


func _style_upgrade_subtab_button(btn: Button, scale: float) -> void:
	var selected: bool = bool(btn.get_meta("selected_subtab", false))
	btn.custom_minimum_size = Vector2(58.0 * scale, 26.0 * scale)
	btn.add_theme_font_size_override("font_size", int(11.0 * scale))
	btn.add_theme_color_override("font_color", Color(0.98, 0.95, 1.0, 1.0) if selected else Color(0.25, 0.2, 0.3, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	var normal_color: Color = Color(0.32, 0.27, 0.43, 1.0) if selected else Color(0.9, 0.87, 0.95, 1.0)
	var hover_color: Color = Color(0.39, 0.33, 0.5, 1.0)
	btn.add_theme_stylebox_override("normal", _button_style(normal_color, Color(0.54, 0.46, 0.66, 1.0), scale))
	btn.add_theme_stylebox_override("hover", _button_style(hover_color, Color(0.65, 0.55, 0.78, 1.0), scale))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.26, 0.22, 0.36, 1.0), Color(0.65, 0.55, 0.78, 1.0), scale))


func _ui_scale(viewport_size: Vector2) -> float:
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)


func _panel_style(scale: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.94, 0.99, 0.98)
	style.border_color = Color(0.75, 0.68, 0.88, 1.0)
	style.set_border_width_all(int(2.0 * scale))
	style.set_corner_radius_all(int(8.0 * scale))
	style.content_margin_left = 8.0 * scale
	style.content_margin_right = 8.0 * scale
	style.content_margin_top = 7.0 * scale
	style.content_margin_bottom = 7.0 * scale
	return style


func _button_style(bg: Color, border: Color, scale: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(int(1.0 * scale))
	style.set_corner_radius_all(int(6.0 * scale))
	style.content_margin_left = 7.0 * scale
	style.content_margin_right = 7.0 * scale
	style.content_margin_top = 4.0 * scale
	style.content_margin_bottom = 4.0 * scale
	return style
