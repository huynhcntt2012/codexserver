extends Node
## Reports offline practice rooms and rounds for the admin history. These are
## client-reported, so the API stores them as unverified and grants nothing.
## Only signed-in players report; every call is fire-and-forget.
var game: Node
var room_id := ""
var room_key := ""  # server room key, also the room chat id
var opening := false
var round_no := 0

func signed_in() -> bool:
	return AuthSession.has_session()

func map_name() -> String:
	return str(game.current_level.get("name", "")).capitalize() if game and game.current_level is Dictionary else ""

func map_id() -> String:
	return str(game.current_level.get("id", "")) if game and game.current_level is Dictionary else ""

func room_opened() -> void:
	if not signed_in() or room_id != "" or opening:
		return
	opening = true
	var reply: Dictionary = await AuthSession.api(HTTPClient.METHOD_POST, "/v1/practice/rooms", {"map_name": map_name(), "map_id": map_id()})
	opening = false
	if reply.status == 201 and reply.data is Dictionary:
		room_id = str(reply.data.get("room_id", ""))
		room_key = str(reply.data.get("room_key", ""))
		round_no = 0

func set_state(status: String) -> void:
	if room_id == "" or not signed_in():
		return
	AuthSession.api(HTTPClient.METHOD_POST, "/v1/practice/rooms/%s/state" % room_id, {"status": status, "map_name": map_name(), "map_id": map_id()})

func round_started() -> void:
	set_state("playing")

## Same ranking as the result screen: points, humans before bots on ties.
func round_finished() -> void:
	if room_id == "" or not signed_in():
		return
	round_no += 1
	var ranked: Array = game.fighters.duplicate()
	var points := func(actor: Dictionary) -> int:
		return int(game.score) if not actor.bot else int(actor.get("kills", 0)) * 100 + int(actor.get("items", 0)) * 25
	ranked.sort_custom(func(a, b): return points.call(a) > points.call(b) or (points.call(a) == points.call(b) and not a.bot and b.bot))
	var bots_alive: Array = game.fighters.filter(func(a): return a.bot and a.alive)
	var people := []
	for i in ranked.size():
		var actor: Dictionary = ranked[i]
		var hero: String = str(actor.hero)
		var hero_name: String = game.HERO_NAMES[game.HEROES.find(hero)].capitalize()
		var winner: bool = game.last_won if not actor.bot else (not game.last_won and bots_alive.size() == 1 and actor.alive)
		people.append({
			"name": (AuthSession.account_name if not actor.bot else "Bot " + hero_name).left(24),
			"is_bot": bool(actor.bot),
			"hero": hero,
			"placement": i + 1,
			"kills": int(actor.get("kills", 0)),
			"bombs": int(actor.get("bombs_placed", 0)),
			"items": int(actor.get("items", 0)),
			"score": points.call(actor),
			"survived_ms": int(game.elapsed * 1000.0) if actor.alive else 0,
			"winner": winner,
		})
	AuthSession.api(HTTPClient.METHOD_POST, "/v1/practice/rooms/%s/matches" % room_id, {
		"round": round_no,
		"duration_ms": int(game.elapsed * 1000.0),
		"participants": people,
	})
	set_state("waiting")

func room_closed() -> void:
	set_state("closed")
	room_id = ""
	room_key = ""
	round_no = 0
