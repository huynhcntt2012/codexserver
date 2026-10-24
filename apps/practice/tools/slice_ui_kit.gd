extends SceneTree
## Cuts the owner-supplied mailbox UI kit (tools/source/ui_kit/*.webp, see
## licenses/UI_KIT_SOURCE.txt) into assets/ui/kit:
## - icon_<name>.png: whole stickers (coin, category tiles, close...), fitted
##   in a 256 canvas, centred;
## - button_<kind>.png: blank pill buttons for StyleBoxTexture. The kit buttons
##   have words baked in, so the left cap is kept, its inner part (where an
##   icon starts) is refilled from the cleanest middle column of the same
##   button, a few of those columns make the stretchable centre and the cap is
##   mirrored for the right side. Recoloured kinds (ghost, lavender, off) are
##   the blue button with a hue / lightness change;
## - glyph_<name>.png: the small icon at the start of a kit button, keyed off
##   that button's own body colour row by row (64 px high).
## Specks (blobs under 2 % of the biggest, 15 % for glyphs) are dropped; no
## pixels are painted.
## Usage: godot --headless --path . --script res://tools/slice_ui_kit.gd -- \
##   tools/source/ui_kit "$PWD/assets/ui/kit"
const ICON := 256
const BUTTON_H := 56
const GLYPH_H := 64
## icon name -> [sheet, x0, y0, x1, y1]
const ICONS := {
	"coin": ["currency", 20, 430, 296, 716],
	"gem": ["currency", 296, 430, 600, 716],
	"bomb": ["currency", 596, 400, 864, 720],
	"star": ["currency", 860, 430, 1140, 716],
	"gift": ["currency", 1140, 400, 1440, 724],
	"close": ["close", 150, 150, 1100, 1100],
	"cat_admin": ["categories", 40, 130, 512, 530],
	"cat_system": ["categories", 516, 130, 932, 536],
	"cat_event": ["categories", 968, 130, 1396, 536],
	"cat_maintenance": ["categories", 60, 570, 484, 980],
	"cat_reward": ["categories", 520, 570, 936, 980],
	"gift_box": ["categories", 984, 590, 1400, 990],
	"mail": ["mail_badge", 30, 120, 1250, 1160],
	"winged_mail": ["winged_mail", 0, 290, 1254, 970],
	"dot_red": ["status", 170, 290, 420, 530],
	"dot_grey": ["status", 600, 290, 846, 530],
	"badge_red": ["status", 996, 250, 1316, 564],
}
## button kind -> [sheet, x0, y0, x1, y1]; glyph name cut from its icon slot.
const BUTTONS := {
	"sky": ["action_buttons", 24, 456, 488, 648, ""],
	"coral": ["action_buttons", 496, 456, 952, 648, "trash"],
	"mint": ["action_buttons", 960, 456, 1424, 648, "gift"],
	"sun": ["tabs", 12, 468, 488, 616, "mail_navy"],
	"tab_sky": ["tabs", 488, 468, 960, 616, "dot"],
	"tab_claimed": ["tabs", 964, 468, 1436, 616, "gift_sky"],
	"read_all": ["bulk_buttons", 28, 424, 720, 668, "mail_white"],
	"claim_all": ["bulk_buttons", 728, 424, 1420, 668, "gift_mint"],
}
## Buttons that only lend their glyph.
const GLYPH_ONLY := ["tab_claimed", "read_all", "claim_all"]

func cut(img: Image, rect: Rect2i, share := 0.02) -> Image:
	rect = rect.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var w := rect.size.x; var h := rect.size.y
	var label := PackedInt32Array(); label.resize(w * h); label.fill(-1)
	var sizes := []
	for s in w * h:
		if label[s] >= 0 or img.get_pixel(rect.position.x + s % w, rect.position.y + s / w).a < 0.08: continue
		var id := sizes.size(); label[s] = id
		var todo: Array[int] = [s]; var n := 0
		while not todo.is_empty():
			var i: int = todo.pop_back(); n += 1
			var x := i % w
			for j in [i - 1, i + 1, i - w, i + w]:
				if j < 0 or j >= w * h or absi(j % w - x) > 1: continue
				if label[j] < 0 and img.get_pixel(rect.position.x + j % w, rect.position.y + j / w).a >= 0.08:
					label[j] = id; todo.append(j)
		sizes.append(n)
	var biggest := 0
	for n in sizes: biggest = maxi(biggest, n)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for i in w * h:
		if label[i] >= 0 and sizes[label[i]] >= biggest * share:
			out.set_pixel(i % w, i / w, img.get_pixel(rect.position.x + i % w, rect.position.y + i / w))
	var used := out.get_used_rect()
	return out.get_region(used) if used.size.x > 0 else out

func fit(piece: Image, side: int) -> Image:
	var factor := float(side - 8) / float(maxi(piece.get_width(), piece.get_height()))
	var size := Vector2i(maxi(1, roundi(piece.get_width() * factor)), maxi(1, roundi(piece.get_height() * factor)))
	piece.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create(side, side, false, Image.FORMAT_RGBA8)
	canvas.blend_rect(piece, Rect2i(Vector2i.ZERO, size), (Vector2i(side, side) - size) / 2)
	return canvas

func diff(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)

## Middle column with the least vertical change: no letters cross it.
func clean_column(piece: Image) -> int:
	var w := piece.get_width(); var h := piece.get_height()
	var best := w / 2; var best_cost := INF
	for x in range(h / 2, w - h / 2):
		var cost := 0.0
		for y in range(1, h):
			cost += diff(piece.get_pixel(x, y), piece.get_pixel(x, y - 1))
		if cost < best_cost:
			best_cost = cost; best = x
	return best

func blank(piece: Image) -> Image:
	var w := piece.get_width(); var h := piece.get_height()
	var cx := clean_column(piece)
	var cap := h / 2
	var mid := 12
	var out := Image.create(cap * 2 + mid, h, false, Image.FORMAT_RGBA8)
	var inner := int(h * 0.28)
	for y in h:
		var refill := y >= int(h * 0.21) and y <= int(h * 0.9)
		var clean := piece.get_pixel(cx, y)
		for x in cap:
			var c := clean if refill and x >= inner else piece.get_pixel(x, y)
			out.set_pixel(x, y, c)
			out.set_pixel(out.get_width() - 1 - x, y, c)
		for x in mid:
			out.set_pixel(cap + x, y, clean)
	var width := roundi(out.get_width() * float(BUTTON_H) / h)
	out.resize(width, BUTTON_H, Image.INTERPOLATE_LANCZOS)
	return out

## The first cluster of columns that differs from the clean column (the icon
## before the words), keyed against that column row by row.
func glyph(piece: Image) -> Image:
	var w := piece.get_width(); var h := piece.get_height()
	var cx := clean_column(piece)
	var busy := []
	for x in w:
		var hits := 0
		if x >= int(h * 0.3) and x < w - int(h * 0.3):
			for y in range(int(h * 0.28), int(h * 0.85)):
				if diff(piece.get_pixel(x, y), piece.get_pixel(cx, y)) > 0.35:
					hits += 1
		busy.append(hits >= 3)
	var x0 := busy.find(true)
	var x1 := x0
	var gap := 0
	while x1 + 1 < w and gap < int(h * 0.06):
		x1 += 1
		gap = 0 if busy[x1] else gap + 1
	x1 -= gap
	var out := Image.create(x1 - x0 + 1, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var clean := piece.get_pixel(cx, y)
		for x in range(x0, x1 + 1):
			var c := piece.get_pixel(x, y)
			var key := clampf((diff(c, clean) - 0.12) / 0.3, 0.0, 1.0)
			if y < int(h * 0.18) or y > int(h * 0.92):
				key = 0.0
			out.set_pixel(x - x0, y, Color(c.r, c.g, c.b, key))
	out = cut(out, Rect2i(Vector2i.ZERO, out.get_size()), 0.15)
	var factor := float(GLYPH_H) / maxf(out.get_width(), out.get_height())
	out.resize(maxi(1, roundi(out.get_width() * factor)), maxi(1, roundi(out.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	return out

## Blue button recoloured: hue shift and a pull towards white or grey.
func recolour(img: Image, hue_shift: float, toward: Color, amount: float, saturation := 1.0) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			var shifted := Color.from_hsv(fposmod(c.h + hue_shift, 1.0), c.s * saturation, c.v, c.a)
			var mixed := shifted.lerp(toward, amount * (0.55 + 0.45 * c.v))
			mixed.a = c.a
			out.set_pixel(x, y, mixed)
	return out

func save(img: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print(path.get_file(), " ", img.get_size())

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source: String = args[0] if args.size() > 0 else "tools/source/ui_kit"
	var out: String = args[1] if args.size() > 1 else ProjectSettings.globalize_path("res://assets/ui/kit")
	var sheets := {}
	for spec in ICONS.values() + BUTTONS.values():
		if not sheets.has(spec[0]):
			sheets[spec[0]] = Image.load_from_file("%s/%s.webp" % [source, spec[0]])
	for name in ICONS:
		var s: Array = ICONS[name]
		save(fit(cut(sheets[s[0]], Rect2i(s[1], s[2], s[3] - s[1], s[4] - s[2])), ICON), "%s/icon_%s.png" % [out, name])
	var made := {}
	for kind in BUTTONS:
		var s: Array = BUTTONS[kind]
		var piece := cut(sheets[s[0]], Rect2i(s[1], s[2], s[3] - s[1], s[4] - s[2]))
		if s[5] != "":
			save(glyph(piece), "%s/glyph_%s.png" % [out, s[5]])
		if kind in GLYPH_ONLY:
			continue
		made[kind] = blank(piece)
		save(made[kind], "%s/button_%s.png" % [out, kind])
	save(recolour(made.sky, 0.12, Color.WHITE, 0.22, 0.75), "%s/button_lavender.png" % out)
	save(recolour(made.sky, 0.0, Color.WHITE, 0.78, 0.7), "%s/button_ghost.png" % out)
	save(recolour(made.sky, 0.0, Color("c3cfe0"), 0.55, 0.15), "%s/button_off.png" % out)
	quit()
