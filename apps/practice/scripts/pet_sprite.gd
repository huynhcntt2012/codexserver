extends AnimatedSprite2D
## A pet skin in a round, child of a fighter's holder: the owner rides it. The
## pet walks under the owner, faces the same way, and is shown only while it is
## ridden (rounds start mounted; Q gets off, a hit it absorbs knocks it away).
## Feet and seat come from where the art sits in each row of frames
## (Cosmetics.pet_bounds), so every pet and direction lines up the same way.
## Purely visual: the mount rules live in battle_items.gd (practice) and the
## arena (online).

const Cosmetics = preload("res://scripts/cosmetics.gd")
const PET_HEIGHT := 44.0  # standing pet (idle art), in arena pixels; a tile is 64
const FEET := 28.0  # pet's feet below the holder's centre
const RIDER_SCALE := 0.82
## Rider's seat, as a share of the pet art's height from its top: behind the
## head seen from the front, on the saddle from the back and the sides.
const SEAT := {"idle": 0.52, "down": 0.52, "up": 0.42, "left": 0.44, "right": 0.44}
const RIDER_BOTTOM := 32.0  # rider frames sit on the bottom of their 64 px canvas

var hero: AnimatedSprite2D
var mounted := false
var facing := "down"
var size_scale := 1.0


## Shows the pet of `pet_id` under `holder`, replacing any earlier one; null
## (and no pet) when the id is empty or the item has no pet art.
static func attach(holder: Node2D, hero_sprite: AnimatedSprite2D, pet_id: String) -> AnimatedSprite2D:
	var old := holder.get_node_or_null("Pet")
	if old:
		old.name = "PetGone"
		old.queue_free()
	var frames := Cosmetics.pet_frames(Cosmetics.item_art(pet_id))
	if frames == null:
		return null
	var pet: AnimatedSprite2D = load("res://scripts/pet_sprite.gd").new()
	pet.name = "Pet"
	pet.sprite_frames = frames
	pet.hero = hero_sprite
	pet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pet.size_scale = PET_HEIGHT / maxf(1.0, Cosmetics.pet_bounds(frames, "idle").size.y)
	pet.scale = Vector2.ONE * pet.size_scale
	pet.visible = false
	holder.add_child(pet)
	holder.move_child(pet, maxi(0, hero_sprite.get_index()))
	pet.play("idle")
	return pet


func _process(delta: float) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	var anim := str(hero.pose)
	if anim.begins_with("walk_"):
		facing = anim.substr(5)
	var riding := mounted and anim != "lose"
	visible = riding
	hero.ride(riding)
	var rise := 0.0
	var rider_scale := 1.0
	if riding:
		var walking := hero.is_playing() and anim.begins_with("walk_")
		var next := "walk_" + facing if walking else "idle"
		if animation != next or not is_playing():
			play(next)
		# The head faces the camera when walking down or standing: in front of the rider.
		z_index = 1 if next == "idle" or facing == "down" else 0
		# Stand the art on the feet line, centred, whatever its place in the frame.
		var art := Cosmetics.pet_bounds(sprite_frames, next)
		var half := sprite_frames.get_frame_texture(next, 0).get_size() * 0.5
		position = Vector2(half.x - art.get_center().x, FEET / size_scale + half.y - art.end.y) * size_scale
		var seat_share: float = SEAT["idle" if next == "idle" else facing]
		var seat := position.y + (art.position.y - half.y + seat_share * art.size.y) * size_scale
		rider_scale = RIDER_SCALE
		rise = RIDER_BOTTOM * RIDER_SCALE - seat
	hero.scale = hero.scale.lerp(Vector2.ONE * rider_scale, minf(1.0, delta * 14.0))
	hero.position.y = lerpf(hero.position.y, -rise, minf(1.0, delta * 14.0))


func _exit_tree() -> void:
	if hero and is_instance_valid(hero):
		hero.position.y = 0.0
		hero.scale = Vector2.ONE
		hero.ride(false)
