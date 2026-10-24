extends SceneTree
## Animated hero portraits: every hero hops through 6 frames of one size, still
## portrait paths resolve to the animation, previews animate, pets stay centred.
const HeroPortrait := preload("res://scripts/hero_portrait.gd")
const HEROES := ["bombo", "kai", "lala", "mimi", "zin"]

var checks := 0
var failed := false

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Loaded after the autoloads (UIState, AuthSession) exist.
	var PcKit = load("res://scripts/ui/pc/pc_kit.gd")
	var HeroPreview = load("res://scripts/ui/hero_preview.gd")
	for hero in HEROES:
		var tex := HeroPortrait.texture(hero)
		check(tex is AnimatedTexture and (tex as AnimatedTexture).frames == 6, "%s: 6-frame animation" % hero)
		if not tex is AnimatedTexture:
			continue
		var anim := tex as AnimatedTexture
		for i in 6:
			check(anim.get_frame_texture(i).get_size() == Vector2(160, 160), "%s %d: 160x160" % [hero, i + 1])
		check(HeroPortrait.texture(hero) == tex, "%s: one shared texture" % hero)
		var path := "res://assets/characters/portraits/%s.png" % hero
		check(HeroPortrait.for_path(path) == tex and PcKit.icon_texture(path) == tex, "%s: still path resolves to the animation" % hero)
		check(root.get_node("CatalogSync").texture(path) == tex, "%s: catalog resolver animates" % hero)
	check(HeroPortrait.for_path("res://assets/items/heart.png") == null, "Other art is untouched")
	var preview: Control = HeroPreview.new()
	root.add_child(preview)
	preview.show_hero("mimi", {})
	check(preview.portrait is AnimatedTexture and preview.is_processing(), "Plain preview hops")
	var sync = root.get_node("CatalogSync")
	# Pets walk in place: in every frame the art's centre is the frame's centre
	# (the sheets drifted sideways, which made previews slide left and right).
	var pets := "res://assets/cosmetics/pets"
	for pet in DirAccess.get_directories_at(pets):
		for anim in ["idle", "walk_down", "walk_up", "walk_left", "walk_right"]:
			for k in range(1, 5):
				var img := (load("%s/%s/%s/%02d.png" % [pets, pet, anim, k]) as Texture2D).get_image()
				img.decompress()
				var sum := 0.0
				var weight := 0.0
				for y in range(0, img.get_height(), 2):
					for x in img.get_width():
						var alpha := img.get_pixel(x, y).a
						sum += x * alpha
						weight += alpha
				var cx := sum / maxf(weight, 1.0)
				check(absf(cx - img.get_width() * 0.5) < 2.0, "%s %s %d: centred (%.1f)" % [pet, anim, k, cx])
	check(HeroPreview.PET_WALK_FPS == HeroPortrait.PET_FPS, "Shop pet icons walk at the preview's pace")
	for pet in DirAccess.get_directories_at(pets):
		var icon := "res://assets/cosmetics/pets/%s/idle/01.png" % pet
		var walk: Texture2D = PcKit.icon_texture(icon)
		check(walk is AnimatedTexture and (walk as AnimatedTexture).get_frame_texture(1) == load("res://assets/cosmetics/pets/%s/walk_down/02.png" % pet), "%s: shop icon walks facing forward" % pet)
	sync.apply([{"id": "pet_dragon", "name": "Rồng Lửa Nhỏ", "category": "pet", "icon": "cosmetics/pets/dragon/idle/01.png", "icon_sha256": "1".repeat(64), "icon_url": "/x"}])
	var dragon: Dictionary = root.get_node("UIState").catalog_by_id.get("pet_dragon", {})
	check(PcKit.icon_texture(str(dragon.get("icon", ""))) == HeroPortrait.pet_texture("dragon"), "Server pet icon walks too (%s)" % dragon.get("icon"))
	# A server outfit whose icon is a hero portrait keeps the bundled animation,
	# not the cached still copy.
	sync.apply([{"id": "outfit_mimi", "name": "Bộ đồ MIMI", "category": "outfit", "icon": "characters/portraits/mimi.png", "icon_sha256": "0".repeat(64), "icon_url": "/x"}])
	var outfit: Dictionary = root.get_node("UIState").catalog_by_id.get("outfit_mimi", {})
	check(str(outfit.get("icon", "")) == "res://assets/characters/portraits/mimi.png", "Outfit icon stays the bundled portrait (%s)" % outfit.get("icon"))
	check(PcKit.icon_texture(str(outfit.get("icon", ""))) == HeroPortrait.texture("mimi"), "Outfit icon animates")
	check(not sync.queue.any(func(q): return q.id == "outfit_mimi"), "No download of a still copy")
	# Dressed / riding previews play too, and the frames really advance on screen.
	preview.show_hero("mimi", {"pet": "pet_rabbit"})
	check(preview.portrait is AnimatedTexture and preview.is_processing(), "Dressed preview animates")
	# (Frames advance on the renderer's clock: only with a display.)
	if DisplayServer.get_name() != "headless":
		var anim := HeroPortrait.texture("bombo") as AnimatedTexture
		var seen := {}
		for i in 30:
			seen[anim.current_frame] = true
			await create_timer(0.1).timeout
		check(seen.size() >= 3, "Frames advance over 3 s (%d seen)" % seen.size())
	if failed:
		quit(1)
		return
	print("HERO_PORTRAIT_OK checks=%d" % checks)
	quit()
