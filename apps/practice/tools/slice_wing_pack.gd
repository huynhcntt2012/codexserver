extends SceneTree
## Cuts the owner-supplied "Modular Wing Pack" sheet into assets/cosmetics:
## halos/<set>.png and wings/<set>/{idle,flap}/01-04.png. The sheet's panels are
## nearly transparent, so alpha alone separates the art from its frame.
## Usage: godot --headless --script tools/slice_wing_pack.gd -- \
##   tools/source/modular_wing_pack.webp "$PWD/assets/cosmetics"
const COLS = [[8,113],[119,225],[231,337],[341,447],[452,557],[563,669]]
const NAMES = ["blue_angel", "pink_heart", "red_flame", "golden_light", "green_nature", "white_classic"]
const HALO = [115, 170]
const IDLE = [[396,438],[438,479],[479,519],[519,561]]
const FLAP = [[592,645],[645,699],[699,751],[751,803]]

func cut(img: Image, x0: int, x1: int, y0: int, y1: int) -> Image:
	var out := Image.create(x1 - x0, y1 - y0, false, Image.FORMAT_RGBA8)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := img.get_pixel(x, y)
			c.a = clampf((c.a - 0.3) / 0.55, 0.0, 1.0)
			if c.a <= 0.0: c = Color(0, 0, 0, 0)
			out.set_pixel(x - x0, y - y0, c)
	return clean(out)

## Drops fragments of neighbouring frames: components touching the top or bottom
## edge that are much smaller than the main sprite.
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
			if y == 0 or y == h - 1: touches = true
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
		if id >= 0 and edge[id] and sizes[id] < biggest * 0.15:
			img.set_pixel(i % w, i / w, Color(0, 0, 0, 0))
	return img

func _init():
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	img.convert(Image.FORMAT_RGBA8)
	var root: String = args[1]
	for c in COLS.size():
		var x0: int = COLS[c][0] + 5
		var x1: int = COLS[c][1] - 5
		var name: String = NAMES[c]
		DirAccess.make_dir_recursive_absolute("%s/wings/%s/idle" % [root, name])
		DirAccess.make_dir_recursive_absolute("%s/wings/%s/flap" % [root, name])
		DirAccess.make_dir_recursive_absolute("%s/halos" % root)
		cut(img, x0, x1, HALO[0], HALO[1]).save_png("%s/halos/%s.png" % [root, name])
		for i in 4:
			cut(img, x0, x1, IDLE[i][0], IDLE[i][1]).save_png("%s/wings/%s/idle/%02d.png" % [root, name, i + 1])
			cut(img, x0, x1, FLAP[i][0], FLAP[i][1]).save_png("%s/wings/%s/flap/%02d.png" % [root, name, i + 1])
	quit()
