extends AnimatedSprite2D
## Uses six cleaned motion frames per direction; original two pose frames
## remain the source for idle / hit / win / lose / place_bomb / throw_item.

const ACTIONS = [
	"idle", "walk_down", "walk_up", "walk_left", "walk_right",
	"place_bomb", "throw_item", "hit", "win", "lose"
]
const WALK_ACTIONS = ["walk_down", "walk_up", "walk_left", "walk_right"]
var step_phase: float = 0.0


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
	sprite_frames = frameset
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	action("idle")


func _process(delta: float) -> void:
	if animation in WALK_ACTIONS and is_playing():
		step_phase += delta * 20.0
		offset = Vector2(0, -1.5 * abs(sin(step_phase)))
	else:
		offset = offset.lerp(Vector2.ZERO, minf(1.0, delta * 18.0))


func action(name: String) -> void:
	if sprite_frames == null or not sprite_frames.has_animation(name):
		return
	if animation != name or not is_playing():
		play(name)
