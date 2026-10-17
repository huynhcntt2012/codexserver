extends Node
## Game-styled mouse cursors drawn in code (no third-party art): a yellow arrow
## an orange one over anything clickable and a yellow I-beam over text fields,
## all with the lobby's navy rim. Every other shape reuses the arrow, so no
## shape falls back to a missing or mismatched system cursor.
const SIZE := 36
const ARROW := [Vector2(0.06, 0.04), Vector2(0.06, 0.8), Vector2(0.25, 0.63), Vector2(0.39, 0.94), Vector2(0.52, 0.88), Vector2(0.38, 0.58), Vector2(0.64, 0.58)]
const BEAM := [Vector2(0.3, 0.04), Vector2(0.7, 0.04), Vector2(0.7, 0.15), Vector2(0.56, 0.15), Vector2(0.56, 0.85), Vector2(0.7, 0.85), Vector2(0.7, 0.96), Vector2(0.3, 0.96), Vector2(0.3, 0.85), Vector2(0.44, 0.85), Vector2(0.44, 0.15), Vector2(0.3, 0.15)]
const RIM := Color("1d4f8a")
const ARROW_FILL := [Color("fff6c9"), Color("ffd257")]
const POINTER_FILL := [Color("ffd8a8"), Color("ff9f43")]

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var arrow := draw_cursor(ARROW_FILL[0], ARROW_FILL[1])
	for shape in Input.CURSOR_HSPLIT + 1:
		Input.set_custom_mouse_cursor(arrow, shape, Vector2(2, 1))
	Input.set_custom_mouse_cursor(draw_cursor(POINTER_FILL[0], POINTER_FILL[1]), Input.CURSOR_POINTING_HAND, Vector2(2, 1))
	Input.set_custom_mouse_cursor(draw_cursor(ARROW_FILL[0], ARROW_FILL[1], BEAM), Input.CURSOR_IBEAM, Vector2(SIZE, SIZE) / 2)
	# Buttons default to the arrow; give every clickable control the pointer.
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is BaseButton and node.mouse_default_cursor_shape == Control.CURSOR_ARROW:
		node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

## 4×4 supersampled shape: gradient fill, 2px rim, soft shadow below-right.
static func draw_cursor(top: Color, bottom: Color, shape: Array = ARROW) -> Image:
	var points := PackedVector2Array()
	for p in shape:
		points.append(p * (SIZE - 4))
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var fill := 0.0
			var rim := 0.0
			var shade := 0.0
			for sy in 4:
				for sx in 4:
					var at := Vector2(x + (sx + 0.5) / 4.0, y + (sy + 0.5) / 4.0)
					if Geometry2D.is_point_in_polygon(at, points):
						fill += 1.0
					elif edge_distance(at, points) <= 2.0:
						rim += 1.0
					elif Geometry2D.is_point_in_polygon(at - Vector2(1.5, 2.0), points):
						shade += 1.0
			var color := top.lerp(bottom, clampf(float(y) / (SIZE * 0.8), 0.0, 1.0))
			var out := Color(0, 0, 0, shade / 16.0 * 0.3)
			out = out.blend(Color(RIM, rim / 16.0))
			out = out.blend(Color(color, fill / 16.0)) if fill > 0.0 else out
			image.set_pixel(x, y, out)
	return image

static func edge_distance(at: Vector2, points: PackedVector2Array) -> float:
	var best := INF
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		best = minf(best, at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b)))
	return best
