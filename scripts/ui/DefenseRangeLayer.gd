class_name DefenseRangeLayer
extends Control
## 防守单位攻击范围绘制层。
##
## ranges 每项包含 center、radius 和可选 color。此层只绘图，
## 命中判定仍由 DefenseMode 使用相同半径计算。

var ranges: Array = []


func set_ranges(value: Array) -> void:
    ## 替换整帧范围快照并请求重绘，避免维护大量圆形控件。
	ranges = value.duplicate(true)
	queue_redraw()


func _draw() -> void:
    ## 先画半透明填充，再画边缘线，保持敌人与背景可辨认。
	for entry_variant in ranges:
		var entry: Dictionary = entry_variant as Dictionary
		var center: Vector2 = entry.get("center", Vector2.ZERO)
		var radius: float = float(entry.get("radius", 0.0))
		var line_width: float = float(entry.get("line_width", 1.5))
		if radius <= 0.0:
			continue
		draw_circle(center, radius, Color(0.35, 0.92, 0.58, 0.055))
		draw_arc(center, radius, 0.0, TAU, 72, Color(0.72, 1.0, 0.78, 0.38), line_width, true)
