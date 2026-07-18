class_name BottleSpawnArea
extends Control
## Central play field that spawns clickable collectables by current scene.

const FALLBACK_TEXTURE: Texture2D = preload("res://assets/bottle.svg")
const BASE_LOGICAL_WIDTH: float = 393.0
const DROP_SIZE_PT: Vector2 = Vector2(34.0, 50.0)
const HELPER_SIZE_PT: Vector2 = Vector2(38.0, 48.0)
const SPAWN_MARGIN_PT: float = 18.0
const TOP_RESERVED_PT: float = 118.0
const GLOW_SCALE: float = 1.16
const HELPER_WANDER_MARGIN_PT: float = 28.0
const HELPER_WANDER_ARRIVE_PT: float = 8.0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spawn_timer: float = 0.0
var _background: TextureRect
var _empty_label: Label


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_rng.randomize()
	_build_background()
	_build_empty_label()
	_apply_scene()
	EventBus.drop_collected.connect(_on_drop_collected)
	EventBus.scene_changed.connect(_on_scene_changed)
	EventBus.unlocked_drops_changed.connect(_on_unlocked_drops_changed)
	EventBus.helper_purchased.connect(_on_helper_purchased)
	_reset_spawn_timer(0.1)
	set_process(true)


func _process(delta: float) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_update_helpers(delta)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return

	var drops: Array = _get_available_drops()
	_update_empty_state(drops)
	if drops.is_empty():
		_reset_spawn_timer(0.8)
		return

	var max_on_screen: int = int(_current_scene().get("max_on_screen", 9))
	if _active_drop_count() < max_on_screen:
		_spawn_drop(_pick_weighted_drop(drops))
	_reset_spawn_timer()


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
	_empty_label.z_index = 5
	add_child(_empty_label)


func _apply_scene() -> void:
	var scene: Dictionary = _current_scene()
	var texture: Texture2D = load(String(scene.get("background", ""))) as Texture2D
	if texture != null:
		_background.texture = texture
	_empty_label.text = "%s暂无可收集物\n先去升级解锁" % ConfigDB.get_scene_name(GameState.current_scene_id)
	_clear_active_drops()
	_refresh_helpers()
	_update_empty_state(_get_available_drops())


func _spawn_drop(drop: Dictionary) -> void:
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
	glow.z_index = 1
	glow.set_meta("is_drop_glow", true)
	add_child(glow)

	item.texture = texture
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item.size = item_size
	item.pivot_offset = item_size * 0.5
	item.position = glow.position + (glow.size - item.size) * 0.5
	item.mouse_filter = Control.MOUSE_FILTER_STOP
	item.set_meta("is_drop", true)
	item.set_meta("drop", drop)
	item.set_meta("glow", glow)
	item.z_index = 2
	item.gui_input.connect(_on_drop_gui_input.bind(item))
	add_child(item)

	item.modulate.a = 0.0
	item.scale = Vector2(0.85, 0.85)
	glow.modulate.a = 0.0
	glow.scale = Vector2(0.85, 0.85)
	var tween: Tween = create_tween()
	tween.tween_property(item, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(item, "scale", Vector2.ONE, 0.12)
	tween.parallel().tween_property(glow, "modulate:a", 0.5, 0.12)
	tween.parallel().tween_property(glow, "scale", Vector2.ONE, 0.12)


func _random_drop_position() -> Vector2:
	var scale: float = _ui_scale()
	var drop_size: Vector2 = _drop_size()
	var min_x: float = SPAWN_MARGIN_PT * scale
	var max_x: float = maxf(min_x, size.x - drop_size.x - SPAWN_MARGIN_PT * scale)
	var min_y: float = TOP_RESERVED_PT * scale
	var max_y: float = maxf(min_y, size.y - drop_size.y - SPAWN_MARGIN_PT * scale)
	return Vector2(_rng.randf_range(min_x, max_x), _rng.randf_range(min_y, max_y))


func _on_drop_gui_input(event: InputEvent, item: TextureRect) -> void:
	var pressed: bool = false
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = event.pressed

	if not pressed or bool(item.get_meta("collected", false)):
		return

	_collect_drop_item(item)


func _collect_drop_item(item: TextureRect) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if bool(item.get_meta("collected", false)):
		return false

	item.set_meta("collected", true)
	var drop: Dictionary = item.get_meta("drop", {})
	var system: ProductionSystem = get_tree().root.get_node_or_null("Main/Systems/ProductionSystem") as ProductionSystem
	if system != null:
		system.collect_drop(drop, item.global_position + item.size * 0.5)
	_despawn_drop(item)
	return true


func _despawn_drop(item: TextureRect) -> void:
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow: TextureRect = item.get_meta("glow", null) as TextureRect
	var tween: Tween = create_tween()
	tween.tween_property(item, "scale", Vector2(0.45, 0.45), 0.16)
	tween.parallel().tween_property(item, "modulate:a", 0.0, 0.16)
	if is_instance_valid(glow):
		tween.parallel().tween_property(glow, "scale", Vector2(0.45, 0.45), 0.16)
		tween.parallel().tween_property(glow, "modulate:a", 0.0, 0.16)
	tween.finished.connect(func(): _free_control(item))
	tween.finished.connect(func(): _free_control(glow))


func _active_drop_count() -> int:
	var count: int = 0
	for child in get_children():
		var node: Node = child as Node
		if node != null and bool(node.get_meta("is_drop", false)) and not bool(node.get_meta("collected", false)):
			count += 1
	return count


func _clear_active_drops() -> void:
	for child in get_children():
		var control: Control = child as Control
		if control == null:
			continue
		if bool(control.get_meta("is_drop", false)) or bool(control.get_meta("is_drop_glow", false)):
			control.queue_free()
	_reset_helper_targets()


func _reset_spawn_timer(first_delay: float = -1.0) -> void:
	if first_delay >= 0.0:
		_spawn_timer = first_delay
	else:
		var scene: Dictionary = _current_scene()
		_spawn_timer = _rng.randf_range(
			float(scene.get("spawn_interval_min", 0.65)),
			float(scene.get("spawn_interval_max", 1.25))
		)


func _on_drop_collected(drop_name: String, amount: int, cash_amount: float, screen_pos: Vector2) -> void:
	if screen_pos == Vector2.ZERO:
		return

	var label: Label = Label.new()
	var scale: float = _ui_scale()
	label.text = "+%d %s  +%s 元" % [amount, drop_name, BigNumber.format(cash_amount)]
	label.add_theme_font_size_override("font_size", int(20.0 * scale))
	label.modulate = Color(0.1, 0.55, 0.28, 1.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 6
	add_child(label)
	label.global_position = screen_pos - Vector2(92.0, 38.0) * scale

	var tween: Tween = create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector2(0.0, -42.0) * scale, 0.48)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.48)
	tween.finished.connect(func(): _free_control(label))


func _on_scene_changed(_scene_id: String) -> void:
	_apply_scene()
	_reset_spawn_timer(0.1)


func _on_unlocked_drops_changed() -> void:
	_update_empty_state(_get_available_drops())
	_reset_spawn_timer(0.1)


func _on_helper_purchased(_helper_id: String) -> void:
	_refresh_helpers()


func _refresh_helpers() -> void:
	var wanted_ids: Dictionary = {}
	var spawn_index: int = 0
	for row in ConfigDB.get_helpers():
		var helper_id: String = String(row.get("id", ""))
		if helper_id.is_empty() or not GameState.has_helper(helper_id):
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
	helper.z_index = 4
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
		if helper == null or not bool(helper.get_meta("is_helper", false)):
			continue
		_update_helper(helper, delta)


func _update_helper(helper: TextureRect, delta: float) -> void:
	var row: Dictionary = helper.get_meta("config", {})
	if row.is_empty() or not _helper_can_work_here(row):
		return

	var cooldown_remaining: float = maxf(0.0, float(helper.get_meta("cooldown_remaining", 0.0)) - delta)
	helper.set_meta("cooldown_remaining", cooldown_remaining)

	var target: TextureRect = helper.get_meta("target", null) as TextureRect
	if not _is_valid_helper_target(target, row):
		target = _find_helper_target(helper, row)
		helper.set_meta("target", target)

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
		helper.set_meta("cooldown_remaining", float(row.get("collect_cooldown", 1.0)))
		helper.set_meta("target", null)


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
		if item == null or not _is_valid_helper_target(item, row):
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


func _is_valid_helper_target(item: TextureRect, row: Dictionary) -> bool:
	if item == null or not is_instance_valid(item):
		return false
	if not bool(item.get_meta("is_drop", false)) or bool(item.get_meta("collected", false)):
		return false
	var drop: Dictionary = item.get_meta("drop", {})
	if String(drop.get("scene_id", GameState.current_scene_id)) != GameState.current_scene_id:
		return false
	var preferred_types: Array = row.get("preferred_types", [])
	return preferred_types.is_empty() or preferred_types.has(String(drop.get("type", "")))


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
		if helper != null and bool(helper.get_meta("is_helper", false)) and String(helper.get_meta("helper_id", "")) == helper_id:
			return helper
	return null


func _reset_helper_targets() -> void:
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper != null and bool(helper.get_meta("is_helper", false)):
			helper.set_meta("target", null)
			helper.set_meta("wander_target", _random_helper_center_position())


func _helper_spawn_position(spawn_index: int) -> Vector2:
	var scale: float = _ui_scale()
	var x: float = (SPAWN_MARGIN_PT + 18.0 + float(spawn_index) * 46.0) * scale
	var y: float = (TOP_RESERVED_PT + 22.0 + float(spawn_index % 2) * 32.0) * scale
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


func _get_available_drops() -> Array:
	var out: Array = []
	for drop in ConfigDB.get_scene_drops(GameState.current_scene_id):
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


func apply_layout(viewport_size: Vector2) -> void:
	if _background != null:
		_background.size = size
	if _empty_label != null:
		var scale: float = _ui_scale_from_viewport(viewport_size)
		_empty_label.size = Vector2(minf(size.x * 0.76, 310.0 * scale), 86.0 * scale)
		_empty_label.position = Vector2((size.x - _empty_label.size.x) * 0.5, maxf(150.0 * scale, size.y * 0.42))
		_empty_label.add_theme_font_size_override("font_size", int(17.0 * scale))
	_relayout_helpers()


func _drop_size() -> Vector2:
	return DROP_SIZE_PT * _ui_scale()


func _helper_size() -> Vector2:
	return HELPER_SIZE_PT * _ui_scale()


func _relayout_helpers() -> void:
	for child in get_children():
		var helper: TextureRect = child as TextureRect
		if helper == null or not bool(helper.get_meta("is_helper", false)):
			continue
		helper.size = _helper_size()
		helper.pivot_offset = helper.size * 0.5
		helper.position = _clamp_helper_position(helper.position)


func _ui_scale() -> float:
	return _ui_scale_from_viewport(get_viewport_rect().size)


func _ui_scale_from_viewport(viewport_size: Vector2) -> float:
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)


func _free_control(control: Control) -> void:
	if is_instance_valid(control):
		control.queue_free()
