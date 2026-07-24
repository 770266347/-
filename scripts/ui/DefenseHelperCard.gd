class_name DefenseHelperCard
extends PanelContainer
## Draggable helper card used by the street-defense roster.

var helper_id: String = ""
var helper_row: Dictionary = {}
var icon: TextureRect
var name_label: Label


func configure(row: Dictionary, scale: float) -> void:
	helper_row = row
	helper_id = String(row.get("id", ""))
	custom_minimum_size = Vector2(62.0, 92.0) * scale
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	tooltip_text = String(row.get("name", "帮手"))
	add_theme_stylebox_override("panel", _card_style(scale))

	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)

	icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(48.0, 58.0) * scale
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(String(row.get("sprite", ""))) as Texture2D
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	name_label = Label.new()
	name_label.text = String(row.get("name", "帮手"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", int(10.0 * scale))
	name_label.add_theme_color_override("font_color", Color(0.18, 0.16, 0.14, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if helper_id.is_empty() or icon == null or icon.texture == null:
		return null
	var preview: TextureRect = TextureRect.new()
	preview.size = Vector2(52.0, 66.0)
	preview.texture = icon.texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.modulate = Color(1.0, 1.0, 1.0, 0.9)
	set_drag_preview(preview)
	return {
		"type": "defense_helper",
		"helper_id": helper_id,
	}


func _card_style(scale: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.91, 0.82, 0.98)
	style.border_color = Color(0.35, 0.31, 0.28, 1.0)
	style.set_border_width_all(int(1.0 * scale))
	style.set_corner_radius_all(int(6.0 * scale))
	style.content_margin_left = 4.0 * scale
	style.content_margin_right = 4.0 * scale
	style.content_margin_top = 3.0 * scale
	style.content_margin_bottom = 3.0 * scale
	return style
