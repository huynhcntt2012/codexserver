extends RefCounted
## Wings, halo and pet art for a loadout. Catalog items name their art in "art": a
## folder with idle/ and flap/ frames for wings, one PNG for a halo, a folder with
## idle/ and walk_<dir>/ frames for a pet. Items without art (older hats,
## server-only items) draw nothing, so the hero looks unchanged.
const WING_FPS := {"idle": 6.0, "flap": 12.0}
const WING_FRAMES := 4
const PET_ANIMS := ["idle", "walk_down", "walk_up", "walk_left", "walk_right"]
const PET_FPS := {"idle": 5.0, "walk": 10.0}
const PET_FRAMES := 4
static var _wings := {}
static var _pets := {}
static var _bounds := {}  # "<folder>:<anim>" -> Rect2 of the art in its frames

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

## Art folder of a catalog item, e.g. the pet id a snapshot names.
static func item_art(item_id: String) -> String:
	return str(UIState.get_item(item_id).get("art", "")) if item_id != "" else ""

static func pet_frames(folder: String) -> SpriteFrames:
	if folder == "" or not ResourceLoader.exists(folder + "/idle/01.png"):
		return null
	if not _pets.has(folder):
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		for anim in PET_ANIMS:
			frames.add_animation(anim)
			frames.set_animation_speed(anim, PET_FPS.idle if anim == "idle" else PET_FPS.walk)
			for i in PET_FRAMES:
				frames.add_frame(anim, load("%s/%s/%02d.png" % [folder, anim, i + 1]))
		_pets[folder] = frames
	return _pets[folder]

## Where the pet is drawn inside its frames for `anim` (union of all frames, in
## texture pixels): the sheets place each row differently, so riders and feet
## are lined up from this, not from the frame edges.
static func pet_bounds(frames: SpriteFrames, anim: String) -> Rect2:
	var key := "%d:%s" % [frames.get_instance_id(), anim]
	if not _bounds.has(key):
		var box := Rect2i()
		for i in frames.get_frame_count(anim):
			var image := frames.get_frame_texture(anim, i).get_image()
			if image.is_compressed():
				image.decompress()
			var used := image.get_used_rect()
			box = used if box.size == Vector2i.ZERO else box.merge(used)
		_bounds[key] = Rect2(box)
	return _bounds[key]
