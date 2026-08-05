class_name BottleSpawnArea
extends Control
## 主回收场景控制器。
##
## 维护五个场景的后台生产计时器和当前场景的可视节点。后台库存归 GameState
## 所有，当前场景最多只渲染 max_on_screen 个节点。切换场景时保留库存和序列号，
## 传送门状态机负责帮手离场/入场，帮手 AI 负责预约唯一目标并调用统一结算。

# 产物、帮手和过场节点使用不同 z_index，保证点击层级稳定。

const FALLBACK_TEXTURE: Texture2D = preload("res://assets/bottle.svg")
const BASE_LOGICAL_WIDTH: float = 393.0
const DROP_SIZE_PT: Vector2 = Vector2(34.0, 50.0)
const HELPER_SIZE_PT: Vector2 = Vector2(38.0, 48.0)
const SPAWN_MARGIN_PT: float = 18.0
const TOP_RESERVED_PT: float = 170.0
const GLOW_SCALE: float = 1.16
const HELPER_WANDER_MARGIN_PT: float = 28.0
const HELPER_WANDER_ARRIVE_PT: float = 8.0
const HELPER_SPAWN_COLUMNS: int = 5
const HELPER_ENTRY_COLUMNS: int = 4
const DROP_Z_BASE: int = 10
const HELPER_Z_INDEX: int = 2500
const PORTAL_Z_INDEX: int = 2600
const OVERLAY_Z_INDEX: int = 3000
const POPUP_Z_INDEX: int = 3100
const COLLECT_INPUT_DEDUP_MS: int = 90
const PORTAL_SIZE_PT: Vector2 = Vector2(38.0, 76.0)
const TRANSITION_HELPER_SPEED_PT: float = 180.0
const TRANSITION_ARRIVE_PT: float = 8.0
const TRANSITION_EMPTY_DELAY: float = 0.35
const TRANSITION_IDLE: String = "idle"
const TRANSITION_EXITING: String = "exiting"
const TRANSITION_ENTERING: String = "entering"
const DROP_PLACEMENT_MODULUS: int = 2147483647

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _scene_spawn_timers: Dictionary = {}
var _background: TextureRect
var _empty_label: Label
var _inventory_panel: PanelContainer
var _inventory_label: Label
var _transition_state: String = TRANSITION_IDLE
var _transition_target_scene_id: String = ""
var _transition_direction: int = 1
var _transition_portal: Control
var _transition_timer: float = 0.0
var _drop_input_enabled: bool = true
var _last_collect_input_msec: int = -COLLECT_INPUT_DEDUP_MS
var _defense_mode_active: bool = false


func _ready() -> void:
	## 创建背景、库存计数器并订阅场景、产物和帮手事件。
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_rng.randomize()
	_build_background()
	_build_empty_label()
	_build_inventory_counter()
	_apply_scene()
	EventBus.drop_collected.connect(_on_drop_collected)
	EventBus.scene_changed.connect(_on_scene_changed)
	EventBus.scene_inventory_changed.connect(_on_scene_inventory_changed)
	EventBus.scene_switch_requested.connect(_on_scene_switch_requested)
	EventBus.scene_unlocked.connect(_on_scene_unlocked)
	EventBus.unlocked_drops_changed.connect(_on_unlocked_drops_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	EventBus.helper_purchased.connect(_on_helper_purchased)
	EventBus.helper_active_changed.connect(_on_helper_active_changed)
	_reset_all_scene_spawn_timers(0.1)
	set_process(true)


func _process(delta: float) -> void:
	## 普通状态推进后台生产、当前场景同步和帮手 AI；过场时只推进状态机。
	_update_scene_production(delta)
	if _defense_mode_active:
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _transition_state != TRANSITION_IDLE:
		_update_scene_transition(delta)
		return
	_update_helpers(delta)


func set_defense_mode_active(active: bool) -> void:
	## 防守模式打开时暂停产物输入和帮手工作，返回时重新寻找目标。
	_defense_mode_active = active
	_drop_input_enabled = not active
	if active:
		_reset_helper_targets()


func _build_background() -> void:
	## 创建不接收点击的背景纹理，避免背景静态元素抢产物输入。
	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.anchor_right = 1.0
	_background.anchor_bottom = 1.0
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)


func _build_empty_label() -> void:
	## 候选产物池为空时显示当前场景的空状态提示。
	_empty_label = Label.new()
	_empty_label.text = "需要升级解锁这里的回收物"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.modulate = Color(1.0, 0.96, 0.78, 0.92)
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_label.visible = false
	_empty_label.z_index = OVERLAY_Z_INDEX
	add_child(_empty_label)


func _build_inventory_counter() -> void:
	## 创建右上角当前库存/经过升级后的场景容量显示。
	_inventory_panel = PanelContainer.new()
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory_panel.z_index = OVERLAY_Z_INDEX
	add_child(_inventory_panel)

	_inventory_label = Label.new()
	_inventory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inventory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_inventory_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory_panel.add_child(_inventory_label)


func _apply_scene() -> void:
	## 加载当前场景背景、清理旧画面节点并按后台库存恢复新节点。
	var scene: Dictionary = _current_scene()
	var texture: Texture2D = load(String(scene.get("background", ""))) as Texture2D
	if texture != null:
		_background.texture = texture
	_empty_label.text = "%s暂无可收集物\n先去升级解锁" % ConfigDB.get_scene_name(GameState.current_scene_id)
	_clear_active_drops()
	_render_current_scene_inventory()
	_refresh_helpers()
	_update_empty_state(_get_available_drops())
	_refresh_inventory_counter()


func _render_current_scene_inventory() -> void:
	## 只渲染场景 max_on_screen 预算内的库存，千级库存不会全部实例化。
	var visible_limit: int = _scene_visible_limit(GameState.current_scene_id)
	var inventory: Array = GameState.get_scene_drop_ids(GameState.current_scene_id)
	var serials: Array = GameState.get_scene_drop_serials(GameState.current_scene_id)
	var render_count: int = mini(visible_limit, inventory.size())
	for index in range(render_count):
		var drop: Dictionary = ConfigDB.get_drop(String(inventory[index]))
		if not drop.is_empty():
			_spawn_drop(drop, int(serials[index]), false)


func _spawn_drop(drop: Dictionary, serial: int, animate: bool = true) -> void:
	## 用稳定 serial 创建一项产物节点；serial 决定位置，切场景后仍可复现。
	if drop.is_empty():
		return

	var texture: Texture2D = load(String(drop.get("sprite", ""))) as Texture2D
	if texture == null:
		texture = FALLBACK_TEXTURE

	var glow: TextureRect = TextureRect.new()
	var item: TextureRect = TextureRect.new()
	var item_size: Vector2 = _drop_size()
	glow.texture = texture
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.size = item_size * GLOW_SCALE
	glow.pivot_offset = glow.size * 0.5
	var item_position: Vector2 = _drop_position_for_serial(String(drop.get("scene_id", "")), serial)
	glow.position = item_position - (glow.size - item_size) * 0.5
	glow.modulate = Color(0.62, 1.0, 0.35, 0.5)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_meta("is_drop_glow", true)
	add_child(glow)

	item.texture = texture
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item.size = item_size
	item.pivot_offset = item_size * 0.5
	item.position = item_position
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.set_meta("is_drop", true)
	item.set_meta("drop", drop)
	item.set_meta("drop_serial", serial)
	item.set_meta("glow", glow)
	add_child(item)
	_update_drop_layer(item, glow)

	if animate:
		item.modulate.a = 0.0
		item.scale = Vector2(0.85, 0.85)
		glow.modulate.a = 0.0
		glow.scale = Vector2(0.85, 0.85)
		var tween: Tween = create_tween()
		tween.tween_property(item, "modulate:a", 1.0, 0.12)
		tween.parallel().tween_property(item, "scale", Vector2.ONE, 0.12)
		tween.parallel().tween_property(glow, "modulate:a", 0.5, 0.12)
		tween.parallel().tween_property(glow, "scale", Vector2.ONE, 0.12)
	else:
		item.modulate.a = 1.0
		item.scale = Vector2.ONE
		glow.modulate.a = 0.5
		glow.scale = Vector2.ONE


func _random_drop_position() -> Vector2:
	## 为新产物生成一次随机位置，避开顶部 HUD 和场景边缘。
	var scale: float = _ui_scale()
	var drop_size: Vector2 = _drop_size()
	var min_x: float = SPAWN_MARGIN_PT * scale
	var max_x: float = maxf(min_x, size.x - drop_size.x - SPAWN_MARGIN_PT * scale)
	var min_y: float = TOP_RESERVED_PT * scale
	var max_y: float = maxf(min_y, size.y - drop_size.y - SPAWN_MARGIN_PT * scale)
	return Vector2(_rng.randf_range(min_x, max_x), _rng.randf_range(min_y, max_y))


func _drop_position_for_serial(scene_id: String, serial: int) -> Vector2:
	## 将持久化序列号映射为稳定的伪随机位置，避免切场景时产物乱跳。
	if serial <= 0:
		return _random_drop_position()
	var placement: Vector2 = _drop_placement_for_serial(scene_id, serial)
	var scale: float = _ui_scale()
	var drop_size: Vector2 = _drop_size()
	var min_x: float = SPAWN_MARGIN_PT * scale
	var max_x: float = maxf(min_x, size.x - drop_size.x - SPAWN_MARGIN_PT * scale)
	var min_y: float = TOP_RESERVED_PT * scale
	var max_y: float = maxf(min_y, size.y - drop_size.y - SPAWN_MARGIN_PT * scale)
	return Vector2(lerpf(min_x, max_x, placement.x), lerpf(min_y, max_y, placement.y))


func _drop_placement_for_serial(scene_id: String, serial: int) -> Vector2:
	## 混合场景与序列号生成种子，避免连续产物形成斜线或规则阵列。
	var scene_seed: int = 0
	for index in range(scene_id.length()):
		scene_seed = int(posmod(scene_seed * 131 + scene_id.unicode_at(index), DROP_PLACEMENT_MODULUS))
	var placement_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	placement_rng.seed = int(posmod(
		scene_seed * 104729 + serial * 1000003 + 97,
		DROP_PLACEMENT_MODULUS
	))
	return Vector2(placement_rng.randf(), placement_rng.randf())


func _gui_input(event: InputEvent) -> void:
	## 处理鼠标/触摸点击，并通过时间去重防止一次输入收集多个产物。
	var pointer_position: Vector2
	var pressed: bool = false
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		pressed = mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_LEFT
		pointer_position = mouse_button.position
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		pressed = touch.pressed
		pointer_position = touch.position
	else:
		return
	if not pressed or not _drop_input_enabled or _transition_state != TRANSITION_IDLE:
		return

	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_collect_input_msec < COLLECT_INPUT_DEDUP_MS:
		accept_event()
		return
	var item: TextureRect = _top_drop_at_position(pointer_position)
	if item == null:
		return
	_last_collect_input_msec = now_msec
	_collect_drop_item(item)
	accept_event()


func _top_drop_at_position(pointer_position: Vector2) -> TextureRect:
	## 产物重叠时按 z_index、serial 和节点顺序只选最上层一个。
	var top_item: TextureRect = null
	var top_z_index: int = -1
	var top_child_index: int = -1
	for child in get_children():
		var item: TextureRect = child as TextureRect
		if item == null or item.is_queued_for_deletion():
			continue
		if not bool(item.get_meta("is_drop", false)) or bool(item.get_meta("collected", false)):
			continue
		if not Rect2(item.position, item.size).has_point(pointer_position):
			continue
		var child_index: int = item.get_index()
		if item.z_index > top_z_index or (item.z_index == top_z_index and child_index > top_child_index):
			top_item = item
			top_z_index = item.z_index
			top_child_index = child_index
	return top_item


func _update_drop_layer(item: TextureRect, glow: TextureRect) -> void:
	## 根据产物位置和唯一层级更新 z_index 与选中光晕。
	var logical_y: float = item.position.y / _ui_scale()
	item.z_index = DROP_Z_BASE + clampi(int(round(logical_y * 2.0)), 0, 2000)
	if is_instance_valid(glow):
		glow.z_index = item.z_index - 1


func _collect_drop_item(item: TextureRect) -> bool:
	## 先按 serial 从 GameState 移除实例，再调用 ProductionSystem，确保只结算一次。
	if item == null or not is_instance_valid(item):
		return false
	if bool(item.get_meta("collected", false)):
		return false

	var drop: Dictionary = item.get_meta("drop", {})
	var scene_id: String = String(drop.get("scene_id", GameState.current_scene_id))
	var drop_id: String = String(drop.get("id", ""))
	var serial: int = int(item.get_meta("drop_serial", 0))
	if not GameState.consume_scene_drop_instance(scene_id, serial, drop_id):
		return false
	item.set_meta("collected", true)
	var system: ProductionSystem = get_tree().root.get_node_or_null("Main/Systems/ProductionSystem") as ProductionSystem
	if system != null:
		system.collect_drop(drop, item.global_position + item.size * 0.5)
	_despawn_drop(item)
	_sync_current_scene_visible_drops()
	return true


func _despawn_drop(item: TextureRect) -> void:
	## 播放收集动画后释放画面节点；后台库存已在收集前完成扣除。
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow: TextureRect = item.get_meta("glow") as TextureRect if item.has_meta("glow") else null
	var tween: Tween = create_tween()
	tween.tween_property(item, "scale", Vector2(0.45, 0.45), 0.16)
	tween.parallel().tween_property(item, "modulate:a", 0.0, 0.16)
	if is_instance_valid(glow):
		tween.parallel().tween_property(glow, "scale", Vector2(0.45, 0.45), 0.16)
		tween.parallel().tween_property(glow, "modulate:a", 0.0, 0.16)
	var instance_ids: Array[int] = [int(item.get_instance_id())]
	if is_instance_valid(glow):
		instance_ids.append(int(glow.get_instance_id()))
	tween.finished.connect(_free_controls_by_instance_id.bind(instance_ids))


func _clear_active_drops() -> void:
	## 仅清理当前画面节点，不清空任何场景后台库存。
	for child in get_children():
		var control: Control = child as Control
		if control == null:
			continue
		if bool(control.get_meta("is_drop", false)) or bool(control.get_meta("is_drop_glow", false)):
			control.queue_free()
	_reset_helper_targets()


func _sync_current_scene_visible_drops() -> void:
	## 在库存变化后补齐或移除画面节点，使渲染数量跟随后台库存。
	if _transition_state != TRANSITION_IDLE:
		return
	var visible_limit: int = _scene_visible_limit(GameState.current_scene_id)
	var visible_serials: Dictionary = {}
	for child in get_children():
		var item: TextureRect = child as TextureRect
		if item == null or item.is_queued_for_deletion():
			continue
		if not bool(item.get_meta("is_drop", false)) or bool(item.get_meta("collected", false)):
			continue
		visible_serials[int(item.get_meta("drop_serial", 0))] = true

	var inventory: Array = GameState.get_scene_drop_ids(GameState.current_scene_id)
	var serials: Array = GameState.get_scene_drop_serials(GameState.current_scene_id)
	var target_count: int = mini(visible_limit, inventory.size())
	for index in range(target_count):
		var serial: int = int(serials[index])
		if visible_serials.has(serial):
			continue
		var drop: Dictionary = ConfigDB.get_drop(String(inventory[index]))
		if not drop.is_empty():
			_spawn_drop(drop, serial)


func _update_scene_production(delta: float) -> void:
	## 为所有已解锁场景独立推进计时器，离开当前场景也不会停止生产。
	for scene in ConfigDB.get_scenes():
		var scene_id: String = String(scene.get("id", ""))
		if scene_id.is_empty() or not GameState.is_scene_unlocked(scene_id):
			continue
		var timer: float = float(_scene_spawn_timers.get(scene_id, 0.1)) - delta
		if timer > 0.0:
			_scene_spawn_timers[scene_id] = timer
			continue

		var drops: Array = _get_available_drops_for_scene(scene_id)
		if scene_id == GameState.current_scene_id:
			_update_empty_state(drops)
		if not drops.is_empty() and GameState.get_scene_drop_count(scene_id) < GameState.get_scene_capacity(scene_id):
			var drop: Dictionary = _pick_weighted_drop(drops)
			if GameState.add_scene_drop(scene_id, String(drop.get("id", ""))):
				if scene_id == GameState.current_scene_id and _transition_state == TRANSITION_IDLE:
					_sync_current_scene_visible_drops()
		_reset_scene_spawn_timer(scene_id, 0.8 if drops.is_empty() else -1.0)


func _reset_scene_spawn_timer(scene_id: String, first_delay: float = -1.0) -> void:
	## 重置单场景计时器；生成倍率在下一次计时检查时读取。
	if first_delay >= 0.0:
		_scene_spawn_timers[scene_id] = first_delay
		return
	var scene: Dictionary = ConfigDB.get_scene(scene_id)
	if scene.is_empty():
		return
	var interval_multiplier: float = GameState.get_global_spawn_interval_multiplier()
	_scene_spawn_timers[scene_id] = _rng.randf_range(
		float(scene.get("spawn_interval_min", 0.65)) * interval_multiplier,
		float(scene.get("spawn_interval_max", 1.25)) * interval_multiplier
	)


func _reset_all_scene_spawn_timers(first_delay: float = -1.0) -> void:
	## 为全部已解锁场景建立独立计时器。
	for scene in ConfigDB.get_scenes():
		var scene_id: String = String(scene.get("id", ""))
		if not scene_id.is_empty() and GameState.is_scene_unlocked(scene_id):
			_reset_scene_spawn_timer(scene_id, first_delay)


func _on_drop_collected(drop_name: String, amount: int, cash_amount: float, screen_pos: Vector2) -> void:
	## 只处理收集后的飘字，资源已经由 ProductionSystem/GameState 结算。
	if screen_pos == Vector2.ZERO:
		return

	var label: Label = Label.new()
	var scale: float = _ui_scale()
	label.text = "+%d %s  +%s 元" % [amount, drop_name, BigNumber.format(cash_amount)]
	label.add_theme_font_size_override("font_size", int(20.0 * scale))
	label.modulate = Color(0.1, 0.55, 0.28, 1.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = POPUP_Z_INDEX
	add_child(label)
	label.global_position = screen_pos - Vector2(92.0, 38.0) * scale

	var tween: Tween = create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector2(0.0, -42.0) * scale, 0.48)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.48)
	tween.finished.connect(func(): _free_control(label))


func _on_scene_switch_requested(offset: int) -> void:
	## 校验目标场景后启动传送门过场；过场中重复请求直接忽略。
	if _transition_state != TRANSITION_IDLE or offset == 0:
		return
	var target_scene_id: String = ConfigDB.get_scene_id_at_offset(GameState.current_scene_id, offset)
	if target_scene_id.is_empty() or not GameState.is_scene_unlocked(target_scene_id):
		return

	_refresh_helpers()
	_transition_target_scene_id = target_scene_id
	_transition_direction = -1 if offset < 0 else 1
	_transition_state = TRANSITION_EXITING
	_transition_timer = TRANSITION_EMPTY_DELAY
	_reset_helper_targets()
	_set_active_drops_input(false)
	_create_transition_portal(_transition_direction > 0)
	for helper in _helper_nodes():
		helper.set_meta("transition_hidden", false)
		helper.visible = true
		helper.modulate.a = 1.0
		helper.scale = Vector2.ONE
	EventBus.scene_transition_started.emit()


func _update_scene_transition(delta: float) -> void:
	## 根据 EXITING/ENTERING 状态推进帮手传送，完成后才切换场景。
	match _transition_state:
		TRANSITION_EXITING:
			_update_helpers_exiting(delta)
		TRANSITION_ENTERING:
			_update_helpers_entering(delta)


func _update_helpers_exiting(delta: float) -> void:
	## 将全部上阵帮手移动到当前场景对应方向的传送门。
	var helpers: Array = _helper_nodes()
	if helpers.is_empty():
		_transition_timer -= delta
		if _transition_timer <= 0.0:
			_switch_to_transition_target()
		return

	var portal_center: Vector2 = _transition_portal_center()
	var remaining: int = 0
	for helper in helpers:
		if bool(helper.get_meta("transition_hidden", false)):
			continue
		var row: Dictionary = helper.get_meta("config", {})
		var speed: float = maxf(TRANSITION_HELPER_SPEED_PT, float(row.get("speed", 80.0)) * 1.35)
		_move_helper_during_transition(helper, portal_center, speed, delta)
		var distance: float = _helper_distance_to(helper, portal_center)
		helper.scale = Vector2.ONE * clampf(distance / (48.0 * _ui_scale()), 0.45, 1.0)
		if distance <= TRANSITION_ARRIVE_PT * _ui_scale():
			helper.visible = false
			helper.scale = Vector2.ONE
			helper.set_meta("transition_hidden", true)
		else:
			remaining += 1

	if remaining == 0:
		_switch_to_transition_target()


func _switch_to_transition_target() -> void:
	## 所有帮手离场后切换背景和库存画面，并创建另一侧入口传送门。
	if not GameState.set_current_scene_id(_transition_target_scene_id):
		_finish_scene_transition()
		return

	_transition_state = TRANSITION_ENTERING
	_transition_timer = TRANSITION_EMPTY_DELAY
	_create_transition_portal(_transition_direction < 0)
	var portal_center: Vector2 = _transition_portal_center()
	var helpers: Array = _helper_nodes()
	for index in range(helpers.size()):
		var helper: TextureRect = helpers[index] as TextureRect
		helper.position = portal_center - helper.size * 0.5
		helper.visible = false
		helper.modulate.a = 1.0
		helper.scale = Vector2(0.55, 0.55)
		helper.set_meta("transition_hidden", false)
		helper.set_meta("transition_entered", false)
		helper.set_meta("transition_delay", float(index) * 0.12)
		helper.set_meta("transition_entry_target", _helper_transition_entry_position(index, helpers.size()))


func _update_helpers_entering(delta: float) -> void:
	## 让帮手依次从新场景传送门进入，全部到位后恢复自动拾取。
	var helpers: Array = _helper_nodes()
	if helpers.is_empty():
		_transition_timer -= delta
		if _transition_timer <= 0.0:
			_finish_scene_transition()
		return

	var remaining: int = 0
	for helper in helpers:
		if bool(helper.get_meta("transition_entered", false)):
			continue
		remaining += 1
		var delay: float = maxf(0.0, float(helper.get_meta("transition_delay", 0.0)) - delta)
		helper.set_meta("transition_delay", delay)
		if delay > 0.0:
			continue
		if not helper.visible:
			helper.visible = true
		var target: Vector2 = helper.get_meta("transition_entry_target", helper.position)
		var target_center: Vector2 = target + helper.size * 0.5
		var row: Dictionary = helper.get_meta("config", {})
		var speed: float = maxf(TRANSITION_HELPER_SPEED_PT, float(row.get("speed", 80.0)) * 1.35)
		_move_helper_during_transition(helper, target_center, speed, delta)
		var distance: float = _helper_distance_to(helper, target_center)
		helper.scale = Vector2.ONE * clampf(1.0 - distance / (180.0 * _ui_scale()), 0.55, 1.0)
		if distance <= TRANSITION_ARRIVE_PT * _ui_scale():
			helper.position = target
			helper.scale = Vector2.ONE
			helper.set_meta("transition_entered", true)
			helper.set_meta("target", null)
			helper.set_meta("wander_target", _random_helper_center_position())
			remaining -= 1

	if remaining == 0:
		_finish_scene_transition()


func _finish_scene_transition() -> void:
	## 关闭传送门、恢复输入和生产，并广播过场结束事件。
	if is_instance_valid(_transition_portal):
		_transition_portal.queue_free()
	_transition_portal = null
	_transition_state = TRANSITION_IDLE
	_transition_target_scene_id = ""
	_transition_direction = 1
	_transition_timer = 0.0
	for helper in _helper_nodes():
		helper.visible = true
		helper.modulate.a = 1.0
		helper.scale = Vector2.ONE
		helper.set_meta("transition_hidden", false)
		helper.set_meta("transition_entered", false)
	_clear_active_drops()
	_render_current_scene_inventory()
	_reset_helper_targets()
	_set_active_drops_input(true)
	EventBus.scene_transition_finished.emit(GameState.current_scene_id)


func _create_transition_portal(on_right: bool) -> void:
	## 创建可视传送门；传送门只提供反馈，不参与产物点击。
	if is_instance_valid(_transition_portal):
		_transition_portal.queue_free()
	var scale: float = _ui_scale()
	var portal: Control = Control.new()
	portal.size = PORTAL_SIZE_PT * scale
	portal.pivot_offset = portal.size * 0.5
	portal.position = _transition_portal_position(on_right, portal.size)
	portal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portal.z_index = PORTAL_Z_INDEX
	portal.set_meta("is_transition_portal", true)
	add_child(portal)

	var glow: Panel = Panel.new()
	glow.position = -Vector2(7.0, 7.0) * scale
	glow.size = portal.size + Vector2(14.0, 14.0) * scale
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.add_theme_stylebox_override("panel", _portal_style(Color(0.25, 0.85, 0.8, 0.24), Color(0.95, 0.55, 0.96, 0.72), 3.0, scale))
	portal.add_child(glow)

	var core: Panel = Panel.new()
	core.size = portal.size
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	core.add_theme_stylebox_override("panel", _portal_style(Color(0.13, 0.12, 0.24, 0.94), Color(0.36, 0.94, 0.86, 1.0), 3.0, scale))
	portal.add_child(core)

	_transition_portal = portal
	var tween: Tween = create_tween()
	tween.bind_node(portal)
	tween.set_loops()
	tween.tween_property(portal, "scale", Vector2(1.08, 0.94), 0.42).set_trans(Tween.TRANS_SINE)
	tween.tween_property(portal, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_SINE)


func _transition_portal_position(on_right: bool, portal_size: Vector2) -> Vector2:
	## 根据切换方向计算传送门的屏幕边缘位置。
	var scale: float = _ui_scale()
	var center_y: float = clampf(size.y * 0.55, TOP_RESERVED_PT * scale + portal_size.y * 0.5, size.y - portal_size.y * 0.5 - 24.0 * scale)
	var x: float = size.x - portal_size.x * 0.65 if on_right else -portal_size.x * 0.35
	return Vector2(x, center_y - portal_size.y * 0.5)


func _transition_portal_center() -> Vector2:
	## 返回当前传送门中心，过场移动统一使用此坐标。
	if not is_instance_valid(_transition_portal):
		return Vector2(size.x * 0.5, size.y * 0.5)
	return _transition_portal.position + _transition_portal.size * 0.5


func _move_helper_during_transition(helper: TextureRect, target_center: Vector2, speed_pt: float, delta: float) -> void:
	## 过场移动允许帮手抵达屏幕边缘，不使用普通工作区域边界。
	var helper_center: Vector2 = helper.position + helper.size * 0.5
	var offset: Vector2 = target_center - helper_center
	var distance: float = offset.length()
	if distance <= 0.1:
		return
	var step: float = minf(distance, speed_pt * _ui_scale() * delta)
	helper.position = helper_center + offset.normalized() * step - helper.size * 0.5
	helper.flip_h = offset.x < 0.0


func _helper_transition_entry_position(index: int, helper_count: int) -> Vector2:
	## 为入场帮手生成错开的初始位置，避免多个角色重叠成一个点。
	var scale: float = _ui_scale()
	var helper_size: Vector2 = _helper_size()
	var center_y: float = size.y * 0.55
	var column: int = index % HELPER_ENTRY_COLUMNS
	var row: int = floori(float(index) / float(HELPER_ENTRY_COLUMNS))
	var row_count: int = ceili(float(helper_count) / float(HELPER_ENTRY_COLUMNS))
	var offset_y: float = (float(row) - float(row_count - 1) * 0.5) * 58.0 * scale
	var distance_from_edge: float = (72.0 + float(column) * 56.0) * scale
	var position_x: float = distance_from_edge
	if _transition_direction < 0:
		position_x = size.x - helper_size.x - distance_from_edge
	var position: Vector2 = Vector2(position_x, center_y + offset_y - helper_size.y * 0.5)
	return _clamp_helper_position(position)


func _helper_nodes() -> Array:
	## 收集当前场景全部已上阵帮手节点。
	var out: Array = []
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper != null and not helper.is_queued_for_deletion() and bool(helper.get_meta("is_helper", false)):
			out.append(helper)
	return out


func _set_active_drops_input(enabled: bool) -> void:
	## 过场、防守或弹窗状态通过此入口统一锁定产物输入。
	_drop_input_enabled = enabled
	for child in get_children():
		var item: TextureRect = child as TextureRect
		if item != null and bool(item.get_meta("is_drop", false)):
			item.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _portal_style(bg: Color, border: Color, border_width: float, scale: float) -> StyleBoxFlat:
	## 生成传送门发光边框样式。
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(int(border_width * scale))
	style.set_corner_radius_all(int(18.0 * scale))
	return style


func _on_scene_changed(_scene_id: String) -> void:
	## GameState 场景变化的兜底刷新入口，正常切换由过场状态机驱动。
	_apply_scene()


func _on_scene_inventory_changed(scene_id: String) -> void:
	## 当前场景库存变化时同步可见节点和右上角计数器。
	if scene_id == GameState.current_scene_id:
		_refresh_inventory_counter()


func _on_unlocked_drops_changed() -> void:
	## 产物解锁后刷新空状态、候选池和当前画面。
	_update_empty_state(_get_available_drops())
	_reset_all_scene_spawn_timers(0.1)


func _on_scene_unlocked(scene_id: String) -> void:
	## 新场景解锁后创建其后台计时器，不改变玩家当前场景。
	_reset_scene_spawn_timer(scene_id, 0.1)


func _on_upgrade_purchased(upgrade_id, _new_level: int) -> void:
	## 通用刷新升级购买后重置相关计时器，其他升级无需重建节点。
	var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
	if String(row.get("type", "")) == "global_spawn":
		_reset_all_scene_spawn_timers(0.05)
	_refresh_inventory_counter()


func _on_helper_purchased(_helper_id: String) -> void:
	## 新帮手购买默认上阵，立即加入当前场景并开始寻找目标。
	_refresh_helpers()


func _on_helper_active_changed(_helper_id: String, _active: bool) -> void:
	## 上下阵变化后重新生成帮手节点，预约目标由刷新过程重新建立。
	_refresh_helpers()
	_relayout_helpers()


func _refresh_helpers() -> void:
	## 清理已有帮手节点，并按 active_helpers 重新生成。
	var wanted_ids: Dictionary = {}
	var spawn_index: int = 0
	for row in ConfigDB.get_helpers():
		var helper_id: String = String(row.get("id", ""))
		if helper_id.is_empty() or not GameState.is_helper_active(helper_id):
			continue
		if not _helper_can_work_here(row):
			continue
		wanted_ids[helper_id] = true
		if _get_helper_node(helper_id) == null:
			_spawn_helper(row, spawn_index)
		spawn_index += 1

	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper == null or not bool(helper.get_meta("is_helper", false)):
			continue
		var helper_id: String = String(helper.get_meta("helper_id", ""))
		if not wanted_ids.has(helper_id):
			_release_helper_target(helper)
			helper.visible = false
			helper.queue_free()


func _spawn_helper(row: Dictionary, spawn_index: int) -> void:
	## 创建帮手运行节点并写入目标、巡游点和预约所需的元数据。
	var helper: TextureRect = TextureRect.new()
	var texture: Texture2D = load(String(row.get("sprite", ""))) as Texture2D
	if texture != null:
		helper.texture = texture
	else:
		helper.texture = FALLBACK_TEXTURE
	helper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	helper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	helper.size = _helper_size()
	helper.pivot_offset = helper.size * 0.5
	helper.position = _helper_spawn_position(spawn_index)
	helper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	helper.z_index = HELPER_Z_INDEX
	helper.set_meta("is_helper", true)
	helper.set_meta("helper_id", String(row.get("id", "")))
	helper.set_meta("config", row)
	helper.set_meta("target", null)
	helper.set_meta("wander_target", _random_helper_center_position())
	helper.set_meta("cooldown_remaining", 0.0)
	add_child(helper)

	helper.modulate.a = 0.0
	helper.scale = Vector2(0.86, 0.86)
	var tween: Tween = create_tween()
	tween.tween_property(helper, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(helper, "scale", Vector2.ONE, 0.18)


func _update_helpers(delta: float) -> void:
	## 遍历帮手，逐个推进寻找、移动、收集或巡游状态。
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper == null or helper.is_queued_for_deletion() or not bool(helper.get_meta("is_helper", false)):
			continue
		_update_helper(helper, delta)


func _update_helper(helper: TextureRect, delta: float) -> void:
	## 单个帮手循环：验证目标、预约、移动、冷却并调用统一收集。
	var row: Dictionary = helper.get_meta("config", {})
	if row.is_empty() or not _helper_can_work_here(row):
		_release_helper_target(helper)
		return

	var cooldown_remaining: float = maxf(0.0, float(helper.get_meta("cooldown_remaining", 0.0)) - delta)
	helper.set_meta("cooldown_remaining", cooldown_remaining)

	var target: TextureRect = helper.get_meta("target") as TextureRect if helper.has_meta("target") else null
	if not _is_valid_helper_target(target, row, helper):
		_release_helper_target(helper)
		target = _find_helper_target(helper, row)
		if target != null:
			_reserve_helper_target(helper, target)

	if target == null:
		_update_helper_wander(helper, row, delta)
		return

	var target_center: Vector2 = target.position + target.size * 0.5
	_move_helper_toward(
		helper,
		target_center,
		float(row.get("speed", 80.0)) * GameState.get_helper_speed_multiplier(),
		delta
	)
	if _helper_distance_to(helper, target_center) > float(row.get("collect_radius", 24.0)) * _ui_scale():
		return
	if cooldown_remaining > 0.0:
		return

	if _collect_drop_item(target):
		_release_helper_target(helper)
		helper.set_meta(
			"cooldown_remaining",
			float(row.get("collect_cooldown", 1.0)) * GameState.get_helper_cooldown_multiplier()
		)
	else:
		_release_helper_target(helper)


func _update_helper_wander(helper: TextureRect, row: Dictionary, delta: float) -> void:
	## 没有目标时让帮手以较低速度在工作区域内巡游。
	if not helper.has_meta("wander_target"):
		helper.set_meta("wander_target", _random_helper_center_position())
	var wander_target: Vector2 = helper.get_meta("wander_target")
	if _helper_distance_to(helper, wander_target) <= HELPER_WANDER_ARRIVE_PT * _ui_scale():
		wander_target = _random_helper_center_position()
		helper.set_meta("wander_target", wander_target)
	_move_helper_toward(
		helper,
		wander_target,
		float(row.get("speed", 80.0)) * GameState.get_helper_speed_multiplier() * 0.45,
		delta
	)


func _find_helper_target(helper: TextureRect, row: Dictionary) -> TextureRect:
	## 按距离选择最近可用目标，并尊重 preferred_types 过滤。
	var preferred_types: Array = row.get("preferred_types", [])
	var best_target: TextureRect = null
	var best_distance: float = INF
	var helper_center: Vector2 = helper.position + helper.size * 0.5
	for child in get_children():
		var item: TextureRect = child as TextureRect
		if item == null or not _is_valid_helper_target(item, row, helper):
			continue
		var drop: Dictionary = item.get_meta("drop", {})
		var drop_type: String = String(drop.get("type", ""))
		if not preferred_types.is_empty() and not preferred_types.has(drop_type):
			continue
		var distance: float = helper_center.distance_to(item.position + item.size * 0.5)
		if distance < best_distance:
			best_distance = distance
			best_target = item
	return best_target


func _is_valid_helper_target(item: TextureRect, row: Dictionary, helper: TextureRect = null) -> bool:
	## 检查节点有效性、场景归属、产物类型和其他帮手预约状态。
	if item == null or not is_instance_valid(item):
		return false
	if item.is_queued_for_deletion():
		return false
	if not bool(item.get_meta("is_drop", false)) or bool(item.get_meta("collected", false)):
		return false
	var drop: Dictionary = item.get_meta("drop", {})
	if String(drop.get("scene_id", GameState.current_scene_id)) != GameState.current_scene_id:
		return false
	var preferred_types: Array = row.get("preferred_types", [])
	if not preferred_types.is_empty() and not preferred_types.has(String(drop.get("type", ""))):
		return false
	var reservation_owner: int = _drop_reservation_owner(item)
	return reservation_owner == 0 or (helper != null and reservation_owner == int(helper.get_instance_id()))


func _reserve_helper_target(helper: TextureRect, item: TextureRect) -> bool:
	## 用帮手实例 ID 预约产物，解决多个帮手抢同一目标的问题。
	var helper_instance_id: int = int(helper.get_instance_id())
	var reservation_owner: int = _drop_reservation_owner(item)
	if reservation_owner != 0 and reservation_owner != helper_instance_id:
		return false
	item.set_meta("reserved_helper_instance_id", helper_instance_id)
	helper.set_meta("target", item)
	return true


func _release_helper_target(helper: TextureRect) -> void:
	## 收集、失效、下阵或切场景时释放目标预约。
	var target: TextureRect = helper.get_meta("target") as TextureRect if helper.has_meta("target") else null
	if target != null and is_instance_valid(target):
		var helper_instance_id: int = int(helper.get_instance_id())
		if int(target.get_meta("reserved_helper_instance_id", 0)) == helper_instance_id:
			target.remove_meta("reserved_helper_instance_id")
	helper.set_meta("target", null)


func _drop_reservation_owner(item: TextureRect) -> int:
	## 清理已释放帮手留下的预约，返回当前有效预约者 ID。
	var owner_id: int = int(item.get_meta("reserved_helper_instance_id", 0))
	if owner_id <= 0:
		return 0
	var owner: Object = instance_from_id(owner_id)
	if owner == null or not is_instance_valid(owner) or (owner is Node and (owner as Node).is_queued_for_deletion()):
		item.remove_meta("reserved_helper_instance_id")
		return 0
	return owner_id


func _move_helper_toward(helper: TextureRect, target_center: Vector2, speed_pt: float, delta: float) -> void:
	## 使用速度、边界和水平朝向更新位置，不负责到达后的业务状态。
	var helper_center: Vector2 = helper.position + helper.size * 0.5
	var offset: Vector2 = target_center - helper_center
	var distance: float = offset.length()
	if distance <= 0.1:
		return
	var step: float = minf(distance, speed_pt * _ui_scale() * delta)
	var next_center: Vector2 = helper_center + offset.normalized() * step
	helper.position = _clamp_helper_position(next_center - helper.size * 0.5)
	helper.flip_h = offset.x < 0.0


func _helper_distance_to(helper: TextureRect, target_center: Vector2) -> float:
	## 返回帮手中心到目标中心的距离，收集半径判断使用此结果。
	return (helper.position + helper.size * 0.5).distance_to(target_center)


func _helper_can_work_here(row: Dictionary) -> bool:
	## 空 scenes 表示全场景工作，否则只允许配置场景。
	var scene_ids: Array = row.get("scenes", [])
	return scene_ids.is_empty() or scene_ids.has(GameState.current_scene_id)


func _get_helper_node(helper_id: String) -> TextureRect:
	## 按帮手 ID 查找当前场景运行节点。
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper != null and not helper.is_queued_for_deletion() and bool(helper.get_meta("is_helper", false)) and String(helper.get_meta("helper_id", "")) == helper_id:
			return helper
	return null


func _reset_helper_targets() -> void:
	## 场景变化或生产池更新后释放全部预约并生成新的巡游点。
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper != null and bool(helper.get_meta("is_helper", false)):
			_release_helper_target(helper)
			helper.set_meta("wander_target", _random_helper_center_position())


func _helper_spawn_position(spawn_index: int) -> Vector2:
	## 初次生成时按列布局帮手，随后由 AI 接管移动。
	var scale: float = _ui_scale()
	var column: int = spawn_index % HELPER_SPAWN_COLUMNS
	var row: int = floori(float(spawn_index) / float(HELPER_SPAWN_COLUMNS))
	var x: float = (SPAWN_MARGIN_PT + 18.0 + float(column) * 66.0) * scale
	var y: float = (TOP_RESERVED_PT + 22.0 + float(row) * 58.0) * scale
	return _clamp_helper_position(Vector2(x, y))


func _random_helper_center_position() -> Vector2:
	## 在避开 HUD 和边缘的工作区域内随机生成巡游目标。
	var scale: float = _ui_scale()
	var helper_size: Vector2 = _helper_size()
	var min_x: float = HELPER_WANDER_MARGIN_PT * scale + helper_size.x * 0.5
	var max_x: float = maxf(min_x, size.x - HELPER_WANDER_MARGIN_PT * scale - helper_size.x * 0.5)
	var min_y: float = TOP_RESERVED_PT * scale + helper_size.y * 0.5
	var max_y: float = maxf(min_y, size.y - HELPER_WANDER_MARGIN_PT * scale - helper_size.y * 0.5)
	return Vector2(_rng.randf_range(min_x, max_x), _rng.randf_range(min_y, max_y))


func _clamp_helper_position(position: Vector2) -> Vector2:
	## 将帮手限制在可工作区域，避免遮挡顶部状态栏或离开场景。
	var scale: float = _ui_scale()
	var helper_size: Vector2 = _helper_size()
	var min_x: float = HELPER_WANDER_MARGIN_PT * scale
	var max_x: float = maxf(min_x, size.x - helper_size.x - HELPER_WANDER_MARGIN_PT * scale)
	var min_y: float = TOP_RESERVED_PT * scale
	var max_y: float = maxf(min_y, size.y - helper_size.y - HELPER_WANDER_MARGIN_PT * scale)
	return Vector2(clampf(position.x, min_x, max_x), clampf(position.y, min_y, max_y))


func _current_scene() -> Dictionary:
	## 获取当前场景配置，异常 ID 时回退默认场景。
	var scene: Dictionary = ConfigDB.get_scene(GameState.current_scene_id)
	if scene.is_empty():
		scene = ConfigDB.get_scene(ConfigDB.get_default_scene_id())
	return scene


func _scene_visible_limit(scene_id: String) -> int:
	## 返回画面节点预算，不等同于后台库存上限。
	return maxi(0, int(ConfigDB.get_scene(scene_id).get("max_on_screen", 0)))


func _get_available_drops() -> Array:
	## 获取当前场景已经解锁的候选产物。
	return _get_available_drops_for_scene(GameState.current_scene_id)


func _get_available_drops_for_scene(scene_id: String) -> Array:
	## 按场景归属和 GameState 解锁状态过滤候选产物。
	var out: Array = []
	for drop in ConfigDB.get_scene_drops(scene_id):
		if GameState.is_drop_unlocked(String(drop.get("id", ""))):
			out.append(drop)
	return out


func _pick_weighted_drop(drops: Array) -> Dictionary:
	## 根据 weight 做一次加权随机选择；零权重产物不获得概率。
	if drops.is_empty():
		return {}
	var total_weight: float = 0.0
	for drop in drops:
		total_weight += maxf(0.0, float(drop.get("weight", 0.0)))
	if total_weight <= 0.0:
		return drops[_rng.randi_range(0, drops.size() - 1)]
	var roll: float = _rng.randf_range(0.0, total_weight)
	var cursor: float = 0.0
	for drop in drops:
		cursor += maxf(0.0, float(drop.get("weight", 0.0)))
		if roll <= cursor:
			return drop
	return drops.back()


func _update_empty_state(drops: Array) -> void:
	## 候选池为空时显示提示，否则隐藏空状态标签。
	if _empty_label != null:
		_empty_label.visible = drops.is_empty()


func _refresh_inventory_counter() -> void:
	## 显示后台库存数量/经过升级和天赋后的容量上限。
	if _inventory_label == null:
		return
	_inventory_label.text = "产物 %d/%d" % [
		GameState.get_scene_drop_count(GameState.current_scene_id),
		GameState.get_scene_capacity(GameState.current_scene_id),
	]


func apply_layout(viewport_size: Vector2) -> void:
	## 布局背景、计数器、产物和帮手，并在尺寸变化后保持稳定位置。
	var scale: float = _ui_scale_from_viewport(viewport_size)
	if _background != null:
		_background.size = size
	if _empty_label != null:
		_empty_label.size = Vector2(minf(size.x * 0.76, 310.0 * scale), 86.0 * scale)
		_empty_label.position = Vector2((size.x - _empty_label.size.x) * 0.5, maxf(150.0 * scale, size.y * 0.42))
		_empty_label.add_theme_font_size_override("font_size", int(17.0 * scale))
	if _inventory_panel != null:
		_inventory_panel.size = Vector2(132.0 * scale, 34.0 * scale)
		_inventory_panel.position = Vector2(size.x - _inventory_panel.size.x - 12.0 * scale, 128.0 * scale)
		_inventory_panel.add_theme_stylebox_override("panel", _inventory_counter_style(scale))
	if _inventory_label != null:
		_inventory_label.add_theme_font_size_override("font_size", int(14.0 * scale))
		_inventory_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.72, 1.0))
	_relayout_drops()
	_relayout_helpers()


func _drop_size() -> Vector2:
	## 返回按当前缩放后的产物节点尺寸。
	return DROP_SIZE_PT * _ui_scale()


func _helper_size() -> Vector2:
	## 返回按当前缩放后的帮手节点尺寸。
	return HELPER_SIZE_PT * _ui_scale()


func _relayout_drops() -> void:
	## 根据每个产物保存的 serial 重新计算位置，不改变库存顺序。
	var drop_size: Vector2 = _drop_size()
	for child in get_children():
		var item: TextureRect = child as TextureRect
		if item == null or item.is_queued_for_deletion() or not bool(item.get_meta("is_drop", false)):
			continue
		if bool(item.get_meta("collected", false)):
			continue
		var glow: TextureRect = item.get_meta("glow") as TextureRect if item.has_meta("glow") else null
		item.size = drop_size
		item.pivot_offset = drop_size * 0.5
		var drop: Dictionary = item.get_meta("drop", {})
		var serial: int = int(item.get_meta("drop_serial", 0))
		item.position = _drop_position_for_serial(String(drop.get("scene_id", "")), serial)
		if is_instance_valid(glow):
			glow.size = drop_size * GLOW_SCALE
			glow.pivot_offset = glow.size * 0.5
			glow.position = item.position - (glow.size - item.size) * 0.5
			_update_drop_layer(item, glow)
		else:
			_update_drop_layer(item, null)


func _relayout_helpers() -> void:
	## 尺寸变化时保持帮手相对工作区域位置并重新限制边界。
	var helper_index: int = 0
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper == null or helper.is_queued_for_deletion() or not bool(helper.get_meta("is_helper", false)):
			continue
		helper.size = _helper_size()
		helper.pivot_offset = helper.size * 0.5
		helper.position = _helper_spawn_position(helper_index)
		helper_index += 1


func _ui_scale() -> float:
	## 使用当前视口宽度计算场景节点逻辑缩放。
	return _ui_scale_from_viewport(get_viewport_rect().size)


func _ui_scale_from_viewport(viewport_size: Vector2) -> float:
	## 纯函数版本的缩放计算，供布局入口使用。
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)


func _inventory_counter_style(scale: float) -> StyleBoxFlat:
	## 生成右上角库存计数器样式。
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.15, 0.17, 0.84)
	style.border_color = Color(0.94, 0.76, 0.32, 0.95)
	style.set_border_width_all(int(1.5 * scale))
	style.set_corner_radius_all(int(6.0 * scale))
	style.content_margin_left = 7.0 * scale
	style.content_margin_right = 7.0 * scale
	return style


func _free_control(control: Control) -> void:
	## 安全释放一个可能已经排队删除的 UI 节点。
	if is_instance_valid(control):
		control.queue_free()


func _free_controls_by_instance_id(instance_ids: Array[int]) -> void:
	## 按实例 ID 批量释放过场结束后残留的帮手节点。
	for instance_id in instance_ids:
		var control: Control = instance_from_id(instance_id) as Control
		if is_instance_valid(control):
			control.queue_free()
