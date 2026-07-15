extends VBoxContainer
## Small transient message stack.

const BASE_LOGICAL_WIDTH: float = 393.0


func _ready() -> void:
	EventBus.toast.connect(_on_toast)


func _on_toast(message: String) -> void:
	var label: Label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(14.0 * _ui_scale()))
	label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.94, 1.0))
	add_child(label)
	var timer: SceneTreeTimer = get_tree().create_timer(2.0)
	timer.timeout.connect(func(): _free_label(label))


func _free_label(label: Label) -> void:
	if is_instance_valid(label):
		label.queue_free()


func _ui_scale() -> float:
	return maxf(1.0, get_viewport_rect().size.x / BASE_LOGICAL_WIDTH)
