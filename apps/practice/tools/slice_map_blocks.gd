extends SceneTree
## Cuts the owner-supplied map block sheet (7 columns x 4 rows of props on a
## white background with soft shadows) into assets/obstacles/<name>/00.png.
## The background is the light, grey-ish area reachable from the sheet border;
## white inside a prop (skull, stripes, flowers) is kept because the prop's
## outline closes it off. Each prop is scaled to fit SIZE x SIZE, centred and
## standing on the bottom edge, so tall props (trees, lantern) rise above the tile.
## Usage: godot --headless --script tools/slice_map_blocks.gd -- \
##   tools/source/map_blocks.webp "$PWD/assets/obstacles"
const COLS := 7
const ROWS := 4
const SIZE := 128
const NAMES := [
	"brick_wall", "stone_block", "mossy_stone", "wood_box", "metal_crate", "tnt_barrel", "rusty_barrel",
	"tree_stump", "round_tree", "pine_tree", "flower_bush", "cactus", "bamboo", "sandbags",
	"traffic_cone", "road_barrier", "treasure_chest", "ice_block", "crystal_block", "mushroom", "pumpkin",
	"water_barrel", "hazard_crate", "stone_lantern", "cracked_brick", "broken_box", "cracked_ice", "cracked_stone",
]

## Background: light and nearly colourless (paper white and its grey shadows).
func is_background(c: Color) -> bool:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	return c.a < 0.05 or (lo > 0.70 and hi - lo < 0.09)

func _init():
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	img.convert(Image.FORMAT_RGBA8)
	var root: String = args[1]
	var w := img.get_width(); var h := img.get_height()
	# Flood the background from the border.
	var bg := PackedByteArray(); bg.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		stack.append(x); stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w); stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if bg[i] == 1: continue
		var x := i % w; var y := i / w
		if not is_background(img.get_pixel(x, y)): continue
		bg[i] = 1
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)
	# Props: connected non-background pixels, grouped into grid cells by centre.
	var label := PackedInt32Array(); label.resize(w * h); label.fill(-1)
	var boxes: Array = []  # per cell: Rect2i of its pieces
	var pieces: Array = []  # per cell: Array of component ids
	for c in COLS * ROWS:
		boxes.append(Rect2i()); pieces.append([])
	var comps: Array = []  # [rect, size]
	for start in w * h:
		if bg[start] == 1 or label[start] >= 0: continue
		var id := comps.size(); label[start] = id
		var todo: Array[int] = [start]
		var n := 0; var x0 := w; var y0 := h; var x1 := 0; var y1 := 0
		while not todo.is_empty():
			var i: int = todo.pop_back(); n += 1
			var x := i % w; var y := i / w
			x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
			for j in [i - 1, i + 1, i - w, i + w]:
				if j < 0 or j >= w * h or absi(j % w - x) > 1: continue
				if bg[j] == 0 and label[j] < 0:
					label[j] = id; todo.append(j)
		comps.append([Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1), n])
	for id in comps.size():
		var rect: Rect2i = comps[id][0]
		if comps[id][1] < 150: continue  # specks
		var centre := rect.get_center()
		var cell := clampi(centre.x * COLS / w, 0, COLS - 1) + clampi(centre.y * ROWS / h, 0, ROWS - 1) * COLS
		pieces[cell].append(id)
		boxes[cell] = rect if boxes[cell].size == Vector2i.ZERO else boxes[cell].merge(rect)
	for cell in COLS * ROWS:
		var box: Rect2i = boxes[cell].grow(2).intersection(Rect2i(0, 0, w, h))
		var out := Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
		var keep := {}
		for id in pieces[cell]: keep[id] = true
		for y in box.size.y:
			for x in box.size.x:
				var i := (box.position.y + y) * w + box.position.x + x
				if label[i] >= 0 and keep.has(label[i]):
					out.set_pixel(x, y, img.get_pixel(box.position.x + x, box.position.y + y))
		var scale := float(SIZE - 4) / float(maxi(box.size.x, box.size.y))
		var fit := Vector2i(maxi(1, roundi(box.size.x * scale)), maxi(1, roundi(box.size.y * scale)))
		out.resize(fit.x, fit.y, Image.INTERPOLATE_LANCZOS)
		var tile := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		tile.blend_rect(out, Rect2i(Vector2i.ZERO, fit), Vector2i((SIZE - fit.x) / 2, SIZE - 2 - fit.y))
		DirAccess.make_dir_recursive_absolute("%s/%s" % [root, NAMES[cell]])
		tile.save_png("%s/%s/00.png" % [root, NAMES[cell]])
		print(NAMES[cell], " ", box, " pieces=", pieces[cell].size())
	quit()
