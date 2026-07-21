class_name BottleSpawnArea
extends Control
## Central play field that spawns clickable collectables by current scene.

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


func _ready() -> void:
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
	_update_scene_production(delta)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if _transition_state != TRANSITION_IDLE:
		_update_scene_transition(delta)
		return
	_update_helpers(delta)


func _build_background() -> void:
	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.anchor_right = 1.0
	_background.anchor_bottom = 1.0
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)


func _build_empty_label() -> void:
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
	var visible_limit: int = _scene_visible_limit(GameState.current_scene_id)
	var rendered: int = 0
	for drop_id in GameState.get_scene_drop_ids(GameState.current_scene_id):
		if rendered >= visible_limit:
			break
		var drop: Dictionary = ConfigDB.get_drop(String(drop_id))
		if not drop.is_empty():
			_spawn_drop(drop, false)
			rendered += 1


func _spawn_drop(drop: Dictionary, animate: bool = true) -> void:
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
	glow.position = _random_drop_position()
	glow.modulate = Color(0.62, 1.0, 0.35, 0.5)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_meta("is_drop_glow", true)
	add_child(glow)

	item.texture = texture
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item.size = item_size
	item.pivot_offset = item_size * 0.5
	item.position = glow.position + (glow.size - item.size) * 0.5
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.set_meta("is_drop", true)
	item.set_meta("drop", drop)
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
	var scale: float = _ui_scale()
	var drop_size: Vector2 = _drop_size()
	var min_x: float = SPAWN_MARGIN_PT * scale
	var max_x: float = maxf(min_x, size.x - drop_size.x - SPAWN_MARGIN_PT * scale)
	var min_y: float = TOP_RESERVED_PT * scale
	var max_y: float = maxf(min_y, size.y - drop_size.y - SPAWN_MARGIN_PT * scale)
	return Vector2(_rng.randf_range(min_x, max_x), _rng.randf_range(min_y, max_y))


func _gui_input(event: InputEvent) -> void:
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
	var logical_y: float = item.position.y / _ui_scale()
	item.z_index = DROP_Z_BASE + clampi(int(round(logical_y * 2.0)), 0, 2000)
	if is_instance_valid(glow):
		glow.z_index = item.z_index - 1


func _collect_drop_item(item: TextureRect) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if bool(item.get_meta("collected", false)):
		return false

	var drop: Dictionary = item.get_meta("drop", {})
	var scene_id: String = String(drop.get("scene_id", GameState.current_scene_id))
	var drop_id: String = String(drop.get("id", ""))
	if not GameState.consume_scene_drop(scene_id, drop_id):
		return false
	item.set_meta("collected", true)
	var system: ProductionSystem = get_tree().root.get_node_or_null("Main/Systems/ProductionSystem") as ProductionSystem
	if system != null:
		system.collect_drop(drop, item.global_position + item.size * 0.5)
	_despawn_drop(item)
	_sync_current_scene_visible_drops()
	return true


func _despawn_drop(item: TextureRect) -> void:
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow: TextureRect = item.get_meta("glow") as TextureRect if item.has_meta("glow") else null
	var tween: Tween = create_tween()
	tween.tween_property(item, "scale", Vector2(0.45, 0.45), 0.16)
	tween.parallel().tween_property(item, "modulate:a", 0.0, 0.16)
	if is_instance_valid(glow):
		tween.parallel().tween_property(glow, "scale", Vector2(0.45, 0.45), 0.16)
		tween.parallel().tween_property(glow, "modulate:a", 0.0, 0.16)
	tween.finished.connect(func(): _free_control(item))
	tween.finished.connect(func(): _free_control(glow))


func _clear_active_drops() -> void:
	for child in get_children():
		var control: Control = child as Control
		if control == null:
			continue
		if bool(control.get_meta("is_drop", false)) or bool(control.get_meta("is_drop_glow", false)):
			control.queue_free()
	_reset_helper_targets()


func _sync_current_scene_visible_drops() -> void:
	if _transition_state != TRANSITION_IDLE:
		return
	var visible_limit: int = _scene_visible_limit(GameState.current_scene_id)
	var visible_counts: Dictionary = {}
	var visible_total: int = 0
	for child in get_children():
		var item: TextureRect = child as TextureRect
		if item == null or item.is_queued_for_deletion():
			continue
		if not bool(item.get_meta("is_drop", false)) or bool(item.get_meta("collected", false)):
			continue
		var drop: Dictionary = item.get_meta("drop", {})
		var drop_id: String = String(drop.get("id", ""))
		visible_counts[drop_id] = int(visible_counts.get(drop_id, 0)) + 1
		visible_total += 1
	if visible_total >= visible_limit:
		return

	var unmatched_visible: Dictionary = visible_counts.duplicate()
	var slots_remaining: int = visible_limit - visible_total
	for drop_id_variant in GameState.get_scene_drop_ids(GameState.current_scene_id):
		var drop_id: String = String(drop_id_variant)
		var represented: int = int(unmatched_visible.get(drop_id, 0))
		if represented > 0:
			unmatched_visible[drop_id] = represented - 1
			continue
		var drop: Dictionary = ConfigDB.get_drop(drop_id)
		if not drop.is_empty():
			_spawn_drop(drop)
			slots_remaining -= 1
			if slots_remaining <= 0:
				break


func _update_scene_production(delta: float) -> void:
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
	for scene in ConfigDB.get_scenes():
		var scene_id: String = String(scene.get("id", ""))
		if not scene_id.is_empty() and GameState.is_scene_unlocked(scene_id):
			_reset_scene_spawn_timer(scene_id, first_delay)


func _on_drop_collected(drop_name: String, amount: int, cash_amount: float, screen_pos: Vector2) -> void:
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
	match _transition_state:
		TRANSITION_EXITING:
			_update_helpers_exiting(delta)
		TRANSITION_ENTERING:
			_update_helpers_entering(delta)


func _update_helpers_exiting(delta: float) -> void:
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
	var scale: float = _ui_scale()
	var center_y: float = clampf(size.y * 0.55, TOP_RESERVED_PT * scale + portal_size.y * 0.5, size.y - portal_size.y * 0.5 - 24.0 * scale)
	var x: float = size.x - portal_size.x * 0.65 if on_right else -portal_size.x * 0.35
	return Vector2(x, center_y - portal_size.y * 0.5)


func _transition_portal_center() -> Vector2:
	if not is_instance_valid(_transition_portal):
		return Vector2(size.x * 0.5, size.y * 0.5)
	return _transition_portal.position + _transition_portal.size * 0.5


func _move_helper_during_transition(helper: TextureRect, target_center: Vector2, speed_pt: float, delta: float) -> void:
	var helper_center: Vector2 = helper.position + helper.size * 0.5
	var offset: Vector2 = target_center - helper_center
	var distance: float = offset.length()
	if distance <= 0.1:
		return
	var step: float = minf(distance, speed_pt * _ui_scale() * delta)
	helper.position = helper_center + offset.normalized() * step - helper.size * 0.5
	helper.flip_h = offset.x < 0.0


func _helper_transition_entry_position(index: int, helper_count: int) -> Vector2:
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
	var out: Array = []
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper != null and not helper.is_queued_for_deletion() and bool(helper.get_meta("is_helper", false)):
			out.append(helper)
	return out


func _set_active_drops_input(enabled: bool) -> void:
	_drop_input_enabled = enabled
	for child in get_children():
		var item: TextureRect = child as TextureRect
		if item != null and bool(item.get_meta("is_drop", false)):
			item.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _portal_style(bg: Color, border: Color, border_width: float, scale: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(int(border_width * scale))
	style.set_corner_radius_all(int(18.0 * scale))
	return style


func _on_scene_changed(_scene_id: String) -> void:
	_apply_scene()


func _on_scene_inventory_changed(scene_id: String) -> void:
	if scene_id == GameState.current_scene_id:
		_refresh_inventory_counter()


func _on_unlocked_drops_changed() -> void:
	_update_empty_state(_get_available_drops())
	_reset_all_scene_spawn_timers(0.1)


func _on_scene_unlocked(scene_id: String) -> void:
	_reset_scene_spawn_timer(scene_id, 0.1)


func _on_upgrade_purchased(upgrade_id, _new_level: int) -> void:
	var row: Dictionary = ConfigDB.get_upgrade(upgrade_id)
	if String(row.get("type", "")) == "global_spawn":
		_reset_all_scene_spawn_timers(0.05)
	_refresh_inventory_counter()


func _on_helper_purchased(_helper_id: String) -> void:
	_refresh_helpers()


func _on_helper_active_changed(_helper_id: String, _active: bool) -> void:
	_refresh_helpers()
	_relayout_helpers()


func _refresh_helpers() -> void:
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
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper == null or helper.is_queued_for_deletion() or not bool(helper.get_meta("is_helper", false)):
			continue
		_update_helper(helper, delta)


func _update_helper(helper: TextureRect, delta: float) -> void:
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
	_move_helper_toward(helper, target_center, float(row.get("speed", 80.0)), delta)
	if _helper_distance_to(helper, target_center) > float(row.get("collect_radius", 24.0)) * _ui_scale():
		return
	if cooldown_remaining > 0.0:
		return

	if _collect_drop_item(target):
		_release_helper_target(helper)
		helper.set_meta("cooldown_remaining", float(row.get("collect_cooldown", 1.0)))
	else:
		_release_helper_target(helper)


func _update_helper_wander(helper: TextureRect, row: Dictionary, delta: float) -> void:
	if not helper.has_meta("wander_target"):
		helper.set_meta("wander_target", _random_helper_center_position())
	var wander_target: Vector2 = helper.get_meta("wander_target")
	if _helper_distance_to(helper, wander_target) <= HELPER_WANDER_ARRIVE_PT * _ui_scale():
		wander_target = _random_helper_center_position()
		helper.set_meta("wander_target", wander_target)
	_move_helper_toward(helper, wander_target, float(row.get("speed", 80.0)) * 0.45, delta)


func _find_helper_target(helper: TextureRect, row: Dictionary) -> TextureRect:
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
	var helper_instance_id: int = int(helper.get_instance_id())
	var reservation_owner: int = _drop_reservation_owner(item)
	if reservation_owner != 0 and reservation_owner != helper_instance_id:
		return false
	item.set_meta("reserved_helper_instance_id", helper_instance_id)
	helper.set_meta("target", item)
	return true


func _release_helper_target(helper: TextureRect) -> void:
	var target: TextureRect = helper.get_meta("target") as TextureRect if helper.has_meta("target") else null
	if target != null and is_instance_valid(target):
		var helper_instance_id: int = int(helper.get_instance_id())
		if int(target.get_meta("reserved_helper_instance_id", 0)) == helper_instance_id:
			target.remove_meta("reserved_helper_instance_id")
	helper.set_meta("target", null)


func _drop_reservation_owner(item: TextureRect) -> int:
	var owner_id: int = int(item.get_meta("reserved_helper_instance_id", 0))
	if owner_id <= 0:
		return 0
	var owner: Object = instance_from_id(owner_id)
	if owner == null or not is_instance_valid(owner) or (owner is Node and (owner as Node).is_queued_for_deletion()):
		item.remove_meta("reserved_helper_instance_id")
		return 0
	return owner_id


func _move_helper_toward(helper: TextureRect, target_center: Vector2, speed_pt: float, delta: float) -> void:
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
	return (helper.position + helper.size * 0.5).distance_to(target_center)


func _helper_can_work_here(row: Dictionary) -> bool:
	var scene_ids: Array = row.get("scenes", [])
	return scene_ids.is_empty() or scene_ids.has(GameState.current_scene_id)


func _get_helper_node(helper_id: String) -> TextureRect:
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper != null and not helper.is_queued_for_deletion() and bool(helper.get_meta("is_helper", false)) and String(helper.get_meta("helper_id", "")) == helper_id:
			return helper
	return null


func _reset_helper_targets() -> void:
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper != null and bool(helper.get_meta("is_helper", false)):
			_release_helper_target(helper)
			helper.set_meta("wander_target", _random_helper_center_position())


func _helper_spawn_position(spawn_index: int) -> Vector2:
	var scale: float = _ui_scale()
	var column: int = spawn_index % HELPER_SPAWN_COLUMNS
	var row: int = floori(float(spawn_index) / float(HELPER_SPAWN_COLUMNS))
	var x: float = (SPAWN_MARGIN_PT + 18.0 + float(column) * 66.0) * scale
	var y: float = (TOP_RESERVED_PT + 22.0 + float(row) * 58.0) * scale
	return _clamp_helper_position(Vector2(x, y))


func _random_helper_center_position() -> Vector2:
	var scale: float = _ui_scale()
	var helper_size: Vector2 = _helper_size()
	var min_x: float = HELPER_WANDER_MARGIN_PT * scale + helper_size.x * 0.5
	var max_x: float = maxf(min_x, size.x - HELPER_WANDER_MARGIN_PT * scale - helper_size.x * 0.5)
	var min_y: float = TOP_RESERVED_PT * scale + helper_size.y * 0.5
	var max_y: float = maxf(min_y, size.y - HELPER_WANDER_MARGIN_PT * scale - helper_size.y * 0.5)
	return Vector2(_rng.randf_range(min_x, max_x), _rng.randf_range(min_y, max_y))


func _clamp_helper_position(position: Vector2) -> Vector2:
	var scale: float = _ui_scale()
	var helper_size: Vector2 = _helper_size()
	var min_x: float = HELPER_WANDER_MARGIN_PT * scale
	var max_x: float = maxf(min_x, size.x - helper_size.x - HELPER_WANDER_MARGIN_PT * scale)
	var min_y: float = TOP_RESERVED_PT * scale
	var max_y: float = maxf(min_y, size.y - helper_size.y - HELPER_WANDER_MARGIN_PT * scale)
	return Vector2(clampf(position.x, min_x, max_x), clampf(position.y, min_y, max_y))


func _current_scene() -> Dictionary:
	var scene: Dictionary = ConfigDB.get_scene(GameState.current_scene_id)
	if scene.is_empty():
		scene = ConfigDB.get_scene(ConfigDB.get_default_scene_id())
	return scene


func _scene_visible_limit(scene_id: String) -> int:
	return maxi(0, int(ConfigDB.get_scene(scene_id).get("max_on_screen", 0)))


func _get_available_drops() -> Array:
	return _get_available_drops_for_scene(GameState.current_scene_id)


func _get_available_drops_for_scene(scene_id: String) -> Array:
	var out: Array = []
	for drop in ConfigDB.get_scene_drops(scene_id):
		if GameState.is_drop_unlocked(String(drop.get("id", ""))):
			out.append(drop)
	return out


func _pick_weighted_drop(drops: Array) -> Dictionary:
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
	if _empty_label != null:
		_empty_label.visible = drops.is_empty()


func _refresh_inventory_counter() -> void:
	if _inventory_label == null:
		return
	_inventory_label.text = "产物 %d/%d" % [
		GameState.get_scene_drop_count(GameState.current_scene_id),
		GameState.get_scene_capacity(GameState.current_scene_id),
	]


func apply_layout(viewport_size: Vector2) -> void:
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
	return DROP_SIZE_PT * _ui_scale()


func _helper_size() -> Vector2:
	return HELPER_SIZE_PT * _ui_scale()


func _relayout_drops() -> void:
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
		if is_instance_valid(glow):
			glow.size = drop_size * GLOW_SCALE
			glow.pivot_offset = glow.size * 0.5
			glow.position = _random_drop_position()
			item.position = glow.position + (glow.size - item.size) * 0.5
			_update_drop_layer(item, glow)
		else:
			item.position = _random_drop_position()
			_update_drop_layer(item, null)


func _relayout_helpers() -> void:
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
	return _ui_scale_from_viewport(get_viewport_rect().size)


func _ui_scale_from_viewport(viewport_size: Vector2) -> float:
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)


func _inventory_counter_style(scale: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.15, 0.17, 0.84)
	style.border_color = Color(0.94, 0.76, 0.32, 0.95)
	style.set_border_width_all(int(1.5 * scale))
	style.set_corner_radius_all(int(6.0 * scale))
	style.content_margin_left = 7.0 * scale
	style.content_margin_right = 7.0 * scale
	return style


func _free_control(control: Control) -> void:
	if is_instance_valid(control):
		control.queue_free()
