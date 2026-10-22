extends SceneTree
## Cuts the Thunder Ram (Cừu Sấm Sét) from the owner-supplied spec sheets
## (tools/source/*.webp, transparent; spec "Cừu Sấm Sét & Vua Xương Rồng" v1.0,
## pages 10-11). The Cactus King art is the design team's sprite pack (see
## licenses/TWIN_BOSS_SOURCE.txt), copied as is:
## - thunder_ram_move: rows down, left, right, up (RAM_ROWS), 4 frames each;
## - *_skills: skill VFX, cut from the chosen frames below.
## Bodies go to assets/boss/<pack>/walk_<dir>/NN.png and idle/NN.png (one scale
## per boss, standing on the bottom edge of a 256 canvas); VFX to
## assets/boss/<pack>/vfx/<name>.png (fit in 256, centred). Slivers of the
## neighbouring frames (blobs touching the cell's side, much smaller than the
## boss) and specks are dropped; no pixels are painted.
## Usage: godot --headless --path . --script res://tools/slice_twin_bosses.gd -- \
##   tools/source "$PWD/assets/boss"
const SIZE := 256
const BODY_WIDTH := 230  # width of the first down frame on the canvas
const DIRS := ["walk_down", "walk_left", "walk_right", "walk_up"]
const RAM_ROWS := [[20, 322], [322, 614], [614, 906], [906, 1210]]
## VFX: name -> [x0, y0, x1, y1] on the skills sheet.
const RAM_VFX := {
	"dash": [337, 160, 625, 440],
	"impact": [955, 85, 1250, 455],
	"ball": [334, 550, 620, 785],
	"cross": [628, 490, 940, 790],
	"ring": [12, 895, 326, 1145],
	"strike": [328, 835, 634, 1205],
	"leap": [634, 812, 942, 1236],
	"blast": [940, 850, 1250, 1236],
}

## Pixels of `rect`: specks under 2 % of the biggest blob go, and blobs touching
## the cell's edge under 25 % (bits of the neighbouring frames).
func cut(img: Image, rect: Rect2i, clean_sides := true) -> Image:
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var w := rect.size.x; var h := rect.size.y
	var label := PackedInt32Array(); label.resize(w * h); label.fill(-1)
	var sizes := []; var side := []
	for s in w * h:
		if label[s] >= 0 or img.get_pixel(rect.position.x + s % w, rect.position.y + s / w).a < 0.08: continue
		var id := sizes.size(); label[s] = id
		var todo: Array[int] = [s]; var n := 0; var touches := false
		while not todo.is_empty():
			var i: int = todo.pop_back(); n += 1
			var x := i % w; var y := i / w
			if x == 0 or x == w - 1 or y == 0 or y == h - 1: touches = true
			for j in [i - 1, i + 1, i - w, i + w]:
				if j < 0 or j >= w * h or absi(j % w - x) > 1: continue
				if label[j] < 0 and img.get_pixel(rect.position.x + j % w, rect.position.y + j / w).a >= 0.08:
					label[j] = id; todo.append(j)
		sizes.append(n); side.append(touches)
	var biggest := 0
	for n in sizes: biggest = maxi(biggest, n)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for i in w * h:
		var id := label[i]
		if id < 0 or sizes[id] < biggest * 0.02: continue
		if clean_sides and side[id] and sizes[id] < biggest * 0.25: continue
		out.set_pixel(i % w, i / w, img.get_pixel(rect.position.x + i % w, rect.position.y + i / w))
	var used := out.get_used_rect()
	return out.get_region(used) if used.size.x > 0 else out

func place(piece: Image, scale: float, feet: bool) -> Image:
	var fit := Vector2i(roundi(piece.get_width() * scale), roundi(piece.get_height() * scale))
	var factor := minf(1.0, float(SIZE - 4) / float(maxi(fit.x, fit.y)))
	fit = Vector2i(maxi(1, roundi(fit.x * factor)), maxi(1, roundi(fit.y * factor)))
	piece.resize(fit.x, fit.y, Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var top := SIZE - 2 - fit.y if feet else (SIZE - fit.y) / 2
	canvas.blend_rect(piece, Rect2i(Vector2i.ZERO, fit), Vector2i((SIZE - fit.x) / 2, top))
	return canvas

func save(img: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print(path.get_file().get_basename(), " ", path.get_base_dir().get_file())

func bodies(frames: Dictionary, root: String) -> void:
	var scale := float(BODY_WIDTH) / float(frames["walk_down/01"].get_width())
	for name in frames:
		save(place(frames[name], scale, true), "%s/%s.png" % [root, name])

func vfx(img: Image, spec: Dictionary, root: String) -> void:
	for name in spec:
		var r: Array = spec[name]
		var piece := cut(img, Rect2i(r[0], r[1], r[2] - r[0], r[3] - r[1]), false)
		save(place(piece, 1.0e6, false), "%s/vfx/%s.png" % [root, name])

func _init():
	var args := OS.get_cmdline_user_args()
	var src: String = args[0]
	var root: String = args[1]
	var frames := {}
	var ram := Image.load_from_file(src + "/thunder_ram_move.webp"); ram.convert(Image.FORMAT_RGBA8)
	var cell := Vector2(ram.get_width() / 4.0, ram.get_height() / 4.0)
	for r in DIRS.size():
		for c in 4:
			frames["%s/%02d" % [DIRS[r], c + 1]] = cut(ram, Rect2i(roundi(c * cell.x), RAM_ROWS[r][0], floori(cell.x), RAM_ROWS[r][1] - RAM_ROWS[r][0]))
	frames["idle/01"] = frames["walk_down/01"].duplicate()
	bodies(frames, root + "/thunder_ram")
	var ram_skills := Image.load_from_file(src + "/thunder_ram_skills.webp"); ram_skills.convert(Image.FORMAT_RGBA8)
	vfx(ram_skills, RAM_VFX, root + "/thunder_ram")
	quit()
