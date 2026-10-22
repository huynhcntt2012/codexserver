extends Control
## Hero portrait dressed in a loadout: wings behind the body, halo above the head,
## riding its pet (the hero sits behind the pet's head, as in a round).
## The shop passes a try-on loadout so an item can be seen before it is bought.
## Room for the halo is always kept, so the hero does not jump when dressed.
const HeroPortrait := preload("res://scripts/hero_portrait.gd")
const Cosmetics := preload("res://scripts/cosmetics.gd")
const HEADROOM := 0.22  # share of the portrait side kept free above it
const WING_WIDTH := 1.75
const WING_Y := 0.56
const HALO_WIDTH := 0.5
const HALO_Y := -0.01
const WING_SPILL := 0.1  # share of the wing span allowed outside each side
const PET_WIDTH := 0.95  # pet frame width, share of the unmounted portrait side
const RIDER := 0.8  # portrait size while riding, share of the unmounted side
const PET_WALK_FPS := 7.0  # the pet walks in place, a little slower than in a round
const SEAT := 0.05  # rider's bottom above the pet frame centre, share of its width

var hero := ""
var portrait: Texture2D
var wings: SpriteFrames
var halo: Texture2D
var pet: SpriteFrames
var clock := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func show_hero(hero_id: String, loadout: Dictionary) -> void:
	hero = hero_id
	portrait = HeroPortrait.texture(hero_id)
	wings = Cosmetics.wing_frames(Cosmetics.art_of(loadout, "wings"))
	halo = Cosmetics.halo_texture(Cosmetics.art_of(loadout, "hat"))
	pet = Cosmetics.pet_frames(Cosmetics.art_of(loadout, "pet"))
	# The idle portrait loop stays in place, so it plays dressed or riding too.
	set_process(portrait is AnimatedTexture or wings != null or halo != null or pet != null)
	queue_redraw()

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	if portrait == null:
		return
	var rider := RIDER if pet else 1.0
	var below := PET_WIDTH * (0.5 + SEAT) if pet else 0.0
	var full := minf(size.x / (WING_WIDTH * rider * (1.0 - 2.0 * WING_SPILL)), size.y / (rider * (1.0 + HEADROOM) + below))
	var pet_width := full * PET_WIDTH
	var pet_center := Vector2(size.x * 0.5, size.y - pet_width * 0.5)
	var side := full * rider
	var origin := Vector2((size.x - side) * 0.5, pet_center.y - pet_width * SEAT - side if pet else size.y - side)
	if wings:
		var frame := int(clock * Cosmetics.WING_FPS.idle) % Cosmetics.WING_FRAMES
		draw_centered(wings.get_frame_texture("idle", frame), origin + Vector2(side * 0.5, side * WING_Y), side * WING_WIDTH)
	draw_texture_rect(portrait, Rect2(origin, Vector2(side, side)), false)
	if halo:
		var bob := sin(clock * 2.4) * side * 0.015
		draw_centered(halo, origin + Vector2(side * 0.5, side * HALO_Y + bob), side * HALO_WIDTH)
	if pet:
		# Walking in place, facing the viewer.
		var frame := int(clock * PET_WALK_FPS) % Cosmetics.PET_FRAMES
		draw_centered(pet.get_frame_texture("walk_down", frame), pet_center, pet_width)

func draw_centered(texture: Texture2D, center: Vector2, width: float) -> void:
	var extent := Vector2(width, width * texture.get_height() / texture.get_width())
	draw_texture_rect(texture, Rect2(center - extent * 0.5, extent), false)
