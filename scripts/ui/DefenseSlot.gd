class_name DefenseSlot
extends PanelContainer
## One lane assignment target in street-defense mode.

signal helper_dropped(slot_index: int, helper_id: String)

var slot_index: int = 0
var assigned_helper_id: String = ""
var icon: TextureRect
var name_label: Label
var _scale: float = 1.0


func configure(index: int, scale: float) -> void:
	slot_index = index
	_scale = scale
	custom_minimum_size = Vector2(62.0, 82.0) * scale
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _slot_style(false))

	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)

	icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(48.0, 56.0) * scale
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	name_label = Label.new()
	name_label.text = "+"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", int(11.0 * scale))
	name_label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.48, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)


func assign_helper(row: Dictionary) -> void:
	assigned_helper_id = String(row.get("id", ""))
	icon.texture = load(String(row.get("sprite", ""))) as Texture2D
	name_label.text = String(row.get("name", "帮手"))
	tooltip_text = name_label.text
	add_theme_stylebox_override("panel", _slot_style(true))


func clear_helper() -> void:
	assigned_helper_id = ""
	icon.texture = null
	name_label.text = "+"
	tooltip_text = ""
	add_theme_stylebox_override("panel", _slot_style(false))


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and String((data as Dictionary).get("type", "")) == "defense_helper"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data as Dictionary
	var helper_id: String = String(payload.get("helper_id", ""))
	if not helper_id.is_empty():
		helper_dropped.emit(slot_index, helper_id)


func _slot_style(occupied: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.22, 0.24, 0.94) if occupied else Color(0.12, 0.15, 0.17, 0.74)
	style.border_color = Color(0.98, 0.76, 0.28, 1.0) if occupied else Color(0.78, 0.82, 0.76, 0.82)
	style.set_border_width_all(int((2.0 if occupied else 1.0) * _scale))
	style.set_corner_radius_all(int(6.0 * _scale))
	style.content_margin_left = 3.0 * _scale
	style.content_margin_right = 3.0 * _scale
	style.content_margin_top = 3.0 * _scale
	style.content_margin_bottom = 3.0 * _scale
	return style
