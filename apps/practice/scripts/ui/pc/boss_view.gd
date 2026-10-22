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
##
## Robot Bom Dây Cót (pack clockwork_bot, robot_* skills): walk_<dir>/01..04.png
## frames, turned to boss.facing and slid between cells as the server moves it.
## Its bombs (cast.bombs) fly from its back onto their cells and blink until the
## server resolves them; the blast itself is the server's flames. The mini
## chaser (cast.mini) hops after its target; dash lanes get arrows.
##
## Vua Xương Rồng (cactus_king) and Cừu Sấm Sét (thunder_ram) walk like the robot
## (walk_<dir>/NN.png) and their skills use the art in <pack>/vfx: the lane is
## warned (yellow/orange tiles, an outline and a symbol), the boss rolls/charges
## along it, thorns / the thunder ball fly cell by cell, crosses and storms light
## up on their tiles. A trapped raider (boss.trapped) sits in a water bubble with
## its rescue countdown. A banner names the skill 0.6-1.5 s before the hit.

const TILE := 64.0
## Outline colour and symbol per skill, so the warning reads without colour too.
const SKILL_LOOK := {
	"boss_basic_hit": [Color("ff4d6a"), "!"],
	"boss_aoe_mark": [Color("ff7a1a"), "!!"],
	"boss_block_lane": [Color("8a6a4a"), "▣"],
	"boss_wave_push": [Color("3aa6e6"), ""],
	"boss_weak_point": [Color("ffd84d"), "★"],
	"robot_bomb_launch": [Color("ff7a1a"), "!"],
	"robot_bomb_chain": [Color("ff4d6a"), "!"],
	"robot_mini_chaser": [Color("ff4d6a"), "!!"],
	"robot_recoil_dash": [Color("3aa6e6"), ""],
	"robot_magnet_pull": [Color("9a6bff"), "!"],
	"robot_overheat": [Color("ff7a1a"), "!!"],
	"robot_reactor": [Color("ff2d55"), "!!"],
	"cactus_thorn_roll": [Color("ff9a1a"), ""],
	"cactus_thorn_shot": [Color("ffc21a"), "▲"],
	"cactus_thorn_cross": [Color("ff9a1a"), "+"],
	"cactus_thorn_storm": [Color("ff7a1a"), "!!"],
	"ram_thunder_charge": [Color("ffc21a"), ""],
	"ram_thunder_ball": [Color("ffd84d"), "●"],
	"ram_lightning_cross": [Color("ffb21a"), "+"],
	"ram_thunder_storm": [Color("ff9a1a"), "ϟ"],
}
## VFX art per skill (in <pack>/vfx) and where it is drawn: "boss" on the
## moving boss, "fly" on the projectile's cell, "centre" once on the boss for
## a cross, "tiles" on every hit cell.
const TWIN_VFX := {
	"cactus_thorn_roll": ["roll", "boss"],
	"cactus_thorn_shot": ["thorn", "fly"],
	"cactus_thorn_cross": ["cross", "centre"],
	"cactus_thorn_storm": ["storm", "tiles"],
	"ram_thunder_charge": ["dash", "boss"],
	"ram_thunder_ball": ["ball", "fly"],
	"ram_lightning_cross": ["cross", "centre"],
	"ram_thunder_storm": ["strike", "tiles"],
}
const BANNERS := {
	"cactus_thorn_roll": "LĂN GAI", "cactus_thorn_shot": "GAI BAY", "cactus_thorn_cross": "GAI NỔ",
	"cactus_thorn_storm": "BÃO GAI XOÁY", "ram_thunder_charge": "HÚC SẤM", "ram_thunder_ball": "CẦU ĐIỆN",
	"ram_lightning_cross": "ĐIỆN NỔ", "ram_thunder_storm": "BÃO SÉT",
}
const BANNER_SECONDS := 1.2
const IMPACT_SECONDS := 0.45
const TWIN_ART := 1.7  # art width / footprint (spec: ~1.7-2.1 x a hero's height)
const DIRS := ["down", "left", "right", "up"]
const ROBOT_BOMB := "res://assets/bombs/strong_black.png"
const ROBOT_ART := 1.4  # robot art width / footprint width (feet on the footprint)
const BOMB_WIDTH := 46.0
const MINI_STEP := 0.3  # seconds per cell of the mini chaser (server CHASER_STEP_MS)
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
var hold_clock := false  # tests: keep `now` where they set it (screenshots)
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
var walks: Dictionary = {}  # direction -> [Texture2D] (directional packs only)
var idles: Array = []  # idle/NN.png frames (Cactus King has 4)
var bomb_tex: Texture2D
var slide_from := Vector2.ZERO  # footprint top-left in px, sliding to the server cell
var slide_to := Vector2.ZERO
var slide_t := 1.0
var slide_len := 0.2
var minis_at: Dictionary = {}  # cast id -> {from, to, t}
var vfx: Dictionary = {}  # vfx name -> Texture2D (twin bosses)
var series: Dictionary = {}  # design-team sprite pack: "orb", "warning", ... -> [Texture2D] (vfx/<name>_NN.png)
var banner_text := ""
var banner_left := 0.0
var impacts: Array = []  # {tex, tiles, centre, left} short hit flashes
## Set by the online screen: raider id -> its holder node (followed every frame).
var raider_spots: Dictionary = {}
## Node drawn above the raiders (pc_online), for bubbles and the banner.
var overlay: Node2D

func _init() -> void:
	for kind in ["mini_bomb", "sticky"]:
		minis[kind] = load_pack(kind)
	if ResourceLoader.exists(ROBOT_BOMB):
		bomb_tex = load(ROBOT_BOMB)

func show_boss(data: Dictionary, server_now: float) -> void:
	var pack := str(data.get("assetPack", ""))
	if pack != pack_name:
		pack_name = pack
		textures = load_pack(pack)
		walks = load_walks(pack) if not textures.is_empty() else {}
		vfx = load_vfx(pack)
		series = load_series(pack)
		idles = load_idles(pack)
		if textures.is_empty():
			textures = load_pack(DEFAULT_PACK)
		art = textures.get("idle")
	var cell := Vector2(float(data.get("x", 0)), float(data.get("y", 0))) * TILE
	if boss.is_empty():
		slide_from = cell
		slide_to = cell
		slide_t = 1.0
	elif cell != slide_to:
		# One walking step takes walkMs; a dash (several cells) is quick.
		var cells := absf(cell.x - slide_to.x) / TILE + absf(cell.y - slide_to.y) / TILE
		slide_from = drawn_origin()
		slide_to = cell
		slide_t = 0.0
		slide_len = maxf(0.12, float(data.get("walkMs", 0)) / 1000.0) if cells <= 1.0 else 0.22
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
		if not casts_seen.has(int(cast.id)) and BANNERS.has(str(cast.skill)) and int(cast.get("volley", 0)) == 0 and int(cast.get("wave", 1)) <= 1:
			banner_text = BANNERS[str(cast.skill)]
			banner_left = BANNER_SECONDS
		elif not casts_seen.has(int(cast.id)) and cast.get("volley") != null and not _volley_seen(int(cast.volley)):
			banner_text = BANNERS.get(str(cast.skill), "")
			banner_left = BANNER_SECONDS
	for id in casts_seen:
		if not current.has(id):
			var gone: Dictionary = casts_seen[id]
			if THROWN.has(str(gone.skill)):
				bursts.append({"kind": THROWN[str(gone.skill)], "tiles": gone.tiles, "left": BURST_SECONDS})
			elif TWIN_VFX.has(str(gone.skill)):
				twin_impact(gone)
				if TWIN_VFX[str(gone.skill)][1] == "boss":
					# The orb / charge art already carried it to the end cell.
					slide_from = cell
					slide_t = 1.0
	casts_seen = current
	# Mini chasers glide one cell per server step.
	var alive_minis := {}
	for cast in data.get("casts", []):
		if cast.get("mini") == null:
			continue
		var id := int(cast.id)
		alive_minis[id] = true
		var at := (Vector2(float(cast.mini[0]), float(cast.mini[1])) + Vector2(0.5, 0.5)) * TILE
		if not minis_at.has(id):
			minis_at[id] = {"from": at, "to": at, "t": 1.0}
		elif minis_at[id].to != at:
			minis_at[id] = {"from": mini_drawn(minis_at[id]), "to": at, "t": 0.0}
	for id in minis_at.keys():
		if not alive_minis.has(id):
			minis_at.erase(id)
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

## Directional walk frames: assets/boss/<pack>/walk_<dir>/01..NN.png (empty if none).
static func load_walks(pack: String) -> Dictionary:
	var out := {}
	for dir in DIRS:
		var frames := []
		for i in range(1, 9):
			var path := "res://assets/boss/%s/walk_%s/%02d.png" % [pack, dir, i]
			if not ResourceLoader.exists(path):
				break
			frames.append(load(path))
		if not frames.is_empty():
			out[dir] = frames
	return out if out.size() == DIRS.size() else {}

func drawn_origin() -> Vector2:
	return slide_from.lerp(slide_to, clampf(slide_t, 0.0, 1.0))

func mini_drawn(m: Dictionary) -> Vector2:
	return (m.from as Vector2).lerp(m.to, clampf(m.t, 0.0, 1.0))

## The robot is walking (server moved it within its step time) or still sliding.
func walking() -> bool:
	var step := float(boss.get("walkMs", 0))
	return slide_t < 1.0 or (float(boss.get("movedAt", 0)) > 0.0 and now - float(boss.get("movedAt", 0)) < step + 120.0)

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
	slide_t = minf(1.0, slide_t + delta / maxf(0.05, slide_len))
	banner_left = maxf(0.0, banner_left - delta)
	for hit in impacts:
		hit.left -= delta
	impacts = impacts.filter(func(h): return h.left > 0.0)
	for id in minis_at:
		minis_at[id].t = minf(1.0, minis_at[id].t + delta / MINI_STEP)
	if not hold_clock:
		now += delta * 1000.0  # between 20 Hz snapshots
	if not boss.is_empty():
		queue_redraw()
		if overlay:
			overlay.queue_redraw()

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
	return Rect2(drawn_origin(), Vector2(size, size))

func throws_slimes(cast: Dictionary) -> bool:
	return THROWN.has(str(cast.skill)) and not minis.get(THROWN[str(cast.skill)], {}).is_empty()

func _draw() -> void:
	if boss.is_empty():
		return
	for cast in boss.get("casts", []):
		if throws_slimes(cast):
			draw_marks(cast)
		elif not cast.get("tiles", []).is_empty():
			draw_cast(cast)
	if not walks.is_empty():
		draw_robot()
	else:
		draw_boss()
	for cast in boss.get("casts", []):
		if throws_slimes(cast):
			draw_thrown(cast)
		elif cast.get("mini") != null:
			draw_mini(cast)
		elif cast.get("bombs") != null:
			draw_bombs(cast)
		if str(cast.skill) == "robot_magnet_pull":
			draw_magnet(cast)
	for burst in bursts:
		draw_burst(burst)
	if not vfx.is_empty() or not series.is_empty():
		for cast in boss.get("casts", []):
			draw_twin(cast)
		for hit in impacts:
			draw_impact(hit)

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
	if series.has("warning"):
		draw_pack_warning(cast)
		return
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
		if str(cast.skill) == "boss_wave_push" or (cast.get("to") != null and cast.has("dir")):
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

# ------------------------------------------------------------ Robot Bom Dây Cót

## The robot: frame of its facing (walking cycles 4 frames), larger than its
## footprint, feet on the footprint's bottom edge; effects as for the slime.
func draw_robot() -> void:
	var rect := footprint()
	var dir := str(boss.get("facing", "down"))
	var aiming := false
	if not series.is_empty():
		# Sprite pack: faces the skill's direction (roll lane, thorn line) while warning.
		for cast in boss.get("casts", []):
			if cast.has("dir"):
				dir = str(cast.dir)
				aiming = true
	var frames: Array = walks.get(dir, walks.down)
	var moving := walking()
	var pack := not series.is_empty()
	var tex: Texture2D = frames[int(clock * (PACK_WALK_FPS if pack else 10.0)) % frames.size()] if moving else frames[0]
	if not moving and not aiming and (dir == "down" or pack) and idles.size() > 1:
		tex = idles[int(clock * (PACK_IDLE_FPS if pack else 7.0)) % idles.size()]
	# A roll / charge carries it (the orb / charge art): the body is not drawn then.
	for cast in boss.get("casts", []):
		if TWIN_VFX.get(str(cast.skill), ["", ""])[1] == "boss" and now - float(cast.castAt) > float(SKILL_TIMING_MS.get(str(cast.skill), 900)):
			return
	art = tex
	var phase := int(boss.get("phase", 1))
	var casting: bool = not boss.get("casts", []).is_empty()
	var defeated := int(boss.get("hp", 1)) <= 0 and int(boss.get("maxHp", 0)) > 0
	var width := rect.size.x * (TWIN_ART if not vfx.is_empty() else ROBOT_ART) * (1.0 + 0.02 * sin(clock * 3.0))
	var extent := Vector2(width, width * tex.get_height() / tex.get_width())
	var bob := 0.0 if moving else 2.0 * sin(clock * 2.4)
	var feet := Vector2(rect.get_center().x, rect.end.y + bob)
	if pack:
		feet.y += extent.y * (1.0 - PACK_FEET)  # the pack's frames stand above the canvas edge
	# Shadow on the footprint (no part in collisions).
	draw_set_transform(Vector2(rect.get_center().x, rect.end.y - 6), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, rect.size.x * 0.5, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if bool(boss.get("weak", false)):
		draw_circle(rect.get_center(), rect.size.x * 0.75 + 4.0 * sin(clock * 8.0), Color("ffd84d", 0.35))
	var tint := Color(1, 0.55, 0.55) if flash > 0.0 else (Color(1.15, 0.9, 0.85) if phase == 3 else Color.WHITE)
	if defeated:
		if defeat_time < 0.0:
			return
		# Winds down: tips over, fades, a puff of smoke from the back bomb.
		var t := clampf(defeat_time / 1.2, 0.0, 1.0)
		tint = Color(1, 1, 1, 1.0 - t)
		draw_set_transform(feet, -0.5 * t, Vector2.ONE * (1.0 - 0.25 * t))
		draw_texture_rect(tex, Rect2(Vector2(-extent.x * 0.5, -extent.y), extent), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(rect.get_center() - Vector2(0, rect.size.y * 0.4), rect.size.x * 0.6 * t, Color(0.35, 0.35, 0.4, 0.5 * (1.0 - t)))
		return
	if casting:
		draw_cast_ring(feet, rect.size.x * 1.1)
		tint = tint * Color(1.0, 0.9 + 0.1 * sin(clock * 14.0), 0.9 + 0.1 * sin(clock * 14.0))
	draw_texture_rect(tex, Rect2(feet - Vector2(extent.x * 0.5, extent.y), extent), false, tint)
	if casting:
		draw_cast_marks(feet - Vector2(0, extent.y), extent.x)
	if bool(boss.get("stunned", false)):
		# Stars circling the head while it is stunned.
		for i in 3:
			var angle := clock * 4.0 + i * TAU / 3.0
			var star := feet - Vector2(0, extent.y * 0.95) + Vector2(cos(angle) * 30.0, sin(angle) * 9.0)
			draw_circle(star, 6.0, Color("ffe14d"))
			draw_circle(star, 3.0, Color.WHITE)

## Where the robot's back bomb launches from (above its head).
func launch_point() -> Vector2:
	var rect := footprint()
	return rect.get_center() - Vector2(0, rect.size.y * 0.9)

## Bombs fly from the robot's back to their cells, then sit and blink faster as
## the server's resolve time comes.
func draw_bombs(cast: Dictionary) -> void:
	if bomb_tex == null:
		return
	var span := maxf(1.0, float(cast.resolveAt) - float(cast.castAt))
	var flight := minf(FLIGHT_MS, span * 0.35)
	var origin := launch_point()
	var cells: Array = cast.get("bombs", [])
	for i in cells.size():
		var t = cells[i]
		var target := (Vector2(float(t[0]), float(t[1])) + Vector2(0.5, 0.5)) * TILE
		var start := float(cast.castAt) + minf(i * VOLLEY_MS, span * 0.2)
		if now < start:
			continue
		var p := clampf((now - start) / flight, 0.0, 1.0)
		if p < 1.0:
			var height := 60.0 + origin.distance_to(target) * 0.3
			var pos := origin.lerp(target, p) + Vector2(0, -height * 4.0 * p * (1.0 - p))
			draw_sprite(bomb_tex, pos, BOMB_WIDTH * (0.7 + 0.3 * p), false)
			continue
		var close := clampf((now - start - flight) / maxf(1.0, float(cast.resolveAt) - start - flight), 0.0, 1.0)
		var blink := int(clock * (4.0 + 14.0 * close)) % 2 == 0
		var tint := Color(1.6, 0.8, 0.8) if blink and close > 0.3 else Color.WHITE
		draw_sprite(bomb_tex, target, BOMB_WIDTH * (1.0 + 0.15 * close), false, tint)

## The mini chaser hops after its target; once stopped it blinks like a bomb.
func draw_mini(cast: Dictionary) -> void:
	if bomb_tex == null or not minis_at.has(int(cast.id)):
		return
	var m: Dictionary = minis_at[int(cast.id)]
	var pos := mini_drawn(m)
	var armed: bool = not cast.get("tiles", []).is_empty()
	var hop := 0.0 if armed else -absf(sin(clock * 10.0)) * 10.0
	var tint := Color.WHITE
	if armed and int(clock * 14.0) % 2 == 0:
		tint = Color(1.7, 0.8, 0.8)
	# Little feet so it reads as the walking mini bomb of the concept sheet.
	if not armed:
		var swing := sin(clock * 20.0) * 5.0
		draw_line(pos + Vector2(-7, 10), pos + Vector2(-7 + swing, 20), Color("2a2f45"), 4.0)
		draw_line(pos + Vector2(7, 10), pos + Vector2(7 - swing, 20), Color("2a2f45"), 4.0)
	draw_sprite(bomb_tex, pos + Vector2(0, hop), BOMB_WIDTH * 0.75, false, tint)

## Magnet Pull: four bombs circle the robot and spiral onto its back.
func draw_magnet(cast: Dictionary) -> void:
	if bomb_tex == null:
		return
	var rect := footprint()
	var span := maxf(1.0, float(cast.resolveAt) - float(cast.castAt))
	var p := clampf((now - float(cast.castAt)) / span, 0.0, 1.0)
	var radius := rect.size.x * (1.4 - 0.9 * p)
	for i in 4:
		var angle := clock * 5.0 + i * TAU / 4.0
		var pos := rect.get_center() + Vector2(cos(angle), sin(angle) * 0.6) * radius
		draw_sprite(bomb_tex, pos, BOMB_WIDTH * 0.6, false)
	draw_arc(rect.get_center(), rect.size.x * 1.2, clock * 4.0, clock * 4.0 + PI, 24, Color("9a6bff", 0.6), 4.0)

# ------------------------------------------------------------ Vua Xương Rồng / Cừu Sấm Sét

## Idle frames: assets/boss/<pack>/idle/01..NN.png.
static func load_idles(pack: String) -> Array:
	var out := []
	for i in range(1, 9):
		var path := "res://assets/boss/%s/idle/%02d.png" % [pack, i]
		if not ResourceLoader.exists(path):
			break
		out.append(load(path))
	return out

## VFX of a twin-boss pack: assets/boss/<pack>/vfx/<name>.png.
static func load_vfx(pack: String) -> Dictionary:
	var out := {}
	var dir := "res://assets/boss/%s/vfx" % pack
	for name in ["roll", "thorn", "cross", "storm", "dash", "impact", "ball", "ring", "strike", "leap", "blast"]:
		var path := "%s/%s.png" % [dir, name]
		if ResourceLoader.exists(path):
			out[name] = load(path)
	return out

func _volley_seen(volley: int) -> bool:
	for id in casts_seen:
		if int(casts_seen[id].get("volley", -1)) == volley:
			return true
	return false

func cell_centre(t) -> Vector2:
	return (Vector2(float(t[0]), float(t[1])) + Vector2(0.5, 0.5)) * TILE

## A short flash where a twin skill hit (the server's tiles only).
func twin_impact(cast: Dictionary) -> void:
	var spec: Array = TWIN_VFX[str(cast.skill)]
	var name: String = spec[0]
	if str(cast.skill) == "ram_thunder_charge" or str(cast.skill) == "cactus_thorn_roll":
		name = "impact" if vfx.has("impact") else name
	if bool(cast.get("final", false)) and vfx.has("blast"):
		name = "blast"
	if not series.is_empty():
		pack_impact(cast)
		return
	var tex: Texture2D = vfx.get(name)
	if tex == null:
		return
	impacts.append({"tex": tex, "tiles": cast.get("tiles", []), "mode": spec[1], "left": IMPACT_SECONDS})

## While a twin skill is warned / flying, its art moves with it.
func draw_twin(cast: Dictionary) -> void:
	var skill := str(cast.skill)
	if not TWIN_VFX.has(skill):
		return
	if not series.is_empty():
		draw_pack_skill(cast)
		return
	var spec: Array = TWIN_VFX[skill]
	var tex: Texture2D = vfx.get(spec[0])
	if tex == null:
		return
	var rect := footprint()
	match str(spec[1]):
		"boss":
			# Gathering speed on the boss, then rolling / charging along the lane.
			var warn := float(SKILL_TIMING_MS.get(skill, 900))
			var started := now - float(cast.castAt) > warn
			var glow := 0.55 + 0.25 * sin(clock * 16.0)
			draw_sprite(tex, rect.get_center() + Vector2(0, -rect.size.y * 0.1), rect.size.x * (1.6 if started else 1.2), false, Color(1, 1, 1, glow if not started else 0.95))
		"fly":
			# Each projectile cast is one cell of the flight: drawn while it is next.
			# Only the step in flight now (between the previous cell and this one).
			var lead := float(cast.resolveAt) - now
			if lead > 220.0 or lead < -60.0:
				return
			for t in cast.get("tiles", []):
				draw_sprite(tex, cell_centre(t), TILE * (1.1 if skill == "ram_thunder_ball" else 0.8), false)
		"centre":
			# The cross gathers on the boss during the warning.
			var p := clampf((now - float(cast.castAt)) / maxf(1.0, float(cast.resolveAt) - float(cast.castAt)), 0.0, 1.0)
			draw_sprite(tex, rect.get_center(), rect.size.x * (0.8 + 0.8 * p), false, Color(1, 1, 1, 0.35 + 0.5 * p))
		"tiles":
			# Thunder Ram: the leap art on the boss while it calls the storm.
			if skill == "ram_thunder_storm" and vfx.has("leap") and int(cast.get("wave", 1)) == 1:
				draw_sprite(vfx.leap, rect.get_center() - Vector2(0, rect.size.y * 0.6), rect.size.x * 1.5, false, Color(1, 1, 1, 0.8))
			if skill == "ram_thunder_storm" and vfx.has("ring") and now >= float(cast.castAt):
				for t in cast.get("tiles", []):
					draw_sprite(vfx.ring, cell_centre(t), TILE * 0.95, false, Color(1, 1, 1, 0.75))

const SKILL_TIMING_MS := {"cactus_thorn_roll": 900, "ram_thunder_charge": 900, "cactus_thorn_shot": 700}
## Design-team sprite pack (manifest.json: walk 9 FPS, idle 5 FPS, effects 18 FPS,
## feet at 93.4 % of the frame height). Sizes are art only: hits stay on cells.
const PACK_SERIES := ["orb", "projectile", "impact", "warning", "cross_tile", "storm"]
const PACK_SERIES_FRAMES := 8
const PACK_WALK_FPS := 9.0
const PACK_IDLE_FPS := 5.0
const PACK_FX_FPS := 18.0
const PACK_WARN_FPS := 12.0
const PACK_STORM_FPS := 16.0
const PACK_FEET := 0.9336
const PACK_ORB := 1.15  # orb canvas / footprint (the 2-cell lane)
const PACK_THORN := 0.95
const PACK_THORN_STEP_MS := 167.0  # arena THORN_MS_PER_CELL
const PACK_HIT := 1.4
const PACK_STORM := 1.9

func draw_impact(hit: Dictionary) -> void:
	var tex: Texture2D = hit.tex
	var left: float = hit.left
	if hit.has("frames"):
		# Sprite pack: plays once at PACK_FX_FPS, on each cell or at one point.
		var frames: Array = hit.frames
		var k := clampi(int((float(hit.total) - left) * PACK_FX_FPS), 0, frames.size() - 1)
		var fade := clampf(left / float(hit.total) * 4.0, 0.0, 1.0)
		if hit.has("at"):
			draw_sprite(frames[k], hit.at, float(hit.width), false, Color(1, 1, 1, fade))
		else:
			for t in hit.tiles:
				draw_sprite(frames[k], cell_centre(t), float(hit.width), false, Color(1, 1, 1, fade))
		return
	var alpha := clampf(left / IMPACT_SECONDS * 1.5, 0.0, 1.0)
	var grow := 1.0 + 0.3 * (1.0 - left / IMPACT_SECONDS)
	var tiles: Array = hit.tiles
	if tiles.is_empty():
		return
	if str(hit.mode) == "centre":
		draw_sprite(tex, footprint().get_center(), footprint().size.x * 2.6 * grow, false, Color(1, 1, 1, alpha))
		return
	for t in tiles:
		draw_sprite(tex, cell_centre(t), TILE * 1.1 * grow, false, Color(1, 1, 1, alpha))

## Trapped raiders: a water bubble over them and the seconds left to rescue.
func draw_bubbles(on: CanvasItem) -> void:
	var trapped: Dictionary = boss.get("trapped", {})
	var font := ThemeDB.fallback_font
	for id in trapped:
		var holder = raider_spots.get(str(id))
		if not (holder is Node2D) or not is_instance_valid(holder):
			continue
		var pos: Vector2 = (holder as Node2D).position + Vector2(0, 4)
		var left := maxf(0.0, (float(trapped[id]) - now) / 1000.0)
		var wobble := 1.0 + 0.04 * sin(clock * 6.0)
		on.draw_circle(pos, 36.0 * wobble, Color(0.45, 0.8, 1.0, 0.5))
		on.draw_arc(pos, 36.0 * wobble, 0.0, TAU, 48, Color(0.9, 0.98, 1.0, 1.0), 5.0)
		on.draw_arc(pos, 30.0 * wobble, 0.0, TAU, 48, Color(0.3, 0.65, 1.0, 0.8), 2.0)
		on.draw_arc(pos + Vector2(-12, -14), 9.0, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.9), 3.0)
		var share := clampf(left / maxf(1.0, float(boss.get("rescueMs", 4000)) / 1000.0), 0.0, 1.0)
		on.draw_arc(pos, 40.0, -PI / 2.0, -PI / 2.0 + TAU * share, 32, Color("ffd84d") if share > 0.35 else Color("ff4d6a"), 4.0)
		var label := "%.1f" % left
		on.draw_string_outline(font, pos + Vector2(-30, 54), label, HORIZONTAL_ALIGNMENT_CENTER, 60, 18, 5, Color("0d2f5c"))
		on.draw_string(font, pos + Vector2(-30, 54), label, HORIZONTAL_ALIGNMENT_CENTER, 60, 18, Color.WHITE)

## The skill's name over the boss for a moment before the hit (spec: 0.6-1.5 s).
func draw_banner(on: CanvasItem) -> void:
	if banner_left <= 0.0 or banner_text == "":
		return
	var rect := footprint()
	var font := ThemeDB.fallback_font
	var alpha := clampf(banner_left / 0.3, 0.0, 1.0)
	var pos := rect.get_center() + Vector2(-160, -rect.size.y * 1.15)
	on.draw_string_outline(font, pos, banner_text, HORIZONTAL_ALIGNMENT_CENTER, 320, 30, 9, Color(0.05, 0.1, 0.25, alpha))
	on.draw_string(font, pos, banner_text, HORIZONTAL_ALIGNMENT_CENTER, 320, 30, Color(1, 0.88, 0.3, alpha))

## Drawn by the board's top layer (above raiders and bombs): bubbles and the banner.
func draw_overlay(on: CanvasItem) -> void:
	if boss.is_empty() or vfx.is_empty():
		return
	draw_bubbles(on)
	draw_banner(on)

## Design-team sprite pack (Vua Xương Rồng): assets/boss/<pack>/vfx/<name>_01..08.png,
## each frame a separate PNG: the rolling orb, a thorn, a hit, a one-cell warning,
## a one-cell burst and the storm centre. Areas are built from the server's
## cells in code, never from one long image.
static func load_series(pack: String) -> Dictionary:
	var out := {}
	for name in PACK_SERIES:
		var frames := []
		for i in range(1, 9):
			var path := "res://assets/boss/%s/vfx/%s_%02d.png" % [pack, name, i]
			if not ResourceLoader.exists(path):
				break
			frames.append(load(path))
		if not frames.is_empty():
			out[name] = frames
	return out if out.size() == PACK_SERIES.size() else {}

## Every warned cell gets its own animated warning; the roll lane keeps an arrow.
func draw_pack_warning(cast: Dictionary) -> void:
	var frames: Array = series.warning
	var tex: Texture2D = frames[int(clock * PACK_WARN_FPS) % frames.size()]
	var span := maxf(1.0, float(cast.resolveAt) - float(cast.castAt))
	var progress := clampf((now - float(cast.castAt)) / span, 0.0, 1.0)
	var look: Array = SKILL_LOOK.get(str(cast.skill), [Color("ff4d6a"), "!"])
	var pulse := 0.5 + 0.5 * sin(clock * 12.0)
	for t in cast.get("tiles", []):
		var cell := Rect2(Vector2(float(t[0]), float(t[1])) * TILE, Vector2(TILE, TILE)).grow(-3)
		# Readable on the light map: a warm fill that fills up, then the pack's warning.
		draw_rect(cell, Color(look[0], 0.3 + 0.15 * pulse))
		draw_rect(Rect2(cell.get_center(), Vector2.ZERO).grow(cell.size.x * 0.5 * progress), Color(look[0], 0.3))
		draw_sprite(tex, cell.get_center(), TILE * 1.0, false, Color(1.6, 1.3, 0.9))
		draw_rect(cell, Color(look[0].lightened(0.2), 0.75 + 0.25 * pulse), false, 3.0)
		if str(cast.skill) == "cactus_thorn_roll" and cast.has("dir"):
			var dir: Vector2 = ARROWS.get(str(cast.dir), Vector2.RIGHT)
			var c := cell.get_center() + dir * 14.0
			draw_line(c + dir * 10, c + dir * -2 + dir.orthogonal() * 8, Color.WHITE, 4.0)
			draw_line(c + dir * 10, c + dir * -2 - dir.orthogonal() * 8, Color.WHITE, 4.0)

## Where the rolling orb is: on the boss during the warning (none drawn), then
## along the lane to the server's end cell by the resolve time.
func orb_position(cast: Dictionary) -> Vector2:
	var rect := footprint()
	var warn := float(SKILL_TIMING_MS.get(str(cast.skill), 900))
	var size := rect.size.x
	var to := rect.get_center()
	if cast.get("to") != null:
		to = Vector2(float(cast.to[0]), float(cast.to[1])) * TILE + Vector2(size, size) * 0.5
	var q := clampf((now - float(cast.castAt) - warn) / maxf(1.0, float(cast.resolveAt) - float(cast.castAt) - warn), 0.0, 1.0)
	return rect.get_center().lerp(to, q)

## Sprite pack skills: the boss is hidden while the orb rolls (draw_robot); a
## thorn is one projectile on the cell it is crossing; the storm turns on the boss.
func draw_pack_skill(cast: Dictionary) -> void:
	var rect := footprint()
	match str(cast.skill):
		"cactus_thorn_roll":
			if now - float(cast.castAt) <= float(SKILL_TIMING_MS.cactus_thorn_roll):
				return
			var at := orb_position(cast)
			draw_set_transform(at + Vector2(0, rect.size.y * 0.42), 0.0, Vector2(1.0, 0.3))
			draw_circle(Vector2.ZERO, rect.size.x * 0.42, Color(0, 0, 0, 0.3))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var frames: Array = series.orb
			draw_sprite(frames[int(clock * PACK_FX_FPS) % frames.size()], at, rect.size.x * PACK_ORB, false)
		"cactus_thorn_shot":
			# Each cast is one cell of the flight: the thorn slides in from the
			# cell behind during the last step before this cast resolves.
			var q := 1.0 - (float(cast.resolveAt) - now) / PACK_THORN_STEP_MS
			if q < 0.0 or q > 1.0:
				return
			var back: Vector2 = ARROWS.get(str(cast.get("dir", "up")), Vector2.UP) * -TILE
			var frames: Array = series.projectile
			for t in cast.get("tiles", []):
				draw_sprite(frames[int(clock * PACK_FX_FPS) % frames.size()], cell_centre(t) + back * (1.0 - q), TILE * PACK_THORN, false)
		"cactus_thorn_storm":
			# One storm centre for all waves, from the first wave still to come.
			for other in boss.get("casts", []):
				if str(other.skill) == "cactus_thorn_storm":
					if int(other.id) != int(cast.id):
						return
					break
			if now < float(cast.castAt):
				return
			var frames: Array = series.storm
			draw_sprite(frames[int(clock * PACK_STORM_FPS) % frames.size()], rect.get_center(), rect.size.x * PACK_STORM, false, Color(1, 1, 1, 0.9))

## Hits: the orb bursts at its end cell; the last thorn of a volley bursts where
## it stopped; the cross and each storm wave burst on every server cell.
func pack_impact(cast: Dictionary) -> void:
	var rect := footprint()
	var total := float(PACK_SERIES_FRAMES) / PACK_FX_FPS + 0.1
	match str(cast.skill):
		"cactus_thorn_roll":
			var at := rect.get_center()
			if cast.get("to") != null:
				var size := rect.size.x
				at = Vector2(float(cast.to[0]), float(cast.to[1])) * TILE + Vector2(size, size) * 0.5
			impacts.append({"frames": series.impact, "tex": series.impact[0], "at": at, "width": rect.size.x * PACK_HIT, "total": total, "left": total})
		"cactus_thorn_shot":
			for other in boss.get("casts", []):
				if int(other.get("volley", -1)) == int(cast.get("volley", -2)) and int(other.id) != int(cast.id):
					return  # thorns of this volley still flying
			impacts.append({"frames": series.impact, "tex": series.impact[0], "tiles": cast.get("tiles", []), "width": TILE * 1.4, "total": total, "left": total})
		_:
			impacts.append({"frames": series.cross_tile, "tex": series.cross_tile[0], "tiles": cast.get("tiles", []), "width": TILE * 1.1, "total": total, "left": total})
