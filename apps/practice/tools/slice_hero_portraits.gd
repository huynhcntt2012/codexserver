extends SceneTree
## Cuts the owner-supplied animated portrait sheet (tools/source/
## hero_portraits_idle.webp, 5 rows x 6 poses: Bombo, Mimi, Zin, Lala, Kai) into
## assets/characters/portraits/<hero>/01..06.png.
## An opaque sheet is matted first (matte()): its flat background becomes
## transparent, drop shadows and edges become soft alpha.
## The sheet is a grid split at its emptiest pixel columns; figures of
## neighbouring rows can touch (a hop meets the head below), so each column is
## split between rows at its own emptiest pixel row. In each cell the biggest
## blob is the figure; the rest are specks of neighbours. Where a figure is
## joined to the one above, the narrow rows at the cell's top (the foot of the
## hop above) are dropped. One scale per hero and the
## sheet's vertical offsets are kept, so the hop and the crouch stay in the
## animation. Only cutting and scaling; no pixels are painted.
## Usage: godot --headless --path . --script res://tools/slice_hero_portraits.gd -- \
##   tools/source/hero_portraits_idle.webp "$PWD/assets/characters/portraits"
const SIZE := 160  # same canvas as the still portraits
const MARGIN := 3
const ROWS := ["bombo", "mimi", "zin", "lala", "kai"]
const COLS := 6
const ALPHA := 0.25  # faint shade does not join a figure to its neighbours
const BG_NEAR := 0.05  # colour distance still counted as the flat background
const BG_EDGE := 0.25  # brighter pixels up to this distance are a soft edge
const SHADE_MIN := 0.06  # darker than this is the outline, not a shadow
const SHADE_SAT := 0.65  # shadows are greyish; saturated dark blue is Bombo's shading

func _init():
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0]); img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width(); var h := img.get_height()
	if img.get_pixel(0, 0).a > 0.99:
		matte(img)
	var data := img.get_data()
	var cells := []  # [row][col] -> {box, keep: PackedByteArray over the box}
	for r in ROWS.size(): cells.append([])
	# Columns: split at the emptiest pixel column near each sixth of the width.
	var col_counts := PackedInt32Array()
	for x in w:
		var n := 0
		for y in range(0, h, 2):
			if data[(y * w + x) * 4 + 3] > 200: n += 1
		col_counts.append(n)
	var col_cuts := [0]
	for k in range(1, COLS):
		var guess := w * k / COLS
		var best := guess
		for x in range(guess - w / 14, guess + w / 14):
			if col_counts[x] < col_counts[best]: best = x
		col_cuts.append(best)
	col_cuts.append(w)
	print("column cuts ", col_cuts)
	for c in COLS:
		var x0: int = col_cuts[c]; var x1: int = col_cuts[c + 1]
		var counts := PackedInt32Array()
		for y in h:
			var n := 0
			for x in range(x0, x1):
				if data[(y * w + x) * 4 + 3] > 200: n += 1
			counts.append(n)
		var cuts := [0]
		for k in range(1, ROWS.size()):
			var guess := h * k / ROWS.size()
			var best := guess
			for y in range(guess - h / 10, guess + h / 10):
				if counts[y] < counts[best]: best = y
			cuts.append(best)
		cuts.append(h)
		for r in ROWS.size():
			cells[r].append(figure(data, w, Rect2i(x0, cuts[r], x1 - x0, cuts[r + 1] - cuts[r])))
	for r in ROWS.size():
		var top: float = INF
		var bottom := 0
		var widest := 0
		for f in cells[r]:
			top = minf(top, f.box.position.y); bottom = maxi(bottom, f.box.end.y); widest = maxi(widest, f.box.size.x)
		var scale := minf(float(SIZE - 2 * MARGIN) / float(widest), float(SIZE - 2 * MARGIN) / float(bottom - top))
		var dir: String = args[1] + "/" + ROWS[r]
		DirAccess.make_dir_recursive_absolute(dir)
		for i in COLS:
			var f: Dictionary = cells[r][i]
			var box: Rect2i = f.box
			var piece := Image.create(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
			for y in box.size.y:
				for x in box.size.x:
					if f.keep[y * box.size.x + x] == 1:
						piece.set_pixel(x, y, img.get_pixel(box.position.x + x, box.position.y + y))
			var fit := Vector2i(maxi(1, roundi(box.size.x * scale)), maxi(1, roundi(box.size.y * scale)))
			piece.resize(fit.x, fit.y, Image.INTERPOLATE_LANCZOS)
			var canvas := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
			var at := Vector2i((SIZE - fit.x) / 2, MARGIN + roundi((box.position.y - top) * scale))
			canvas.blend_rect(piece, Rect2i(Vector2i.ZERO, fit), at)
			canvas.save_png("%s/%02d.png" % [dir, i + 1])
		print(ROWS[r], ": ", COLS, " frames, scale ", snappedf(scale, 0.001))
	quit()

## The figure in `cell`: its biggest blob plus blobs of >= 10 % of it.
## {box (sheet coordinates), keep (1 per kept pixel over the box)}.
func figure(data: PackedByteArray, w: int, cell: Rect2i) -> Dictionary:
	var cw := cell.size.x; var ch := cell.size.y
	var label := PackedInt32Array(); label.resize(cw * ch); label.fill(-1)
	var limit := int(ALPHA * 255.0)
	var blobs := []
	for s in cw * ch:
		if label[s] >= 0 or data[((s / cw + cell.position.y) * w + s % cw + cell.position.x) * 4 + 3] <= limit: continue
		var id := blobs.size()
		label[s] = id
		var stack := PackedInt32Array([s])
		var n := 0
		var bx0 := s % cw; var bx1 := bx0; var by0 := s / cw; var by1 := by0
		while not stack.is_empty():
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			n += 1
			var x := i % cw; var y := i / cw
			bx0 = mini(bx0, x); bx1 = maxi(bx1, x); by0 = mini(by0, y); by1 = maxi(by1, y)
			for j in [i - 1 if x > 0 else -1, i + 1 if x < cw - 1 else -1, i - cw if y > 0 else -1, i + cw if y < ch - 1 else -1]:
				if j < 0 or label[j] >= 0 or data[((j / cw + cell.position.y) * w + j % cw + cell.position.x) * 4 + 3] <= limit: continue
				label[j] = id
				stack.append(j)
		blobs.append({"id": id, "n": n, "box": Rect2i(bx0, by0, bx1 - bx0 + 1, by1 - by0 + 1)})
	var biggest := 0
	for b in blobs: biggest = maxi(biggest, b.n)
	var ids := []
	var box := Rect2i()
	for b in blobs:
		if b.n >= biggest * 0.1:
			ids.append(b.id)
			box = b.box if box.size == Vector2i.ZERO else box.merge(b.box)
	var keep := PackedByteArray(); keep.resize(box.size.x * box.size.y)
	for y in box.size.y:
		for x in box.size.x:
			if ids.has(label[(box.position.y + y) * cw + box.position.x + x]): keep[y * box.size.x + x] = 1
	if box.position.y == 0:
		# Joined to the figure above: drop top rows narrower than a quarter of it.
		var trim := 0
		while trim < box.size.y / 4:
			var n := 0
			for x in box.size.x: n += keep[trim * box.size.x + x]
			if n >= box.size.x / 4: break
			trim += 1
		if trim > 0:
			keep = keep.slice(trim * box.size.x)
			box = Rect2i(box.position + Vector2i(0, trim), box.size - Vector2i(0, trim))
	return {"box": Rect2i(box.position + cell.position, box.size), "keep": keep}

## Flat background -> alpha. A flood from the border walks through the
## background colour and through drop shadows (darker, same hue); pixels next
## to it that differ more (anti-aliased edges, the dark outline) join the matte
## without spreading. Matted pixels are un-composited from the background:
## darker ones become translucent shade, brighter ones a soft edge.
func matte(img: Image) -> void:
	var w := img.get_width(); var h := img.get_height()
	var bg := img.get_pixel(0, 0)
	var data := img.get_data()
	var state := PackedByteArray(); state.resize(w * h)  # 1 = matted
	var todo := PackedInt32Array()
	for x in w:
		todo.append(x); todo.append((h - 1) * w + x)
	for y in h:
		todo.append(y * w); todo.append(y * w + w - 1)
	var luma_bg := bg.get_luminance()
	while not todo.is_empty():
		var i: int = todo[todo.size() - 1]
		todo.resize(todo.size() - 1)
		if state[i] == 1:
			continue
		var c := Color8(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
		var d := Vector3(c.r - bg.r, c.g - bg.g, c.b - bg.b).length()
		var luma := c.get_luminance()
		var hue_gap := absf(wrapf(c.h - bg.h, -0.5, 0.5))
		var spread := d < BG_NEAR or (luma < luma_bg and luma > SHADE_MIN and hue_gap < 0.06 and c.s < SHADE_SAT)
		if not spread and d > BG_EDGE and luma >= luma_bg:
			continue
		state[i] = 1
		if not spread:
			continue
		var x := i % w
		if x > 0: todo.append(i - 1)
		if x < w - 1: todo.append(i + 1)
		if i >= w: todo.append(i - w)
		if i < w * (h - 1): todo.append(i + w)
	for i in w * h:
		if state[i] == 0:
			continue
		var c := Color8(data[i * 4], data[i * 4 + 1], data[i * 4 + 2])
		var d := Vector3(c.r - bg.r, c.g - bg.g, c.b - bg.b).length()
		var a := 0.0
		if d >= BG_NEAR:
			var luma := c.get_luminance()
			a = clampf((luma_bg - luma) / luma_bg * 1.3, 0.0, 1.0) if luma < luma_bg else clampf(d / 0.45, 0.0, 1.0)
		var out := Color(0, 0, 0, 0)
		if a > 0.02:
			out = Color(clampf((c.r - bg.r * (1.0 - a)) / a, 0.0, 1.0), clampf((c.g - bg.g * (1.0 - a)) / a, 0.0, 1.0), clampf((c.b - bg.b * (1.0 - a)) / a, 0.0, 1.0), a)
		data[i * 4] = roundi(out.r * 255.0); data[i * 4 + 1] = roundi(out.g * 255.0)
		data[i * 4 + 2] = roundi(out.b * 255.0); data[i * 4 + 3] = roundi(out.a * 255.0)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
