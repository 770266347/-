class_name DefenseRangeLayer
extends Control
## Draws helper attack radii behind enemies in freeform defense mode.

var ranges: Array = []


func set_ranges(value: Array) -> void:
	ranges = value.duplicate(true)
	queue_redraw()


func _draw() -> void:
	for entry_variant in ranges:
		var entry: Dictionary = entry_variant as Dictionary
		var center: Vector2 = entry.get("center", Vector2.ZERO)
		var radius: float = float(entry.get("radius", 0.0))
		var line_width: float = float(entry.get("line_width", 1.5))
		if radius <= 0.0:
			continue
		draw_circle(center, radius, Color(0.35, 0.92, 0.58, 0.055))
		draw_arc(center, radius, 0.0, TAU, 72, Color(0.72, 1.0, 0.78, 0.38), line_width, true)
