class_name BottleSpawnArea
extends Control
## Central play field that spawns clickable plastic bottles.

const BOTTLE_TEXTURE: Texture2D = preload("res://assets/bottle.svg")
const STREET_TEXTURE: Texture2D = preload("res://assets/street_pickup_bg_clean.png")
const BASE_LOGICAL_WIDTH: float = 393.0
const BOTTLE_SIZE_PT: Vector2 = Vector2(44.0, 64.0)
const MAX_BOTTLES: int = 9
const SPAWN_MARGIN_PT: float = 18.0
const TOP_RESERVED_PT: float = 118.0
const SPAWN_INTERVAL_MIN: float = 0.65
const SPAWN_INTERVAL_MAX: float = 1.25

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spawn_timer: float = 0.0
var _street_bg: TextureRect


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_rng.randomize()
	_build_background()
	EventBus.bottle_collected.connect(_on_bottle_collected)
	_reset_spawn_timer(0.1)
	set_process(true)


func _process(delta: float) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	if _active_bottle_count() < MAX_BOTTLES:
		_spawn_bottle()
	_reset_spawn_timer()


func _build_background() -> void:
	_street_bg = TextureRect.new()
	_street_bg.texture = STREET_TEXTURE
	_street_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_street_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_street_bg.anchor_right = 1.0
	_street_bg.anchor_bottom = 1.0
	_street_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_street_bg)


func _spawn_bottle() -> void:
	var glow: TextureRect = TextureRect.new()
	var bottle: TextureRect = TextureRect.new()
	var bottle_size: Vector2 = _bottle_size()
	glow.texture = BOTTLE_TEXTURE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glow.size = bottle_size * 1.16
	glow.pivot_offset = glow.size * 0.5
	glow.position = _random_bottle_position()
	glow.modulate = Color(0.62, 1.0, 0.35, 0.5)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.z_index = 1
	add_child(glow)

	bottle.texture = BOTTLE_TEXTURE
	bottle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bottle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bottle.size = bottle_size
	bottle.pivot_offset = bottle_size * 0.5
	bottle.position = glow.position + (glow.size - bottle.size) * 0.5
	bottle.mouse_filter = Control.MOUSE_FILTER_STOP
	bottle.set_meta("is_bottle", true)
	bottle.set_meta("glow", glow)
	bottle.z_index = 2
	bottle.gui_input.connect(_on_bottle_gui_input.bind(bottle))
	add_child(bottle)

	bottle.modulate.a = 0.0
	bottle.scale = Vector2(0.85, 0.85)
	glow.modulate.a = 0.0
	glow.scale = Vector2(0.85, 0.85)
	var tween: Tween = create_tween()
	tween.tween_property(bottle, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(bottle, "scale", Vector2.ONE, 0.12)
	tween.parallel().tween_property(glow, "modulate:a", 0.5, 0.12)
	tween.parallel().tween_property(glow, "scale", Vector2.ONE, 0.12)


func _random_bottle_position() -> Vector2:
	var scale: float = _ui_scale()
	var bottle_size: Vector2 = _bottle_size()
	var min_x: float = SPAWN_MARGIN_PT * scale
	var max_x: float = maxf(min_x, size.x - bottle_size.x - SPAWN_MARGIN_PT * scale)
	var min_y: float = TOP_RESERVED_PT * scale
	var max_y: float = maxf(min_y, size.y - bottle_size.y - SPAWN_MARGIN_PT * scale)
	return Vector2(_rng.randf_range(min_x, max_x), _rng.randf_range(min_y, max_y))


func _on_bottle_gui_input(event: InputEvent, bottle: TextureRect) -> void:
	var pressed: bool = false
	if event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		pressed = event.pressed

	if not pressed or bool(bottle.get_meta("collected", false)):
		return

	bottle.set_meta("collected", true)
	var system: ProductionSystem = get_tree().root.get_node_or_null("Main/Systems/ProductionSystem") as ProductionSystem
	if system != null:
		system.collect_bottle(bottle.global_position + bottle.size * 0.5)
	_despawn_bottle(bottle)


func _despawn_bottle(bottle: TextureRect) -> void:
	bottle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow: TextureRect = bottle.get_meta("glow", null) as TextureRect
	var tween: Tween = create_tween()
	tween.tween_property(bottle, "scale", Vector2(0.45, 0.45), 0.16)
	tween.parallel().tween_property(bottle, "modulate:a", 0.0, 0.16)
	if is_instance_valid(glow):
		tween.parallel().tween_property(glow, "scale", Vector2(0.45, 0.45), 0.16)
		tween.parallel().tween_property(glow, "modulate:a", 0.0, 0.16)
	tween.finished.connect(func(): _free_control(bottle))
	tween.finished.connect(func(): _free_control(glow))


func _active_bottle_count() -> int:
	var count: int = 0
	for child in get_children():
		var node: Node = child as Node
		if node != null and bool(node.get_meta("is_bottle", false)) and not bool(node.get_meta("collected", false)):
			count += 1
	return count


func _reset_spawn_timer(first_delay: float = -1.0) -> void:
	if first_delay >= 0.0:
		_spawn_timer = first_delay
	else:
		_spawn_timer = _rng.randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)


func _on_bottle_collected(bottle_amount: int, cash_amount: float, screen_pos: Vector2) -> void:
	if screen_pos == Vector2.ZERO:
		return

	var label: Label = Label.new()
	var scale: float = _ui_scale()
	label.text = "+%d 瓶  +%s 元" % [bottle_amount, BigNumber.format(cash_amount)]
	label.add_theme_font_size_override("font_size", int(20.0 * scale))
	label.modulate = Color(0.1, 0.55, 0.28, 1.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.global_position = screen_pos - Vector2(74.0, 38.0) * scale

	var tween: Tween = create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector2(0.0, -42.0) * scale, 0.48)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.48)
	tween.finished.connect(func(): _free_control(label))


func apply_layout(viewport_size: Vector2) -> void:
	if _street_bg != null:
		_street_bg.size = size


func _bottle_size() -> Vector2:
	return BOTTLE_SIZE_PT * _ui_scale()


func _ui_scale() -> float:
	return _ui_scale_from_viewport(get_viewport_rect().size)


func _ui_scale_from_viewport(viewport_size: Vector2) -> float:
	return maxf(1.0, viewport_size.x / BASE_LOGICAL_WIDTH)


func _free_control(control: Control) -> void:
	if is_instance_valid(control):
		control.queue_free()
