extends RefCounted
## Wings and halo art for a loadout. Catalog items name their art in "art": a
## folder with idle/ and flap/ frames for wings, one PNG for a halo. Items without
## art (older hats, server-only items) draw nothing, so the hero looks unchanged.
const WING_FPS := {"idle": 6.0, "flap": 12.0}
const WING_FRAMES := 4
static var _wings := {}

static func art_of(loadout: Dictionary, slot: String) -> String:
	var item: Dictionary = UIState.get_item(str(loadout.get(slot, "")))
	return str(item.get("art", ""))

static func wing_frames(folder: String) -> SpriteFrames:
	if folder == "" or not ResourceLoader.exists(folder + "/idle/01.png"):
		return null
	if not _wings.has(folder):
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		for anim in WING_FPS:
			frames.add_animation(anim)
			frames.set_animation_speed(anim, WING_FPS[anim])
			for i in WING_FRAMES:
				frames.add_frame(anim, load("%s/%s/%02d.png" % [folder, anim, i + 1]))
		_wings[folder] = frames
	return _wings[folder]

static func halo_texture(path: String) -> Texture2D:
	return load(path) if path != "" and ResourceLoader.exists(path) else null
