extends RefCounted
## Animated hero portraits: assets/characters/portraits/<hero>/01..06.png, an idle
## loop (stand, laugh, stand, wink, giggle, stand) cut by tools/slice_hero_portraits.gd.
## One shared AnimatedTexture per hero, so every portrait of a hero moves together
## and costs nothing per node; the still <hero>.png if the frames are missing.
const ROOT := "res://assets/characters/portraits/"
const FRAMES := 6
const HOLD := [1.0, 0.35, 0.5, 0.45, 0.3, 0.5]  # seconds per frame (stand longest)

static var cache := {}

static func texture(hero: String) -> Texture2D:
	if cache.has(hero):
		return cache[hero]
	var value: Texture2D = null
	if ResourceLoader.exists("%s%s/%02d.png" % [ROOT, hero, FRAMES]):
		var anim := AnimatedTexture.new()
		anim.frames = FRAMES
		for i in FRAMES:
			anim.set_frame_texture(i, load("%s%s/%02d.png" % [ROOT, hero, i + 1]))
			anim.set_frame_duration(i, HOLD[i])
		value = anim
	elif ResourceLoader.exists(ROOT + hero + ".png"):
		value = load(ROOT + hero + ".png")
	cache[hero] = value
	return value

## Pet icons (res://assets/cosmetics/pets/<pet>/idle/01.png) walk in place facing
## the viewer, like the pet under a hero in the lobby and shop previews.
const PETS := "res://assets/cosmetics/pets/"
const PET_FRAMES := 4
const PET_FPS := 7.0  # HeroPreview.PET_WALK_FPS

static func pet_texture(pet: String) -> Texture2D:
	var key := "pet:" + pet
	if cache.has(key):
		return cache[key]
	var value: Texture2D = null
	if ResourceLoader.exists("%s%s/walk_down/%02d.png" % [PETS, pet, PET_FRAMES]):
		var anim := AnimatedTexture.new()
		anim.frames = PET_FRAMES
		for i in PET_FRAMES:
			anim.set_frame_texture(i, load("%s%s/walk_down/%02d.png" % [PETS, pet, i + 1]))
			anim.set_frame_duration(i, 1.0 / PET_FPS)
		value = anim
	cache[key] = value
	return value

## The animation for a still icon path: a hero portrait
## (res://.../portraits/<hero>.png) or a pet icon (.../pets/<pet>/idle/01.png); else null.
static func for_path(path: String) -> Texture2D:
	if path.begins_with(PETS) and path.ends_with("/idle/01.png"):
		return pet_texture(path.trim_prefix(PETS).get_slice("/", 0))
	if not path.begins_with(ROOT) or not path.ends_with(".png") or path.get_base_dir() + "/" != ROOT:
		return null
	return texture(path.get_file().get_basename())
