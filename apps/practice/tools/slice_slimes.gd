extends SceneTree
## Cuts the slime boss art from the owner-supplied minion frame sheet
## (tools/source/slime_minion_frames.webp, transparent, 2 x 4 rows of 4 frames:
## move, idle, cast, burst) into assets/boss/<set>/<anim>/01.png:
## - slime_king: the crowned row (row 3, right half), the boss itself;
## - mini_bomb: "Mini Slime Bomb" (row 1, left), thrown at hit telegraphs;
## - sticky: "Sticky Slime" (row 2, left), thrown at Block Lane cells.
## Slivers of neighbouring frames are dropped (blobs touching the frame edge,
## much smaller than the slime). A set's frames share one scale and stand on
## the bottom edge of its canvas (the burst is centred).
## Usage: godot --headless --script tools/slice_slimes.gd -- \
##   tools/source/slime_minion_frames.webp "$PWD/assets/boss"
const SETS := {
	"slime_king": {"rows": [420, 640], "size": 320, "idle_width": 300,
		"frames": {"move": [562, 717], "idle": [720, 830], "cast": [830, 934], "defeat": [934, 1125]}},
	"mini_bomb": {"rows": [36, 224], "size": 160, "idle_width": 140,
		"frames": {"move": [0, 158], "idle": [158, 252], "cast": [252, 354], "defeat": [354, 562]}},
	"sticky": {"rows": [268, 428], "size": 160, "idle_width": 140,
		"frames": {"move": [0, 164], "idle": [164, 266], "cast": [266, 380], "defeat": [380, 562]}},
}
var ROW := Vector2i.ZERO  # y range of the row being cut

func cut(img: Image, x0: int, x1: int) -> Image:
	var w := x1 - x0; var h := ROW.y - ROW.x
	var label := PackedInt32Array(); label.resize(w * h); label.fill(-1)
	var sizes := []; var edge := []
	for s in w * h:
		if label[s] >= 0 or img.get_pixel(x0 + s % w, ROW.x + s / w).a < 0.06: continue
		var id := sizes.size(); label[s] = id
		var todo: Array[int] = [s]; var n := 0; var touches := false
		while not todo.is_empty():
			var i: int = todo.pop_back(); n += 1
			var x := i % w; var y := i / w
			if y == 0 or y == h - 1 or x == 0 or x == w - 1: touches = true
			for j in [i - 1, i + 1, i - w, i + w]:
				if j < 0 or j >= w * h or absi(j % w - x) > 1: continue
				if label[j] < 0 and img.get_pixel(x0 + j % w, ROW.x + j / w).a >= 0.06:
					label[j] = id; todo.append(j)
		sizes.append(n); edge.append(touches)
	var biggest := 0
	for n in sizes: biggest = maxi(biggest, n)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for i in w * h:
		var id := label[i]
		if id < 0 or (edge[id] and sizes[id] < biggest * 0.2) or sizes[id] < 12: continue
		out.set_pixel(i % w, i / w, img.get_pixel(x0 + i % w, ROW.x + i / w))
	return out.get_region(out.get_used_rect())

func _init():
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0]); img.convert(Image.FORMAT_RGBA8)
	for set_name in SETS:
		var spec: Dictionary = SETS[set_name]
		ROW = Vector2i(spec.rows[0], spec.rows[1])
		var size: int = spec.size
		var pieces := {}
		for anim in spec.frames:
			pieces[anim] = cut(img, spec.frames[anim][0], spec.frames[anim][1])
		var scale := float(spec.idle_width) / float(pieces.idle.get_width())
		for anim in pieces:
			var piece: Image = pieces[anim]
			var fit := Vector2i(roundi(piece.get_width() * scale), roundi(piece.get_height() * scale))
			var factor := minf(1.0, float(size) / float(maxi(fit.x, fit.y)))
			fit = Vector2i(maxi(1, roundi(fit.x * factor)), maxi(1, roundi(fit.y * factor)))
			piece.resize(fit.x, fit.y, Image.INTERPOLATE_LANCZOS)
			var canvas := Image.create(size, size, false, Image.FORMAT_RGBA8)
			var top := (size - fit.y) / 2 if anim == "defeat" else size - 2 - fit.y
			canvas.blend_rect(piece, Rect2i(Vector2i.ZERO, fit), Vector2i((size - fit.x) / 2, top))
			var folder := "%s/%s/%s" % [args[1], set_name, anim]
			DirAccess.make_dir_recursive_absolute(folder)
			canvas.save_png(folder + "/01.png")
			print(set_name, " ", anim, " ", fit)
	quit()
