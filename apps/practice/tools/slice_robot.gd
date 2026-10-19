extends SceneTree
## Cuts the Clockwork Bomb Robot (Robot Bom Dây Cót) from the owner-supplied
## directional sheet (tools/source/clockwork_bot_directional.webp: transparent,
## 4 x 4 frames; rows walk down, left, right, up) into
## assets/boss/clockwork_bot/walk_<dir>/01..04.png, plus idle/01.png (the first
## frame facing down), the frame the boss view needs to load the pack.
## Specks of the sheet's halo are dropped (blobs much smaller than the robot).
## All frames share one scale and stand on the bottom edge of a 256 x 256 canvas.
## The first run also converts the dev pack PNG into the kept source:
##   godot --headless --script tools/slice_robot.gd -- \
##     <03_robot_boss_directional_original.png | tools/source/clockwork_bot_directional.webp> \
##     "$PWD/assets/boss/clockwork_bot" ["$PWD/tools/source/clockwork_bot_directional.webp"]
const ROWS := ["walk_down", "walk_left", "walk_right", "walk_up"]
const SIZE := 256
const IDLE_WIDTH := 236

## The frame's pixels, without blobs under 3 % of its biggest one.
func cut(img: Image, region: Rect2i) -> Image:
	var w := region.size.x; var h := region.size.y
	var label := PackedInt32Array(); label.resize(w * h); label.fill(-1)
	var sizes := []
	for s in w * h:
		if label[s] >= 0 or img.get_pixel(region.position.x + s % w, region.position.y + s / w).a < 0.1: continue
		var id := sizes.size(); label[s] = id
		var todo: Array[int] = [s]; var n := 0
		while not todo.is_empty():
			var i: int = todo.pop_back(); n += 1
			var x := i % w
			for j in [i - 1, i + 1, i - w, i + w]:
				if j < 0 or j >= w * h or absi(j % w - x) > 1: continue
				if label[j] < 0 and img.get_pixel(region.position.x + j % w, region.position.y + j / w).a >= 0.1:
					label[j] = id; todo.append(j)
		sizes.append(n)
	var biggest := 0
	for n in sizes: biggest = maxi(biggest, n)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for i in w * h:
		var id := label[i]
		if id < 0 or sizes[id] < biggest * 0.03: continue
		out.set_pixel(i % w, i / w, img.get_pixel(region.position.x + i % w, region.position.y + i / w))
	return out.get_region(out.get_used_rect())

func _init():
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0]); img.convert(Image.FORMAT_RGBA8)
	if args.size() > 2:
		img.save_webp(args[2], true, 0.92)
	var cell := Vector2(img.get_width() / 4.0, img.get_height() / 4.0)
	var frames := {}
	for r in ROWS.size():
		for c in 4:
			var region := Rect2i(Vector2i(roundi(c * cell.x), roundi(r * cell.y)), Vector2i(floori(cell.x), floori(cell.y)))
			frames["%s/%02d" % [ROWS[r], c + 1]] = cut(img, region)
	var scale := float(IDLE_WIDTH) / float(frames["walk_down/01"].get_width())
	for name in frames:
		var piece: Image = frames[name]
		var fit := Vector2i(roundi(piece.get_width() * scale), roundi(piece.get_height() * scale))
		var factor := minf(1.0, float(SIZE - 4) / float(maxi(fit.x, fit.y)))
		fit = Vector2i(maxi(1, roundi(fit.x * factor)), maxi(1, roundi(fit.y * factor)))
		piece.resize(fit.x, fit.y, Image.INTERPOLATE_LANCZOS)
		var canvas := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		canvas.blend_rect(piece, Rect2i(Vector2i.ZERO, fit), Vector2i((SIZE - fit.x) / 2, SIZE - 2 - fit.y))
		var folder := "%s/%s" % [args[1], name.get_base_dir()]
		DirAccess.make_dir_recursive_absolute(folder)
		canvas.save_png("%s/%s.png" % [folder, name.get_file()])
		if name == "walk_down/01":
			DirAccess.make_dir_recursive_absolute(args[1] + "/idle")
			canvas.save_png(args[1] + "/idle/01.png")
		print(name, " ", fit)
	quit()
