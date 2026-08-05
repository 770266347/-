class_name DefenseMode
extends Control
## 街区防守玩法主控制器。
##
## 负责关卡选择、波次队列、顶部/左右出怪、敌人移动、帮手圆形攻击、
## 胜负结算和拖放阵容。DefenseSlot/Card 只负责 UI 拖放，所有战斗权威状态
## （敌人节点、生命、冷却、关卡进度）集中在此脚本。

# 战斗区域采用自由坐标，敌人不绑定五条道路；三个方向共享出怪权重。

const BASE_LOGICAL_WIDTH: float = 393.0
const DEFENSE_SLOT_COUNT: int = 5
const BASE_MAX_HP: int = 100
const ENEMY_LIMIT: int = 18
const TOP_BAND_HEIGHT_PT: float = 64.0
const ROSTER_HEIGHT_PT: float = 166.0
const SLOT_HEIGHT_PT: float = 82.0
const ENEMY_SIZE_PT: Vector2 = Vector2(54.0, 66.0)
const SIDE_PORTAL_SIZE_PT: Vector2 = Vector2(30.0, 76.0)
const SPAWN_TOP: String = "top"
const SPAWN_LEFT: String = "left"
const SPAWN_RIGHT: String = "right"

var background: TextureRect
var shade: ColorRect
var range_layer: DefenseRangeLayer
var left_spawn_portal: Panel
var right_spawn_portal: Panel
var combat_layer: Control
var top_panel: PanelContainer
var back_button: Button
var title_label: Label
var wave_label: Label
var status_label: Label
var slot_row: HBoxContainer
var roster_panel: PanelContainer
var roster_title_label: Label
var deployed_label: Label
var roster_scroll: ScrollContainer
var roster_row: HBoxContainer
var result_panel: PanelContainer
var result_label: Label
var restart_button: Button
var level_select_button: Button
var level_select_panel: PanelContainer
var level_grid: GridContainer
var level_buttons: Dictionary = {}
var slots: Array[DefenseSlot] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _active: bool = false
var _battle_started: bool = false
var _battle_over: bool = false
var _base_hp: int = BASE_MAX_HP
var _defeated: int = 0
var _spawn_timer: float = 0.6
var _current_level_id: int = 0
var _current_level: Dictionary = {}
var _spawn_queue: Array = []
var _spawn_index: int = 0
var _current_wave_number: int = 0
var _result_was_victory: bool = false
var _assigned_helpers: Dictionary = {}
var _attack_cooldowns: Dictionary = {}
var _last_layout_scale: float = 0.0


func _ready() -> void:
	## 创建防守 UI，订阅关卡完成事件，并保持模式初始关闭。
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	_build()
	visible = false
	set_process(false)
	call_deferred("apply_layout", get_viewport_rect().size)


func _process(delta: float) -> void:
	## 仅在模式打开且战斗进行中推进出怪、敌人移动和帮手攻击。
	if not _active or not _battle_started or _battle_over:
		return
	_update_enemy_spawning(delta)
	_update_enemies(delta)
	_update_helpers(delta)
	_check_level_completion()


func _build() -> void:
	## 组装背景、出怪口、顶部状态、帮手栏、结果层和关卡选择层。
	background = TextureRect.new()
	background.texture = load("res://assets/street_pickup_bg_clean.png") as Texture2D
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	shade = ColorRect.new()
	shade.color = Color(0.08, 0.1, 0.11, 0.24)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	range_layer = DefenseRangeLayer.new()
	range_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(range_layer)

	left_spawn_portal = _make_spawn_portal(">")
	add_child(left_spawn_portal)
	right_spawn_portal = _make_spawn_portal("<")
	add_child(right_spawn_portal)

	combat_layer = Control.new()
	combat_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(combat_layer)

	_build_top_band()

	slot_row = HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(slot_row)

	_build_roster_panel()
	_build_level_select_panel()
	_build_result_panel()


func _make_spawn_portal(direction_text: String) -> Panel:
	## 创建只做视觉提示的出怪口，实际出生位置由配置和随机源决定。
	var portal: Panel = Panel.new()
	portal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portal.z_index = 12
	var direction_label: Label = Label.new()
	direction_label.text = direction_text
	direction_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	direction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	direction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	direction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	direction_label.set_meta("portal_direction", true)
	portal.add_child(direction_label)
	return portal


func _build_top_band() -> void:
	## 创建关卡标题、波次、耐久和剩余敌人等战斗摘要。
	top_panel = PanelContainer.new()
	top_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(top_panel)

	var row: HBoxContainer = HBoxContainer.new()
	top_panel.add_child(row)

	back_button = Button.new()
	back_button.text = "<"
	back_button.tooltip_text = "返回主界面"
	back_button.pressed.connect(func(): EventBus.defense_mode_exit_requested.emit())
	row.add_child(back_button)

	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_box)

	title_label = Label.new()
	title_label.text = "街区防守"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(title_label)

	wave_label = Label.new()
	wave_label.text = "第 1 波"
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(wave_label)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(status_label)


func _build_roster_panel() -> void:
	## 创建可拖动帮手卡片和五个防守格子容器。
	roster_panel = PanelContainer.new()
	roster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(roster_panel)

	var box: VBoxContainer = VBoxContainer.new()
	roster_panel.add_child(box)

	var header: HBoxContainer = HBoxContainer.new()
	box.add_child(header)

	roster_title_label = Label.new()
	roster_title_label.text = "帮手栏"
	roster_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(roster_title_label)

	deployed_label = Label.new()
	deployed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(deployed_label)

	roster_scroll = ScrollContainer.new()
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(roster_scroll)

	roster_row = HBoxContainer.new()
	roster_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	roster_scroll.add_child(roster_row)


func _build_result_panel() -> void:
	## 创建胜利/失败共用结果面板，按钮行为由当前结果状态决定。
	result_panel = PanelContainer.new()
	result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	result_panel.visible = false
	result_panel.z_index = 100
	add_child(result_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	result_panel.add_child(box)

	result_label = Label.new()
	result_label.text = "防线失守"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(result_label)

	restart_button = Button.new()
	restart_button.text = "重新挑战"
	restart_button.pressed.connect(_on_result_primary_pressed)
	box.add_child(restart_button)

	level_select_button = Button.new()
	level_select_button.text = "关卡选择"
	level_select_button.pressed.connect(_show_level_selection)
	box.add_child(level_select_button)


func _build_level_select_panel() -> void:
	## 根据 ConfigDB 关卡表建立可解锁关卡按钮。
	level_select_panel = PanelContainer.new()
	level_select_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	level_select_panel.z_index = 90
	level_select_panel.visible = false
	add_child(level_select_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	level_select_panel.add_child(box)

	var heading: Label = Label.new()
	heading.text = "选择防守关卡"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.set_meta("level_heading", true)
	box.add_child(heading)

	level_grid = GridContainer.new()
	level_grid.columns = 5
	level_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(level_grid)

	for level in ConfigDB.get_defense_levels():
		var level_id: int = int(level.get("id", 0))
		var button: Button = Button.new()
		button.text = "%d\n%s" % [level_id, String(level.get("name", "关卡"))]
		button.tooltip_text = "第 %d 关：%s" % [level_id, String(level.get("name", ""))]
		button.pressed.connect(_start_level.bind(level_id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		level_grid.add_child(button)
		level_buttons[level_id] = button


func open_mode() -> void:
	## 打开模式并显示关卡选择；尚未开始战斗时不生成敌人。
	visible = true
	_active = true
	_refresh_roster()
	apply_layout(get_viewport_rect().size)
	set_process(true)
	_show_level_selection()


func close_mode() -> void:
	## 退出模式并清理敌人、攻击闪光和当前阵容运行节点。
	_active = false
	_battle_started = false
	set_process(false)
	_clear_combat_nodes()
	visible = false


func _reset_battle() -> void:
	## 清空单局战斗状态，不影响玩家永久关卡通关记录。
	if _current_level.is_empty():
		_show_level_selection()
		return
	_clear_combat_nodes()
	_battle_started = true
	_battle_over = false
	_base_hp = int(_current_level.get("base_hp", BASE_MAX_HP))
	_defeated = 0
	_spawn_timer = 0.45
	_spawn_queue = _build_spawn_queue(_current_level)
	_spawn_index = 0
	_current_wave_number = 1
	_attack_cooldowns.clear()
	result_panel.visible = false
	level_select_panel.visible = false
	range_layer.visible = true
	left_spawn_portal.visible = true
	right_spawn_portal.visible = true
	title_label.text = "第 %d 关 %s" % [_current_level_id, String(_current_level.get("name", ""))]
	_refresh_status()


func _show_level_selection() -> void:
	## 显示关卡选择并隐藏战斗中的临时节点。
	_clear_combat_nodes()
	_battle_started = false
	_battle_over = false
	result_panel.visible = false
	level_select_panel.visible = true
	range_layer.visible = false
	left_spawn_portal.visible = false
	right_spawn_portal.visible = false
	title_label.text = "街区防守"
	wave_label.text = "选择关卡"
	status_label.text = "已解锁\n%d/%d" % [GameState.defense_highest_unlocked_level, ConfigDB.get_defense_max_level()]
	_refresh_level_buttons()


func _refresh_level_buttons() -> void:
	## 按最高解锁关卡和 cleared 状态刷新按钮。
	var scale: float = _ui_scale(get_viewport_rect().size)
	for level_id_variant in level_buttons.keys():
		var level_id: int = int(level_id_variant)
		var button: Button = level_buttons.get(level_id) as Button
		if button == null:
			continue
		var row: Dictionary = ConfigDB.get_defense_level(level_id)
		button.disabled = not GameState.is_defense_level_unlocked(level_id)
		var state_text: String = "已通关" if GameState.is_defense_level_cleared(level_id) else ("未解锁" if button.disabled else "可挑战")
		button.tooltip_text = "第 %d 关：%s｜%s" % [level_id, String(row.get("name", "")), state_text]
		_style_level_button(button, GameState.is_defense_level_cleared(level_id), scale)


func _start_level(level_id: int) -> void:
	## 读取关卡波次、耐久和敌人配置，初始化一局战斗。
	if not GameState.is_defense_level_unlocked(level_id):
		return
	var row: Dictionary = ConfigDB.get_defense_level(level_id)
	if row.is_empty():
		return
	_current_level_id = level_id
	_current_level = row
	_reset_battle()


func _build_spawn_queue(level: Dictionary) -> Array:
	## 将关卡波次展开成按时间顺序出现的敌人 ID 队列。
	var queue: Array = []
	var waves: Array = level.get("waves", [])
	var wave_gap: float = float(level.get("wave_gap", 2.0))
	for wave_index in range(waves.size()):
		var wave: Dictionary = waves[wave_index]
		var interval: float = float(wave.get("spawn_interval", 1.0))
		var first_in_wave: bool = true
		for group in wave.get("groups", []):
			var enemy_id: String = String(group.get("enemy_id", ""))
			if ConfigDB.get_defense_enemy(enemy_id).is_empty():
				continue
			for enemy_index in range(maxi(0, int(group.get("count", 0)))):
				queue.append({
					"enemy_id": enemy_id,
					"wave": wave_index + 1,
					"delay_before": wave_gap if wave_index > 0 and first_in_wave else interval,
				})
				first_in_wave = false
	return queue


func _refresh_roster() -> void:
	## 只展示已购买帮手；已部署帮手从卡片栏移到对应格子状态。
	for child in roster_row.get_children():
		child.queue_free()
	var scale: float = _ui_scale(get_viewport_rect().size)
	var owned_count: int = 0
	for row in ConfigDB.get_helpers():
		var helper_id: String = String(row.get("id", ""))
		if helper_id.is_empty() or not GameState.has_helper(helper_id):
			continue
		var card: DefenseHelperCard = DefenseHelperCard.new()
		card.configure(row, scale)
		roster_row.add_child(card)
		owned_count += 1
	if owned_count == 0:
		var empty_label: Label = Label.new()
		empty_label.text = "暂无可用帮手"
		empty_label.custom_minimum_size = Vector2(180.0, 78.0) * scale
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", int(14.0 * scale))
		roster_row.add_child(empty_label)
	_refresh_deployed_label()


func _rebuild_slots(scale: float) -> void:
	## 重新创建固定数量的防守格子，保证布局尺寸稳定。
	for child in slot_row.get_children():
		child.queue_free()
	slots.clear()
	slot_row.add_theme_constant_override("separation", int(5.0 * scale))
	for slot_index in range(DEFENSE_SLOT_COUNT):
		var slot: DefenseSlot = DefenseSlot.new()
		slot.configure(slot_index, scale)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.helper_dropped.connect(_on_helper_dropped)
		slot_row.add_child(slot)
		slots.append(slot)
		var helper_id: String = String(_assigned_helpers.get(slot_index, ""))
		if not helper_id.is_empty():
			var row: Dictionary = ConfigDB.get_helper(helper_id)
			if not row.is_empty() and GameState.has_helper(helper_id):
				slot.assign_helper(row)
			else:
				_assigned_helpers.erase(slot_index)
	_refresh_deployed_label()
	call_deferred("_refresh_attack_ranges")


func _on_helper_dropped(slot_index: int, helper_id: String) -> void:
	## 校验拖放帮手并处理换位或覆盖旧格子的规则。
	if not _active or not GameState.has_helper(helper_id):
		return
	for existing_slot_variant in _assigned_helpers.keys():
		var existing_slot: int = int(existing_slot_variant)
		if String(_assigned_helpers.get(existing_slot, "")) == helper_id:
			_assigned_helpers.erase(existing_slot)
			if existing_slot >= 0 and existing_slot < slots.size():
				slots[existing_slot].clear_helper()
	_assigned_helpers[slot_index] = helper_id
	if slot_index >= 0 and slot_index < slots.size():
		slots[slot_index].assign_helper(ConfigDB.get_helper(helper_id))
	_attack_cooldowns[slot_index] = 0.0
	_refresh_deployed_label()
	_refresh_attack_ranges()


func _update_enemy_spawning(delta: float) -> void:
	## 按波次队列时间生成敌人，全部生成后停止出怪。
	if _spawn_index >= _spawn_queue.size():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0 or _enemy_count() >= ENEMY_LIMIT:
		return
	var entry: Dictionary = _spawn_queue[_spawn_index]
	_spawn_enemy(String(entry.get("enemy_id", "")))
	_current_wave_number = int(entry.get("wave", 1))
	_spawn_index += 1
	if _spawn_index < _spawn_queue.size():
		_spawn_timer = float((_spawn_queue[_spawn_index] as Dictionary).get("delay_before", 1.0))
	_refresh_status()


func _spawn_enemy(enemy_id: String) -> void:
	## 创建敌人节点并写入生命、速度、出生方向和目标位置元数据。
	var enemy_row: Dictionary = ConfigDB.get_defense_enemy(enemy_id)
	if enemy_row.is_empty():
		return
	var scale: float = _ui_scale(get_viewport_rect().size)
	var is_boss: bool = bool(enemy_row.get("boss", false))
	var visual_scale: float = float(enemy_row.get("visual_scale", 1.0))
	var enemy: TextureRect = TextureRect.new()
	enemy.texture = load(String(enemy_row.get("sprite", ""))) as Texture2D
	enemy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	enemy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	enemy.size = ENEMY_SIZE_PT * scale * visual_scale
	enemy.pivot_offset = enemy.size * 0.5
	var spawn_source: String = SPAWN_TOP if is_boss else _pick_spawn_source()
	enemy.position = _enemy_spawn_position(spawn_source, enemy.size)
	enemy.modulate = Color.from_string(String(enemy_row.get("tint", "#ffffff")), Color.WHITE)
	enemy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy.z_index = 45 if is_boss else 20
	enemy.set_meta("is_defense_enemy", true)
	enemy.set_meta("spawn_source", spawn_source)
	enemy.set_meta("target_position", _random_defense_target())
	enemy.set_meta("enemy_id", enemy_id)
	enemy.set_meta("enemy_name", String(enemy_row.get("name", "敌人")))
	enemy.set_meta("boss", is_boss)
	var max_hp: float = float(enemy_row.get("hp", 5.0)) * float(_current_level.get("hp_multiplier", 1.0))
	enemy.set_meta("hp", max_hp)
	enemy.set_meta("max_hp", max_hp)
	enemy.set_meta("speed", float(enemy_row.get("speed", 28.0)) * float(_current_level.get("speed_multiplier", 1.0)))
	enemy.set_meta("base_damage", maxi(1, int(round(
		float(enemy_row.get("base_damage", 10.0)) * float(_current_level.get("damage_multiplier", 1.0))
	))))
	combat_layer.add_child(enemy)

	var hp_bar: ProgressBar = ProgressBar.new()
	hp_bar.position = Vector2(4.0 * scale, -8.0 * scale)
	hp_bar.size = Vector2(maxf(46.0 * scale, enemy.size.x - 8.0 * scale), (8.0 if is_boss else 6.0) * scale)
	hp_bar.max_value = max_hp
	hp_bar.value = max_hp
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.set_meta("enemy_hp_bar", true)
	enemy.add_child(hp_bar)
	if is_boss:
		var boss_label: Label = Label.new()
		boss_label.text = String(enemy_row.get("name", "头目"))
		boss_label.position = Vector2(-10.0, -22.0) * scale
		boss_label.size = Vector2(enemy.size.x + 20.0 * scale, 18.0 * scale)
		boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_label.add_theme_font_size_override("font_size", int(12.0 * scale))
		boss_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32, 1.0))
		boss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		enemy.add_child(boss_label)


func _pick_spawn_source() -> String:
	## 按 top/left/right 配置权重随机选择出怪口。
	var weights: Dictionary = ConfigDB.get_defense_spawn_weights()
	var top_weight: float = maxf(0.0, float(weights.get(SPAWN_TOP, 60.0)))
	var left_weight: float = maxf(0.0, float(weights.get(SPAWN_LEFT, 20.0)))
	var right_weight: float = maxf(0.0, float(weights.get(SPAWN_RIGHT, 20.0)))
	var total_weight: float = top_weight + left_weight + right_weight
	if total_weight <= 0.0:
		return SPAWN_TOP
	var roll: float = _rng.randf_range(0.0, total_weight)
	if roll <= top_weight:
		return SPAWN_TOP
	if roll <= top_weight + left_weight:
		return SPAWN_LEFT
	return SPAWN_RIGHT


func _enemy_spawn_position(source: String, enemy_size: Vector2) -> Vector2:
	## 在选定出怪口附近生成随机位置，避免敌人排成固定道路。
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = _ui_scale(viewport_size)
	var margin: float = 16.0 * scale
	match source:
		SPAWN_LEFT:
			return _portal_center(left_spawn_portal) - enemy_size * 0.5
		SPAWN_RIGHT:
			return _portal_center(right_spawn_portal) - enemy_size * 0.5
	var min_x: float = margin
	var max_x: float = maxf(min_x, viewport_size.x - enemy_size.x - margin)
	return Vector2(_rng.randf_range(min_x, max_x), (TOP_BAND_HEIGHT_PT + 36.0) * scale)


func _random_defense_target() -> Vector2:
	## 为敌人生成向下移动的自由目标点，保持出怪路线混乱。
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = _ui_scale(viewport_size)
	var margin: float = 20.0 * scale
	return Vector2(_rng.randf_range(margin, viewport_size.x - margin), _defense_line_y())


func _update_enemies(delta: float) -> void:
	## 推进敌人到目标；抵达防线后减少基地耐久并移除敌人。
	var scale: float = _ui_scale(get_viewport_rect().size)
	for child in combat_layer.get_children():
		var enemy: TextureRect = child as TextureRect
		if enemy == null or enemy.is_queued_for_deletion() or not bool(enemy.get_meta("is_defense_enemy", false)):
			continue
		if bool(enemy.get_meta("defeated", false)):
			continue
		var target_position: Vector2 = enemy.get_meta("target_position", Vector2(enemy.position.x, _defense_line_y()))
		var enemy_center: Vector2 = enemy.position + enemy.size * 0.5
		var offset: Vector2 = target_position - enemy_center
		var step: float = float(enemy.get_meta("speed", 28.0)) * scale * delta
		if offset.length() > maxf(step, 3.0 * scale):
			enemy.position += offset.normalized() * step
			enemy.flip_h = offset.x < 0.0
			enemy.z_index = 20 + clampi(int(enemy.position.y / scale), 0, 500)
			continue
		_base_hp = maxi(0, _base_hp - int(enemy.get_meta("base_damage", 10)))
		enemy.queue_free()
		_refresh_status()
		if _base_hp <= 0:
			_end_battle(false)
			return


func _update_helpers(delta: float) -> void:
	## 按部署格处理攻击冷却，并查找攻击范围内最近敌人。
	for slot_index in range(DEFENSE_SLOT_COUNT):
		var helper_id: String = String(_assigned_helpers.get(slot_index, ""))
		if helper_id.is_empty() or not GameState.has_helper(helper_id):
			continue
		var remaining: float = maxf(0.0, float(_attack_cooldowns.get(slot_index, 0.0)) - delta)
		_attack_cooldowns[slot_index] = remaining
		if remaining > 0.0:
			continue
		var row: Dictionary = ConfigDB.get_helper(helper_id)
		var target: TextureRect = _nearest_enemy_in_range(slot_index, row)
		if target == null:
			continue
		var damage: float = maxf(1.0, roundf(float(row.get("speed", 80.0)) / 42.0))
		_damage_enemy(target, damage)
		_attack_cooldowns[slot_index] = maxf(0.34, float(row.get("collect_cooldown", 1.0)) * 0.62)
		_spawn_attack_flash(slot_index, target)


func _nearest_enemy_in_range(slot_index: int, helper_row: Dictionary) -> TextureRect:
	## 使用 defense_range 做圆形距离判定，返回范围内最近目标。
	var target: TextureRect = null
	var smallest_distance_to_defense: float = INF
	var helper_center: Vector2 = _helper_defense_center(slot_index)
	var attack_radius: float = float(helper_row.get("defense_range", 145.0)) * _ui_scale(get_viewport_rect().size)
	for child in combat_layer.get_children():
		var enemy: TextureRect = child as TextureRect
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		if not bool(enemy.get_meta("is_defense_enemy", false)) or bool(enemy.get_meta("defeated", false)):
			continue
		var enemy_center: Vector2 = enemy.position + enemy.size * 0.5
		if helper_center.distance_to(enemy_center) > attack_radius:
			continue
		var defense_target: Vector2 = enemy.get_meta("target_position", Vector2(enemy_center.x, _defense_line_y()))
		var distance_to_defense: float = enemy_center.distance_to(defense_target)
		if distance_to_defense < smallest_distance_to_defense:
			smallest_distance_to_defense = distance_to_defense
			target = enemy
	return target


func _damage_enemy(enemy: TextureRect, damage: float) -> void:
	## 扣除敌人生命，并在归零时发放击杀反馈和移除节点。
	if enemy == null or not is_instance_valid(enemy) or bool(enemy.get_meta("defeated", false)):
		return
	var hp: float = maxf(0.0, float(enemy.get_meta("hp", 0.0)) - damage)
	enemy.set_meta("hp", hp)
	for child in enemy.get_children():
		var hp_bar: ProgressBar = child as ProgressBar
		if hp_bar != null and bool(hp_bar.get_meta("enemy_hp_bar", false)):
			hp_bar.value = hp
	if hp > 0.0:
		return
	enemy.set_meta("defeated", true)
	_defeated += 1
	_refresh_status()
	var tween: Tween = create_tween()
	tween.tween_property(enemy, "scale", Vector2(0.7, 0.7), 0.14)
	tween.parallel().tween_property(enemy, "modulate:a", 0.0, 0.14)
	tween.finished.connect(_free_instance_by_id.bind(int(enemy.get_instance_id())))


func _spawn_attack_flash(slot_index: int, target: TextureRect) -> void:
	## 绘制一次性攻击反馈，不参与命中计算。
	if target == null or not is_instance_valid(target):
		return
	var scale: float = _ui_scale(get_viewport_rect().size)
	var shot: Panel = Panel.new()
	shot.size = Vector2(10.0, 10.0) * scale
	shot.position = _helper_defense_center(slot_index) - shot.size * 0.5
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot.z_index = 60
	shot.add_theme_stylebox_override("panel", _round_style(Color(1.0, 0.84, 0.24, 1.0), Color(1.0, 0.96, 0.7, 1.0), 1.0, 5.0, scale))
	shot.set_meta("is_defense_projectile", true)
	combat_layer.add_child(shot)
	var target_position: Vector2 = target.position + target.size * 0.5 - shot.size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(shot, "position", target_position, 0.12)
	tween.finished.connect(_free_instance_by_id.bind(int(shot.get_instance_id())))


func _check_level_completion() -> void:
	## 确认所有敌人清除且所有波次已生成，避免提前胜利。
	if _battle_over or _spawn_index < _spawn_queue.size() or _enemy_count() > 0:
		return
	_end_battle(true)


func _end_battle(victory: bool) -> void:
	## 结束单局并停止临时逻辑；胜利时推进永久关卡解锁。
	_battle_over = true
	_battle_started = false
	_result_was_victory = victory
	if victory:
		GameState.complete_defense_level(_current_level_id)
		SaveManager.save_game()
		result_label.text = "第 %d 关通关\n击退 %d 人" % [_current_level_id, _defeated]
		restart_button.text = "下一关" if _current_level_id < ConfigDB.get_defense_max_level() else "再次挑战"
	else:
		result_label.text = "防线失守\n击退 %d 人" % _defeated
		restart_button.text = "重新挑战"
	result_panel.visible = true


func _on_result_primary_pressed() -> void:
	## 结果按钮根据胜负返回关卡选择或关闭防守模式。
	if _result_was_victory and _current_level_id < ConfigDB.get_defense_max_level():
		_start_level(_current_level_id + 1)
	else:
		_reset_battle()


func _clear_combat_nodes() -> void:
	## 清理单局敌人和临时特效，不清理帮手购买状态。
	if combat_layer == null:
		return
	for child in combat_layer.get_children():
		child.queue_free()


func _enemy_count() -> int:
	## 返回当前场上敌人节点数量，用于顶部状态和胜负判断。
	var count: int = 0
	for child in combat_layer.get_children():
		if not child.is_queued_for_deletion() and bool(child.get_meta("is_defense_enemy", false)) and not bool(child.get_meta("defeated", false)):
			count += 1
	return count


func _refresh_status() -> void:
	## 将单局状态同步到顶部标题和波次摘要。
	if status_label == null:
		return
	var max_hp: int = int(_current_level.get("base_hp", BASE_MAX_HP))
	var remaining: int = maxi(0, _spawn_queue.size() - _spawn_index + _enemy_count())
	status_label.text = "耐久 %d/%d\n剩余 %d" % [_base_hp, max_hp, remaining]
	var wave_count: int = (_current_level.get("waves", []) as Array).size()
	wave_label.text = "第 %d/%d 波｜击退 %d" % [_current_wave_number, wave_count, _defeated]


func _refresh_deployed_label() -> void:
	## 显示已部署帮手数量和格子总数。
	if deployed_label != null:
		deployed_label.text = "布阵 %d/%d" % [_assigned_helpers.size(), DEFENSE_SLOT_COUNT]


func apply_layout(viewport_size: Vector2) -> void:
	## 布局全屏战斗区域、三处出怪口、帮手栏和结果弹窗。
	if background == null:
		return
	var scale: float = _ui_scale(viewport_size)
	background.position = Vector2.ZERO
	background.size = viewport_size
	shade.position = Vector2.ZERO
	shade.size = viewport_size
	range_layer.position = Vector2.ZERO
	range_layer.size = viewport_size
	combat_layer.position = Vector2.ZERO
	combat_layer.size = viewport_size

	var margin: float = 10.0 * scale
	top_panel.position = Vector2(margin, margin)
	top_panel.size = Vector2(viewport_size.x - margin * 2.0, TOP_BAND_HEIGHT_PT * scale)
	top_panel.add_theme_stylebox_override("panel", _round_style(Color(0.11, 0.14, 0.16, 0.92), Color(0.95, 0.73, 0.24, 1.0), 2.0, 6.0, scale))
	back_button.custom_minimum_size = Vector2(44.0, 44.0) * scale
	back_button.add_theme_font_size_override("font_size", int(20.0 * scale))
	title_label.add_theme_font_size_override("font_size", int(18.0 * scale))
	title_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.7, 1.0))
	wave_label.add_theme_font_size_override("font_size", int(11.0 * scale))
	wave_label.add_theme_color_override("font_color", Color(0.76, 0.9, 0.95, 1.0))
	status_label.custom_minimum_size = Vector2(82.0, 44.0) * scale
	status_label.add_theme_font_size_override("font_size", int(11.0 * scale))
	status_label.add_theme_color_override("font_color", Color(0.94, 0.98, 0.9, 1.0))

	var roster_top: float = viewport_size.y - ROSTER_HEIGHT_PT * scale - margin
	roster_panel.position = Vector2(margin, roster_top)
	roster_panel.size = Vector2(viewport_size.x - margin * 2.0, ROSTER_HEIGHT_PT * scale)
	roster_panel.add_theme_stylebox_override("panel", _round_style(Color(0.9, 0.88, 0.82, 0.98), Color(0.34, 0.31, 0.29, 1.0), 2.0, 6.0, scale))
	roster_title_label.add_theme_font_size_override("font_size", int(15.0 * scale))
	deployed_label.add_theme_font_size_override("font_size", int(12.0 * scale))
	roster_row.add_theme_constant_override("separation", int(6.0 * scale))

	var slot_top: float = roster_top - SLOT_HEIGHT_PT * scale - 10.0 * scale
	slot_row.position = Vector2(margin, slot_top)
	slot_row.size = Vector2(viewport_size.x - margin * 2.0, SLOT_HEIGHT_PT * scale)

	var combat_top: float = (TOP_BAND_HEIGHT_PT + 36.0) * scale
	var portal_size: Vector2 = SIDE_PORTAL_SIZE_PT * scale
	var portal_y: float = combat_top + maxf(0.0, slot_top - combat_top - portal_size.y) * 0.43
	left_spawn_portal.position = Vector2(2.0 * scale, portal_y)
	left_spawn_portal.size = portal_size
	right_spawn_portal.position = Vector2(viewport_size.x - portal_size.x - 2.0 * scale, portal_y)
	right_spawn_portal.size = portal_size
	for portal in [left_spawn_portal, right_spawn_portal]:
		portal.add_theme_stylebox_override("panel", _round_style(Color(0.16, 0.1, 0.24, 0.94), Color(0.48, 0.9, 0.86, 0.94), 2.0, 14.0, scale))
		for child in portal.get_children():
			var direction_label: Label = child as Label
			if direction_label != null and bool(direction_label.get_meta("portal_direction", false)):
				direction_label.add_theme_font_size_override("font_size", int(18.0 * scale))
				direction_label.add_theme_color_override("font_color", Color(0.78, 1.0, 0.92, 1.0))

	level_select_panel.size = Vector2(350.0, 230.0) * scale
	level_select_panel.position = Vector2((viewport_size.x - level_select_panel.size.x) * 0.5, 150.0 * scale)
	level_select_panel.add_theme_stylebox_override("panel", _round_style(Color(0.12, 0.14, 0.16, 0.97), Color(0.96, 0.73, 0.25, 1.0), 3.0, 6.0, scale))
	level_grid.add_theme_constant_override("h_separation", int(5.0 * scale))
	level_grid.add_theme_constant_override("v_separation", int(6.0 * scale))
	for child in level_select_panel.find_children("*", "Label", true, false):
		var heading: Label = child as Label
		if heading != null and bool(heading.get_meta("level_heading", false)):
			heading.add_theme_font_size_override("font_size", int(19.0 * scale))
			heading.add_theme_color_override("font_color", Color(1.0, 0.92, 0.66, 1.0))
	for button_variant in level_buttons.values():
		var level_button: Button = button_variant as Button
		if level_button != null:
			level_button.custom_minimum_size = Vector2(61.0, 66.0) * scale
			level_button.add_theme_font_size_override("font_size", int(10.0 * scale))
	_refresh_level_buttons()

	result_panel.size = Vector2(250.0, 190.0) * scale
	result_panel.position = (viewport_size - result_panel.size) * 0.5
	result_panel.add_theme_stylebox_override("panel", _round_style(Color(0.12, 0.14, 0.16, 0.97), Color(0.96, 0.73, 0.25, 1.0), 3.0, 6.0, scale))
	result_label.add_theme_font_size_override("font_size", int(22.0 * scale))
	result_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.66, 1.0))
	restart_button.custom_minimum_size = Vector2(160.0, 42.0) * scale
	restart_button.add_theme_font_size_override("font_size", int(15.0 * scale))
	level_select_button.custom_minimum_size = Vector2(160.0, 38.0) * scale
	level_select_button.add_theme_font_size_override("font_size", int(14.0 * scale))

	if not is_equal_approx(_last_layout_scale, scale):
		_last_layout_scale = scale
		_rebuild_slots(scale)
		if _active:
			_refresh_roster()
	call_deferred("_refresh_attack_ranges")


func _portal_center(portal: Control) -> Vector2:
	## 将出怪口控件坐标转换为战斗区域中心坐标。
	if portal == null:
		return Vector2.ZERO
	return portal.position + portal.size * 0.5


func _helper_defense_center(slot_index: int) -> Vector2:
	## 返回防守格中心，攻击范围圆和攻击起点共用此位置。
	if slot_index >= 0 and slot_index < slots.size():
		var slot: DefenseSlot = slots[slot_index]
		if slot != null and is_instance_valid(slot) and not slot.is_queued_for_deletion() and slot.size.x > 0.0:
			return slot_row.position + slot.position + slot.size * 0.5
	var viewport_size: Vector2 = get_viewport_rect().size
	var scale: float = _ui_scale(viewport_size)
	var margin: float = 10.0 * scale
	var usable_width: float = viewport_size.x - margin * 2.0
	return Vector2(
		margin + usable_width * (float(slot_index) + 0.5) / float(DEFENSE_SLOT_COUNT),
		_defense_line_y() + SLOT_HEIGHT_PT * scale * 0.5
	)


func _refresh_attack_ranges() -> void:
	## 为所有已部署帮手提交当前攻击圆快照给绘制层。
	if range_layer == null:
		return
	var scale: float = _ui_scale(get_viewport_rect().size)
	var ranges: Array = []
	for slot_index_variant in _assigned_helpers.keys():
		var slot_index: int = int(slot_index_variant)
		var helper_id: String = String(_assigned_helpers.get(slot_index, ""))
		var row: Dictionary = ConfigDB.get_helper(helper_id)
		if row.is_empty() or not GameState.has_helper(helper_id):
			continue
		ranges.append({
			"center": _helper_defense_center(slot_index),
			"radius": float(row.get("defense_range", 145.0)) * scale,
			"line_width": 1.4 * scale,
		})
	range_layer.set_ranges(ranges)


func _defense_line_y() -> float:
	## 计算敌人抵达后扣除耐久的防线 Y 坐标。
	var scale: float = _ui_scale(get_viewport_rect().size)
	return get_viewport_rect().size.y - ROSTER_HEIGHT_PT * scale - SLOT_HEIGHT_PT * scale - 14.0 * scale


func _free_instance_by_id(instance_id: int) -> void:
	## 按实例 ID 安全释放临时战斗节点。
	var node: Node = instance_from_id(instance_id) as Node
	if is_instance_valid(node):
		node.queue_free()


func _ui_scale(viewport_size: Vector2) -> float:
	## 以 iPhone 16 逻辑宽度计算防守 UI 缩放。
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)


func _round_style(bg: Color, border: Color, border_width: float, radius: float, scale: float) -> StyleBoxFlat:
	## 生成防守面板、格子和按钮共用的圆角样式。
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(int(border_width * scale))
	style.set_corner_radius_all(int(radius * scale))
	style.content_margin_left = 7.0 * scale
	style.content_margin_right = 7.0 * scale
	style.content_margin_top = 5.0 * scale
	style.content_margin_bottom = 5.0 * scale
	return style


func _style_level_button(button: Button, cleared: bool, scale: float) -> void:
	## 根据关卡是否已通关设置按钮颜色和文字尺寸。
	var normal_color: Color = Color(0.25, 0.45, 0.31, 0.98) if cleared else Color(0.45, 0.35, 0.18, 0.98)
	button.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.58, 0.6, 0.61, 1.0))
	button.add_theme_stylebox_override("normal", _round_style(normal_color, Color(0.95, 0.76, 0.3, 1.0), 1.0, 5.0, scale))
	button.add_theme_stylebox_override("hover", _round_style(normal_color.lightened(0.12), Color(1.0, 0.86, 0.4, 1.0), 2.0, 5.0, scale))
	button.add_theme_stylebox_override("disabled", _round_style(Color(0.17, 0.19, 0.2, 0.94), Color(0.36, 0.39, 0.4, 1.0), 1.0, 5.0, scale))
