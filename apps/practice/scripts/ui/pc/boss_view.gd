extends Node2D
## Boss raid drawing on the online board (docs/BOSS.md). The server decides
## which cells a skill hits and when (boss.casts[].tiles / resolveAt); this only
## shows them: the boss throws a small slime onto every warned cell, the slime
## sits there glowing (the warning) and bursts when the server resolves the hit.
## Nothing here decides a hit.
##
## Art: assets/boss/<asset_pack>/<anim>/01.png when the pack ships with the app,
## else the Slime King (DEFAULT_PACK), else a placeholder silhouette. Thrown
## slimes: assets/boss/mini_bomb (hits) and assets/boss/sticky (Block Lane).

const TILE := 64.0
## Outline colour and symbol per skill, so the warning reads without colour too.
const SKILL_LOOK := {
	"boss_basic_hit": [Color("ff4d6a"), "!"],
	"boss_aoe_mark": [Color("ff7a1a"), "!!"],
	"boss_block_lane": [Color("8a6a4a"), "▣"],
	"boss_wave_push": [Color("3aa6e6"), ""],
	"boss_weak_point": [Color("ffd84d"), "★"],
}
## Which slime the boss throws for a skill (others are drawn as warning tiles).
const THROWN := {"boss_basic_hit": "mini_bomb", "boss_aoe_mark": "mini_bomb", "boss_block_lane": "sticky"}
const ARROWS := {"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}
const DEFAULT_PACK := "slime_king"
const ANIMS := ["idle", "cast", "move", "defeat"]
const FLIGHT_MS := 420.0  # throw time, capped to 45 % of the telegraph
const VOLLEY_MS := 18.0  # delay between two slimes of one throw
const BURST_SECONDS := 0.45
const MINI_WIDTH := 60.0
# Size effect: breath ±6 %, +4 % per phase, +8 % when throwing, squash ±3 %.
const BREATH := 0.06
const PHASE_GROW := 0.04
const KICK := 0.08
const SQUASH := 0.03
## Largest possible size: art never leaves the 3x3 footprint, even at its peak.
const PEAK := (1.0 + PHASE_GROW * 2.0) * (1.0 + BREATH + KICK) * (1.0 + SQUASH)

var boss: Dictionary = {}
var now := 0.0
var clock := 0.0
var flash := 0.0
var lunge := 0.0  # seconds left of the phase-change dash frame
var throw_kick := 0.0  # seconds left of the throw puff
var defeat_time := -1.0  # seconds since the boss was defeated (-1 = alive)
const POP_SECONDS := 0.55  # the body swells and flashes before it bursts
var last_hp := -1
var last_phase := 0
var pack_name := ""
var textures: Dictionary = {}  # boss anim -> Texture2D
var minis: Dictionary = {}  # "mini_bomb" / "sticky" -> {anim -> Texture2D}
var casts_seen: Dictionary = {}  # cast id -> cast, to burst it when it resolves
var bursts: Array = []  # {kind, tiles, left}
## The boss texture in use (null = placeholder silhouette).
var art: Texture2D

func _init() -> void:
	for kind in ["mini_bomb", "sticky"]:
		minis[kind] = load_pack(kind)

func show_boss(data: Dictionary, server_now: float) -> void:
	var pack := str(data.get("assetPack", ""))
	if pack != pack_name:
		pack_name = pack
		textures = load_pack(pack)
		if textures.is_empty():
			textures = load_pack(DEFAULT_PACK)
		art = textures.get("idle")
	var hp := int(data.get("hp", 0))
	if last_hp >= 0 and hp < last_hp:
		flash = 0.25
	var defeated := hp <= 0 and int(data.get("maxHp", 0)) > 0
	if defeated and defeat_time < 0.0:
		defeat_time = 0.0
	elif not defeated:
		defeat_time = -1.0
	last_hp = hp
	var phase := int(data.get("phase", 1))
	if last_phase and phase > last_phase:
		lunge = 0.7
	last_phase = phase
	# New casts: the boss throws; casts gone from the snapshot have resolved.
	var current := {}
	for cast in data.get("casts", []):
		current[int(cast.id)] = cast
		if not casts_seen.has(int(cast.id)) and THROWN.has(str(cast.skill)):
			throw_kick = 0.35
	for id in casts_seen:
		if not current.has(id):
			var gone: Dictionary = casts_seen[id]
			if THROWN.has(str(gone.skill)):
				bursts.append({"kind": THROWN[str(gone.skill)], "tiles": gone.tiles, "left": BURST_SECONDS})
	casts_seen = current
	boss = data
	now = server_now
	queue_redraw()

## Art pack: assets/boss/<pack>/<anim>/01.png for idle (required), cast, move, defeat.
static func load_pack(pack: String) -> Dictionary:
	var out := {}
	if pack == "":
		return out
	for anim in ANIMS:
		var path := "res://assets/boss/%s/%s/01.png" % [pack, anim]
		if ResourceLoader.exists(path):
			out[anim] = load(path)
	return out if out.has("idle") else {}

func _process(delta: float) -> void:
	clock += delta
	flash = maxf(0.0, flash - delta)
	lunge = maxf(0.0, lunge - delta)
	throw_kick = maxf(0.0, throw_kick - delta)
	if defeat_time >= 0.0:
		defeat_time += delta
	for burst in bursts:
		burst.left -= delta
	bursts = bursts.filter(func(b): return b.left > 0.0)
	now += delta * 1000.0  # between 20 Hz snapshots
	if not boss.is_empty():
		queue_redraw()

func current_anim() -> String:
	if int(boss.get("hp", 1)) <= 0 and int(boss.get("maxHp", 0)) > 0 and textures.has("defeat"):
		return "defeat"
	if lunge > 0.0 and textures.has("move"):
		return "move"
	if not boss.get("casts", []).is_empty() and textures.has("cast"):
		return "cast"
	return "idle"

## Boss size: breathes between small and big, grows each phase, puffs up when
## it throws; 1.0 = the footprint width at the biggest moment (PEAK).
func size_factor() -> float:
	var phase := int(boss.get("phase", 1))
	var breath := 1.0 + BREATH * sin(clock * 3.2)
	var kick := KICK * sin(PI * throw_kick / 0.35) if throw_kick > 0.0 else 0.0
	return (1.0 + PHASE_GROW * (phase - 1)) * (breath + kick) / PEAK

## Width and height of the boss art now, never larger than the footprint.
func art_size(tex: Texture2D, anim: String) -> Vector2:
	var side := footprint().size.x
	var squash := SQUASH * sin(clock * 6.4) if anim == "idle" else 0.0
	var grow := size_factor()
	if anim == "move":
		squash = -0.06  # stretched sideways, as if dashing
	elif anim == "defeat":
		# Swells to the full footprint, then is gone (the burst takes over).
		var t := clampf(maxf(0.0, defeat_time) / POP_SECONDS, 0.0, 1.0)
		grow = lerpf(size_factor(), 1.0 / (1.0 + SQUASH), t)
		squash = 0.0
	var width := side * grow * (1.0 + squash)
	var height := width * tex.get_height() / tex.get_width() * (1.0 - 2.0 * squash)
	return Vector2(width, height).min(Vector2(side, side))

func footprint() -> Rect2:
	var size := float(boss.get("size", 3)) * TILE
	return Rect2(Vector2(float(boss.get("x", 0)), float(boss.get("y", 0))) * TILE, Vector2(size, size))

func throws_slimes(cast: Dictionary) -> bool:
	return THROWN.has(str(cast.skill)) and not minis.get(THROWN[str(cast.skill)], {}).is_empty()

func _draw() -> void:
	if boss.is_empty():
		return
	for cast in boss.get("casts", []):
		if throws_slimes(cast):
			draw_marks(cast)
		else:
			draw_cast(cast)
	draw_boss()
	for cast in boss.get("casts", []):
		if throws_slimes(cast):
			draw_thrown(cast)
	for burst in bursts:
		draw_burst(burst)

## Thin pulsing outline on each warned cell, under the slime that lands there.
func draw_marks(cast: Dictionary) -> void:
	var look: Array = SKILL_LOOK.get(str(cast.skill), [Color("ff4d6a"), "!"])
	var pulse := 0.5 + 0.5 * sin(clock * 12.0)
	for t in cast.get("tiles", []):
		var cell := Rect2(Vector2(float(t[0]), float(t[1])) * TILE, Vector2(TILE, TILE)).grow(-4)
		draw_rect(cell, Color(look[0], 0.12 + 0.12 * pulse))
		draw_rect(cell, Color(look[0], 0.8), false, 2.0)

## Each slime flies from the boss to its cell on an arc, then sits and glows.
func draw_thrown(cast: Dictionary) -> void:
	var frames: Dictionary = minis[THROWN[str(cast.skill)]]
	var span := maxf(1.0, float(cast.resolveAt) - float(cast.castAt))
	var flight := minf(FLIGHT_MS, span * 0.45)
	var origin := footprint().get_center() + Vector2(0, -TILE * 0.6)
	var tiles: Array = cast.get("tiles", [])
	for i in tiles.size():
		var t = tiles[i]
		var target := Vector2(float(t[0]) + 0.5, float(t[1]) + 0.5) * TILE
		var start := float(cast.castAt) + minf(i * VOLLEY_MS, span * 0.2)
		if now < start:
			continue
		var p := clampf((now - start) / flight, 0.0, 1.0)
		var tex: Texture2D
		var pos: Vector2
		var width := MINI_WIDTH
		if p < 1.0:
			tex = frames.get("move", frames.idle)
			var height := 70.0 + origin.distance_to(target) * 0.25
			pos = origin.lerp(target, p) + Vector2(0, -height * 4.0 * p * (1.0 - p))
			width *= 0.75 + 0.25 * p
			draw_sprite(tex, pos, width, false)
		else:
			# Blinks, then glows steadily as the hit comes closer.
			var close := clampf((now - start - flight) / maxf(1.0, float(cast.resolveAt) - start - flight), 0.0, 1.0)
			tex = frames.get("cast", frames.idle) if close > 0.35 or int(clock * 6.0) % 2 == 0 else frames.idle
			pos = target + Vector2(0, TILE * 0.42)
			width *= 1.0 + 0.12 * close + 0.04 * sin(clock * 14.0)
			draw_sprite(tex, pos, width, true)

func draw_burst(burst: Dictionary) -> void:
	var frames: Dictionary = minis.get(str(burst.kind), {})
	var tex: Texture2D = frames.get("defeat", frames.get("idle"))
	if tex == null:
		return
	var grow: float = 1.0 - burst.left / BURST_SECONDS
	var alpha: float = clampf(burst.left / BURST_SECONDS * 1.6, 0.0, 1.0)
	for t in burst.tiles:
		var centre := Vector2(float(t[0]) + 0.5, float(t[1]) + 0.5) * TILE
		draw_sprite(tex, centre, TILE * (1.0 + 0.4 * grow), false, Color(1, 1, 1, alpha))

## Texture `width` px wide; `feet` puts its bottom edge at `pos` (else centred).
func draw_sprite(tex: Texture2D, pos: Vector2, width: float, feet: bool, tint := Color.WHITE) -> void:
	var extent := Vector2(width, width * tex.get_height() / tex.get_width())
	var top_left := pos - Vector2(extent.x * 0.5, extent.y if feet else extent.y * 0.5)
	draw_texture_rect(tex, Rect2(top_left, extent), false, tint)

## Warning tiles (Wave Push, weak point, or when no slime art ships).
func draw_cast(cast: Dictionary) -> void:
	var look: Array = SKILL_LOOK.get(str(cast.skill), [Color("ff4d6a"), "!"])
	var tint: Color = look[0]
	var span := maxf(1.0, float(cast.resolveAt) - float(cast.castAt))
	var progress := clampf((now - float(cast.castAt)) / span, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(clock * 12.0)
	var font := ThemeDB.fallback_font
	for t in cast.get("tiles", []):
		var cell := Rect2(Vector2(float(t[0]), float(t[1])) * TILE, Vector2(TILE, TILE)).grow(-3)
		draw_rect(cell, Color(tint, 0.22 + 0.18 * pulse))
		# Diagonal hatching: the warning is visible without colour.
		for i in range(-2, 4):
			var a := cell.position + Vector2(i * 16.0, 0)
			var b := a + Vector2(cell.size.y, cell.size.y)
			draw_line(a.clamp(cell.position, cell.end), b.clamp(cell.position, cell.end), Color(tint.darkened(0.3), 0.55), 2.0)
		draw_rect(cell, Color(tint, 0.95), false, 3.0)
		var inner := Rect2(cell.get_center(), Vector2.ZERO).grow(cell.size.x * 0.5 * progress)
		draw_rect(inner, Color(tint, 0.35))
		if str(cast.skill) == "boss_wave_push":
			var dir: Vector2 = ARROWS.get(str(cast.get("dir", "right")), Vector2.RIGHT)
			var c := cell.get_center()
			draw_line(c - dir * 18, c + dir * 18, Color.WHITE, 5.0)
			draw_line(c + dir * 18, c + dir * 6 + dir.orthogonal() * 10, Color.WHITE, 5.0)
			draw_line(c + dir * 18, c + dir * 6 - dir.orthogonal() * 10, Color.WHITE, 5.0)
		elif str(look[1]) != "":
			draw_string_outline(font, cell.get_center() + Vector2(-14, 10), str(look[1]), HORIZONTAL_ALIGNMENT_CENTER, 28, 26, 6, Color("1b1030"))
			draw_string(font, cell.get_center() + Vector2(-14, 10), str(look[1]), HORIZONTAL_ALIGNMENT_CENTER, 28, 26, Color.WHITE)

## Red ring at the boss's feet while it casts (same look as the thrown slimes).
func draw_cast_ring(feet: Vector2, width: float) -> void:
	var pulse := 0.5 + 0.5 * sin(clock * 10.0)
	draw_set_transform(feet + Vector2(0, -6), 0.0, Vector2(1.0, 0.32))
	draw_arc(Vector2.ZERO, width * 0.46, 0.0, TAU, 40, Color("ff6b8a", 0.55 + 0.35 * pulse), 9.0)
	draw_arc(Vector2.ZERO, width * 0.40, 0.0, TAU, 40, Color("ffd0dc", 0.5), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Three red strokes above the head while it casts.
func draw_cast_marks(head: Vector2, width: float) -> void:
	var lift := 4.0 * sin(clock * 10.0)
	for i in 3:
		var angle := -PI / 2.0 + (i - 1) * 0.55
		var dir := Vector2.from_angle(angle)
		var start := head + Vector2(0, 10 - lift) + dir * width * 0.06
		draw_line(start, start + dir * width * 0.16, Color("ff4d6a"), 7.0)

## The boss bursts into water and small slimes (the Mini Slime Bomb burst), inside its footprint.
func draw_defeat_burst(rect: Rect2, t: float) -> void:
	if t <= 0.0:
		return
	var p := clampf(t / 0.9, 0.0, 1.0)
	var alpha := 1.0 - clampf((t - 0.9) / 1.2, 0.0, 1.0)
	if alpha <= 0.0:
		return
	var centre := rect.get_center()
	var side := rect.size.x
	draw_circle(centre, side * 0.5 * p, Color(0.7, 0.92, 1.0, 0.45 * alpha * (1.0 - p)))
	var splash: Dictionary = minis.get("mini_bomb", {})
	var tex: Texture2D = splash.get("defeat")
	if tex:
		draw_sprite(tex, centre, side * (0.55 + 0.45 * p), false, Color(1, 1, 1, alpha))

func draw_boss() -> void:
	var rect := footprint()
	var centre := rect.get_center() + Vector2(0, sin(clock * 2.2) * 3.0)
	var weak := bool(boss.get("weak", false))
	var phase := int(boss.get("phase", 1))
	if weak:
		draw_circle(centre, rect.size.x * 0.62 + 4.0 * sin(clock * 8.0), Color("ffd84d", 0.35))
	if not textures.is_empty():
		# One look in every state: the idle Slime King, with effects on top.
		var anim := current_anim()
		var tex: Texture2D = textures.idle
		art = tex
		var extent := art_size(tex, anim)
		var feet := Vector2(rect.get_center().x, rect.end.y)
		var tint := Color(1, 0.55, 0.55) if flash > 0.0 else (Color(1.15, 0.9, 0.9) if phase == 3 else Color.WHITE)
		if anim == "cast":
			draw_cast_ring(feet, extent.x)
			tint = tint * Color(1.0, 0.92 + 0.08 * sin(clock * 14.0), 0.92 + 0.08 * sin(clock * 14.0))
		if anim == "defeat":
			var t := clampf(defeat_time / POP_SECONDS, 0.0, 1.0)
			if t < 1.0:
				# Flashes white faster and faster while it swells.
				var blink := 0.5 + 0.5 * sin(defeat_time * (14.0 + 30.0 * t))
				tint = Color.WHITE.lerp(Color(2.2, 2.2, 2.2), blink * t)
				draw_texture_rect(tex, Rect2(feet - Vector2(extent.x * 0.5, extent.y), extent), false, tint)
			draw_defeat_burst(rect, maxf(0.0, defeat_time - POP_SECONDS * 0.85))
			return
		draw_texture_rect(tex, Rect2(feet - Vector2(extent.x * 0.5, extent.y), extent), false, tint)
		if anim == "cast":
			draw_cast_marks(feet - Vector2(0, extent.y), extent.x)
		return
	# Placeholder silhouette: a round body that darkens each phase, two eyes.
	var body := Color("4a3a78").lerp(Color("8a2a4a"), (phase - 1) / 2.0)
	if flash > 0.0:
		body = body.lerp(Color.WHITE, 0.6)
	var radius := rect.size.x * 0.5
	draw_circle(centre + Vector2(0, radius * 0.25), radius * 0.92, Color(0, 0, 0, 0.25))
	draw_circle(centre, radius * 0.9, body)
	draw_circle(centre + Vector2(-radius * 0.55, -radius * 0.6), radius * 0.28, body)
	draw_circle(centre + Vector2(radius * 0.55, -radius * 0.6), radius * 0.28, body)
	for side in [-1.0, 1.0]:
		var eye := centre + Vector2(side * radius * 0.32, -radius * 0.12)
		draw_circle(eye, radius * 0.17, Color.WHITE)
		draw_circle(eye + Vector2(0, radius * 0.03), radius * 0.08, Color("ff4d6a") if phase == 3 else Color("1b1030"))
	draw_arc(centre + Vector2(0, radius * 0.25), radius * 0.3, 0.2, PI - 0.2, 16, Color("1b1030"), 4.0)
