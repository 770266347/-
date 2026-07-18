extends Control
## Bottom panel: compact upgrade, scene unlock, and helper purchase tabs.

const BASE_LOGICAL_WIDTH: float = 393.0
const TAB_PRICE: String = "price"
const TAB_SCENE: String = "scene"
const TAB_HELPER: String = "helper"

var panel_container: PanelContainer
var tab_bar: HBoxContainer
var price_tab_button: Button
var scene_tab_button: Button
var helper_tab_button: Button
var list: VBoxContainer
var _selected_tab: String = TAB_PRICE


func _ready() -> void:
	_build()
	EventBus.currency_changed.connect(func(_a: float, _d: float): _refresh())
	EventBus.upgrade_purchased.connect(func(_id, _lv: int): _refresh())
	EventBus.unlocked_drops_changed.connect(func(): _refresh())
	EventBus.scene_unlocked.connect(func(_id: String): _refresh())
	EventBus.helper_purchased.connect(func(_id: String): _refresh())
	EventBus.scene_changed.connect(func(_id: String): _refresh())
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

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)


func _select_tab(tab_id: String) -> void:
	if _selected_tab == tab_id:
		return
	_selected_tab = tab_id
	_refresh()


func _refresh() -> void:
	if list == null:
		return
	_clear_list()
	_refresh_tabs()
	match _selected_tab:
		TAB_SCENE:
			_build_scene_buttons()
		TAB_HELPER:
			_build_helper_buttons()
		_:
			_build_upgrade_buttons()
	apply_layout(get_viewport_rect().size)


func _build_upgrade_buttons() -> void:
	var rows: Array = _ordered_upgrades()
	for row in rows:
		var id = row.get("id", "")
		var btn: Button = _make_list_button(_upgrade_button_text(row))
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
		var btn: Button = _make_list_button(_helper_button_text(row))
		btn.disabled = _upgrade_system() == null or not _upgrade_system().can_buy_helper(id)
		btn.pressed.connect(_on_buy_helper_pressed.bind(id))
		list.add_child(btn)


func _make_list_button(text: String) -> Button:
	var btn: Button = Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return btn


func _on_buy_upgrade_pressed(upgrade_id) -> void:
	var system: UpgradeSystem = _upgrade_system()
	if system != null:
		system.buy(upgrade_id)


func _on_buy_helper_pressed(helper_id: String) -> void:
	var system: UpgradeSystem = _upgrade_system()
	if system != null:
		system.buy_helper(helper_id)


func _upgrade_button_text(row: Dictionary) -> String:
	var cost: float = float(row.get("cost", 0.0))
	var scene_name: String = ConfigDB.get_scene_name(_upgrade_scene_id(row))
	var status: String = "%s 元" % BigNumber.format(cost)
	if _is_upgrade_target_unlocked(row):
		status = "已解锁"
	elif not _requirements_met(row):
		status = "需 %s" % _requirement_names(row)
	elif not GameState.can_afford(cost):
		status = "差钱 %s" % BigNumber.format(cost)
	return "%s｜%s｜%s" % [
		scene_name,
		String(row.get("name", "升级")),
		status
	]


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
	var scenes: Array = row.get("scenes", [])
	if scenes.has(GameState.current_scene_id):
		return "工作中"
	return "已拥有"


func _ordered_upgrades() -> Array:
	var current: Array = []
	var others: Array = []
	for row in ConfigDB.get_upgrades():
		if String(row.get("type", "")) == "unlock_scene":
			continue
		if _upgrade_scene_id(row) == GameState.current_scene_id:
			current.append(row)
		else:
			others.append(row)
	return current + others


func _scene_unlocks() -> Array:
	var out: Array = []
	for row in ConfigDB.get_upgrades():
		if String(row.get("type", "")) == "unlock_scene":
			out.append(row)
	return out


func _upgrade_scene_id(row: Dictionary) -> String:
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
	var names: Array = []
	for scene_id in scene_ids:
		names.append(ConfigDB.get_scene_name(String(scene_id)))
	return "、".join(names)


func _clear_list() -> void:
	for child in list.get_children():
		child.queue_free()


func _refresh_tabs() -> void:
	if price_tab_button == null or scene_tab_button == null or helper_tab_button == null:
		return
	price_tab_button.disabled = _selected_tab == TAB_PRICE
	scene_tab_button.disabled = _selected_tab == TAB_SCENE
	helper_tab_button.disabled = _selected_tab == TAB_HELPER


func _upgrade_system() -> UpgradeSystem:
	return get_tree().root.get_node_or_null("Main/Systems/UpgradeSystem") as UpgradeSystem


func apply_layout(viewport_size: Vector2) -> void:
	var scale: float = _ui_scale(viewport_size)
	if panel_container != null:
		panel_container.add_theme_stylebox_override("panel", _panel_style(scale))
	if tab_bar != null:
		tab_bar.add_theme_constant_override("separation", int(5.0 * scale))
	if price_tab_button != null:
		_style_tab_button(price_tab_button, scale)
	if scene_tab_button != null:
		_style_tab_button(scene_tab_button, scale)
	if helper_tab_button != null:
		_style_tab_button(helper_tab_button, scale)
	if list != null:
		list.add_theme_constant_override("separation", int(5.0 * scale))
	for child in list.get_children():
		var btn: Button = child as Button
		if btn == null:
			continue
		btn.custom_minimum_size = Vector2(0.0, 38.0 * scale)
		btn.add_theme_font_size_override("font_size", int(12.0 * scale))
		btn.add_theme_color_override("font_color", Color(0.18, 0.15, 0.13, 1.0))
		btn.add_theme_color_override("font_disabled_color", Color(0.38, 0.34, 0.31, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.08, 0.22, 0.14, 1.0))
		btn.add_theme_stylebox_override("normal", _button_style(Color(1.0, 0.96, 0.76, 1.0), Color(0.5, 0.4, 0.24, 1.0), scale))
		btn.add_theme_stylebox_override("hover", _button_style(Color(1.0, 0.9, 0.5, 1.0), Color(0.55, 0.42, 0.18, 1.0), scale))
		btn.add_theme_stylebox_override("disabled", _button_style(Color(0.78, 0.76, 0.7, 1.0), Color(0.54, 0.52, 0.48, 1.0), scale))


func _style_tab_button(btn: Button, scale: float) -> void:
	btn.custom_minimum_size = Vector2(0.0, 30.0 * scale)
	btn.add_theme_font_size_override("font_size", int(12.0 * scale))
	btn.add_theme_color_override("font_color", Color(0.16, 0.13, 0.18, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.95, 0.9, 1.0, 1.0))


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
