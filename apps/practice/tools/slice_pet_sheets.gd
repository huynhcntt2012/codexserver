extends SceneTree
## Cuts the owner-supplied pet sheets (229.png-238.png: 4 columns x 5 rows of
## idle, walk_down, walk_up, walk_left, walk_right) into assets/cosmetics/pets:
## pets/<name>/<anim>/01-04.png at FRAME px. The art drifts sideways across a
## row of the sheet, so each frame is moved left/right until the art's centre
## (alpha-weighted) is the frame's centre: the pet walks in place without
## sliding. Its height in the frame is kept (the walk's bob).
## Usage: godot --headless --script tools/slice_pet_sheets.gd -- \
##   <folder with 229.png..238.png> "$PWD/assets/cosmetics/pets"
const SHEETS := {
	"229": "bunny", "230": "dragon", "231": "sheep", "232": "deer", "233": "alpaca",
	"234": "cat", "235": "corgi", "236": "dino", "237": "turtle", "238": "fox",
}
const ROWS := ["idle", "walk_down", "walk_up", "walk_left", "walk_right"]
const COLS := 4
const FRAME := 128

## Faint glow and speckles around the art go; solid pixels keep their colour.
func cut(img: Image, x0: int, y0: int, w: int, h: int) -> Image:
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := img.get_pixel(x0 + x, y0 + y)
			c.a = clampf((c.a - 0.25) / 0.6, 0.0, 1.0)
			out.set_pixel(x, y, c if c.a > 0.0 else Color(0, 0, 0, 0))
	return clean(out)

## Drops specks much smaller than the pet, and slivers of neighbouring frames
## (blobs touching the cell edge that are well under the pet's size).
func clean(img: Image) -> Image:
	var w := img.get_width(); var h := img.get_height()
	var label := PackedInt32Array(); label.resize(w * h); label.fill(-1)
	var sizes := []; var edge := []
	for start in w * h:
		if label[start] >= 0 or img.get_pixel(start % w, start / w).a <= 0.0: continue
		var id := sizes.size(); var stack := [start]; label[start] = id
		var n := 0; var touches := false
		while not stack.is_empty():
			var i: int = stack.pop_back(); n += 1
			var x := i % w; var y := i / w
			if x == 0 or y == 0 or x == w - 1 or y == h - 1: touches = true
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var nx: int = x + dx; var ny: int = y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
					var j := ny * w + nx
					if label[j] < 0 and img.get_pixel(nx, ny).a > 0.0:
						label[j] = id; stack.append(j)
		sizes.append(n); edge.append(touches)
	var biggest := 0
	for n in sizes: biggest = max(biggest, n)
	for i in w * h:
		var id := label[i]
		if id >= 0 and (sizes[id] < biggest * 0.02 or (edge[id] and sizes[id] < biggest * 0.15)):
			img.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
	return img

## Transparent pixels take the colour of their nearest solid neighbour, so
## shrinking the frame does not leave a dark rim.
func bleed(img: Image) -> void:
	var w := img.get_width(); var h := img.get_height()
	for _pass in 4:
		var copy := img.duplicate()
		for y in h:
			for x in w:
				if copy.get_pixel(x, y).a > 0.0: continue
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var p: Vector2i = Vector2i(x, y) + d
					if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h: continue
					var c: Color = copy.get_pixel(p.x, p.y)
					if c.a > 0.0:
						img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
						break

## Moves the art horizontally so its alpha-weighted centre is the image centre,
## never pushing it over an edge.
func centre(img: Image) -> void:
	var w := img.get_width()
	var sum := 0.0
	var weight := 0.0
	for y in img.get_height():
		for x in w:
			var a := img.get_pixel(x, y).a
			sum += x * a
			weight += a
	if weight <= 0.0:
		return
	var used := img.get_used_rect()
	var shift := clampi(roundi(w * 0.5 - sum / weight), -used.position.x, w - used.end.x)
	if shift == 0:
		return
	var moved := Image.create(w, img.get_height(), false, Image.FORMAT_RGBA8)
	moved.blit_rect(img, used, used.position + Vector2i(shift, 0))
	img.copy_from(moved)

func _init():
	var args := OS.get_cmdline_user_args()
	var source: String = args[0]
	var root: String = args[1]
	for sheet in SHEETS:
		var img := Image.load_from_file("%s/%s.png" % [source, sheet])
		img.convert(Image.FORMAT_RGBA8)
		var cw := img.get_width() / COLS
		var ch := img.get_height() / ROWS.size()
		var side := mini(cw, ch)
		for r in ROWS.size():
			var folder := "%s/%s/%s" % [root, SHEETS[sheet], ROWS[r]]
			DirAccess.make_dir_recursive_absolute(folder)
			for c in COLS:
				var frame := cut(img, c * cw + (cw - side) / 2, r * ch + (ch - side) / 2, side, side)
				centre(frame)
				bleed(frame)
				frame.resize(FRAME, FRAME, Image.INTERPOLATE_LANCZOS)
				frame.save_png("%s/%02d.png" % [folder, c + 1])
		print("cut ", sheet, " -> ", SHEETS[sheet])
	quit()
