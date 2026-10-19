extends SceneTree
## Cuts the owner-supplied "Rider Character Sheet" (5 heroes x 5 rows of 3
## sitting frames, each row on its own coloured panel) into
## assets/riders/<hero>/<anim>/01-03.png. The panel colour is removed by growing
## from the panel edge over small colour steps that stay close to the panel's
## own colour; the hero's bright outline stops it. Each hero's frames share one
## scale, are centred and sit on the bottom edge of a FRAME x FRAME canvas.
## Usage: godot --headless --script tools/slice_rider_sheet.gd -- \
##   tools/source/rider_sheet.webp "$PWD/assets/riders"
const HEROES := ["bombo", "mimi", "zin", "lala", "kai"]
const COLS := [[72, 268], [277, 478], [487, 688], [697, 898], [908, 1112]]
const ANIMS := ["ride_idle", "ride_down", "ride_up", "ride_left", "ride_right"]
const ROWS := [[342, 458], [470, 598], [610, 742], [754, 882], [894, 1022]]
const INSET := 9  # skip the panel's glowing border
const STEP := 0.055  # colour change allowed between neighbouring background pixels
const REACH := 0.34  # colour distance allowed from the panel colour
const FRAME := 64
const HEIGHT := 58  # tallest frame of a hero, in canvas pixels

func dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

## Pixels of `rect` that are not panel background, as a mask.
func foreground(img: Image, rect: Rect2i) -> PackedByteArray:
	var w := rect.size.x; var h := rect.size.y
	var samples: Array[Color] = []
	for x in range(0, w, 4):
		samples.append(img.get_pixel(rect.position.x + x, rect.position.y))
		samples.append(img.get_pixel(rect.position.x + x, rect.end.y - 1))
	var panel := Color(0, 0, 0)
	for c in samples: panel += c
	panel = panel / float(samples.size())
	var bg := PackedByteArray(); bg.resize(w * h)
	var todo: Array[int] = []
	for x in w: todo.append(x); todo.append((h - 1) * w + x)
	for y in h: todo.append(y * w); todo.append(y * w + w - 1)
	for i in todo: bg[i] = 1
	while not todo.is_empty():
		var i: int = todo.pop_back()
		var x := i % w; var y := i / w
		var here := img.get_pixel(rect.position.x + x, rect.position.y + y)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x; var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
			var j := ny * w + nx
			if bg[j] == 1: continue
			var c := img.get_pixel(rect.position.x + nx, rect.position.y + ny)
			if dist(c, here) < STEP and dist(c, panel) < REACH:
				bg[j] = 1; todo.append(j)
	var fg := PackedByteArray(); fg.resize(w * h)
	for i in w * h: fg[i] = 1 - bg[i]
	return fg

## Keeps the largest blob and blobs at least 4% of it (hands, feet); a smaller
## blob on the left/right edge must reach 25% (else it is the neighbour frame).
func main_blobs(fg: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var label := PackedInt32Array(); label.resize(w * h); label.fill(-1)
	var sizes := []
	for s in w * h:
		if fg[s] == 0 or label[s] >= 0: continue
		var id := sizes.size(); label[s] = id
		var todo: Array[int] = [s]; var n := 0
		while not todo.is_empty():
			var i: int = todo.pop_back(); n += 1
			for j in [i - 1, i + 1, i - w, i + w]:
				if j < 0 or j >= w * h or absi(j % w - i % w) > 1: continue
				if fg[j] == 1 and label[j] < 0:
					label[j] = id; todo.append(j)
		sizes.append(n)
	var biggest := 0
	for n in sizes: biggest = maxi(biggest, n)
	var side := {}  # blobs touching the left or right edge
	for y in h:
		for x in [0, w - 1]:
			if label[y * w + x] >= 0: side[label[y * w + x]] = true
	var out := PackedByteArray(); out.resize(w * h)
	for i in w * h:
		var id := label[i]
		if id >= 0 and sizes[id] >= biggest * (0.25 if side.has(id) and sizes[id] < biggest else 0.04): out[i] = 1
	return out

func _init():
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	img.convert(Image.FORMAT_RGBA8)
	var root: String = args[1]
	for c in HEROES.size():
		var frames := []  # [anim, index, Image cut to its box]
		var tallest := 1
		for r in ANIMS.size():
			var panel := Rect2i(COLS[c][0], ROWS[r][0], COLS[c][1] - COLS[c][0], ROWS[r][1] - ROWS[r][0]).grow(-INSET)
			var fg := foreground(img, panel)
			# Frames may touch: split where the fewest hero pixels are, near each third.
			var cuts := [0]
			for k in [1, 2]:
				var best: int = panel.size.x * k / 3; var least := 1 << 30
				for x in range(best - 22, best + 23):
					var n := 0
					for y in panel.size.y: n += fg[y * panel.size.x + x]
					if n < least: least = n; best = x
				cuts.append(best)
			cuts.append(panel.size.x)
			for f in 3:
				var x0: int = cuts[f]; var x1: int = cuts[f + 1]
				var w := x1 - x0; var h := panel.size.y
				var part := PackedByteArray(); part.resize(w * h)
				for y in h:
					for x in w: part[y * w + x] = fg[y * panel.size.x + x0 + x]
				part = main_blobs(part, w, h)
				var box := Rect2i()
				var cut := Image.create(w, h, false, Image.FORMAT_RGBA8)
				for y in h:
					for x in w:
						if part[y * w + x] == 1:
							cut.set_pixel(x, y, img.get_pixel(panel.position.x + x0 + x, panel.position.y + y))
							box = Rect2i(x, y, 1, 1) if box.size == Vector2i.ZERO else box.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
				var piece := cut.get_region(box)
				tallest = maxi(tallest, piece.get_height())
				frames.append([ANIMS[r], f, piece])
		var scale := float(HEIGHT) / float(tallest)
		for entry in frames:
			var piece: Image = entry[2]
			var size := Vector2i(maxi(1, roundi(piece.get_width() * scale)), maxi(1, roundi(piece.get_height() * scale)))
			piece.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
			var canvas := Image.create(FRAME, FRAME, false, Image.FORMAT_RGBA8)
			canvas.blend_rect(piece, Rect2i(Vector2i.ZERO, size), Vector2i((FRAME - size.x) / 2, FRAME - 1 - size.y))
			var folder := "%s/%s/%s" % [root, HEROES[c], entry[0]]
			DirAccess.make_dir_recursive_absolute(folder)
			canvas.save_png("%s/%02d.png" % [folder, entry[1] + 1])
		print("cut ", HEROES[c])
	quit()
