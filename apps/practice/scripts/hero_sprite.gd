extends AnimatedSprite2D
## Uses six cleaned motion frames per direction; original two pose frames
## remain the source for idle / hit / win / lose / place_bomb / throw_item.
## dress() adds the loadout's wings (behind the body, in front when walking
## away from the camera) and a floating halo above the head.
## While `riding` (on a pet, see pet_sprite.gd) idle and walking use the sitting
## rider frames in assets/riders/<hero>/ride_* when the hero has them; `pose`
## keeps the action asked for (idle, walk_left, ...) either way.

const Cosmetics = preload("res://scripts/cosmetics.gd")
const ACTIONS = [
	"idle", "walk_down", "walk_up", "walk_left", "walk_right",
	"place_bomb", "throw_item", "hit", "win", "lose"
]
const WALK_ACTIONS = ["walk_down", "walk_up", "walk_left", "walk_right"]
const RIDE = {"idle": "ride_idle", "walk_down": "ride_down", "walk_up": "ride_up", "walk_left": "ride_left", "walk_right": "ride_right"}
const RIDE_FRAMES = [1, 2, 3, 2]
const WING_WIDTH := 72.0
const WING_Y := 4.0
const HALO_WIDTH := 34.0
const HALO_Y := -36.0
var step_phase: float = 0.0
var halo_phase: float = 0.0
var wings: AnimatedSprite2D
var halo: Sprite2D
var pose := "idle"
var riding := false


func configure(hero_id: String) -> void:
	var frameset = SpriteFrames.new()
	frameset.remove_animation("default")
	for action_name in ACTIONS:
		frameset.add_animation(action_name)
		var walking: bool = action_name in WALK_ACTIONS
		frameset.set_animation_speed(action_name, 12.0 if walking else 5.5)
		frameset.set_animation_loop(action_name, walking or action_name == "idle")
		var count: int = 6 if walking else 2
		for index in range(1, count + 1):
			var texture_path: String
			if walking:
				texture_path = "res://assets/animations/%s/%s/%02d.png" % [hero_id, action_name, index]
			else:
				texture_path = "res://assets/characters/%s/%s/%02d.png" % [hero_id, action_name, index]
			frameset.add_frame(action_name, load(texture_path))
	for pose_name in RIDE:
		var ride: String = RIDE[pose_name]
		var folder := "res://assets/riders/%s/%s" % [hero_id, ride]
		if not ResourceLoader.exists(folder + "/01.png"):
			continue
		frameset.add_animation(ride)
		frameset.set_animation_speed(ride, 5.0 if ride == "ride_idle" else 9.0)
		for index in RIDE_FRAMES:
			frameset.add_frame(ride, load("%s/%02d.png" % [folder, index]))
	sprite_frames = frameset
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	action("idle")


## Wears the loadout's wings and halo; an empty loadout removes both.
func dress(loadout: Dictionary) -> void:
	for node in [wings, halo]:
		if node:
			node.queue_free()
	wings = null
	halo = null
	var frames := Cosmetics.wing_frames(Cosmetics.art_of(loadout, "wings"))
	if frames:
		wings = AnimatedSprite2D.new()
		wings.name = "Wings"
		wings.sprite_frames = frames
		wings.position = Vector2(0, WING_Y)
		wings.scale = Vector2.ONE * WING_WIDTH / frames.get_frame_texture("idle", 0).get_width()
		wings.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(wings)
	var texture := Cosmetics.halo_texture(Cosmetics.art_of(loadout, "hat"))
	if texture:
		halo = Sprite2D.new()
		halo.name = "Halo"
		halo.texture = texture
		halo.position = Vector2(0, HALO_Y)
		halo.scale = Vector2.ONE * HALO_WIDTH / texture.get_width()
		halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(halo)
	_wear(animation)


func _process(delta: float) -> void:
	if pose in WALK_ACTIONS and is_playing() and not riding:
		step_phase += delta * 20.0
		offset = Vector2(0, -1.5 * abs(sin(step_phase)))
	else:
		offset = offset.lerp(Vector2.ZERO, minf(1.0, delta * 18.0))
	if wings:
		wings.offset = offset / wings.scale
	if halo:
		halo_phase += delta * 2.4
		halo.position = Vector2(0, HALO_Y + offset.y + sin(halo_phase) * 1.5)


func action(name: String) -> void:
	if sprite_frames == null or not sprite_frames.has_animation(name):
		return
	pose = name
	var shown: String = RIDE.get(name, name) if riding else name
	if not sprite_frames.has_animation(shown):
		shown = name
	if animation != shown or not is_playing():
		play(shown)
	_wear(name)

## Gets on or off a pet: the current pose switches to / from the rider frames.
func ride(on: bool) -> void:
	if riding == on:
		return
	riding = on
	action(pose)


## Wings flap while walking and sit behind the body except from the back; side
## views squeeze them so they read as seen edge-on.
func _wear(name: String) -> void:
	if wings == null:
		return
	var walking: bool = name in WALK_ACTIONS
	var anim := "flap" if walking else "idle"
	if wings.animation != anim or not wings.is_playing():
		wings.play(anim)
	wings.show_behind_parent = name != "walk_up"
	var width := WING_WIDTH / wings.sprite_frames.get_frame_texture("idle", 0).get_width()
	wings.scale = Vector2(width * (0.7 if name in ["walk_left", "walk_right"] else 1.0), width)
	wings.visible = name != "lose"
