extends SceneTree
## Boss raid UI of the PC app (docs/BOSS.md) with snapshots written by the real
## arena simulation (apps/arena/scripts/boss_fixture.ts): the waiting room, the
## board with the boss, warning tiles and HP bar, the WIN result, the SĂN BOSS
## page (open / closed / rewards) and the reconnect rule. No server needed.
## Set SUNI_CAPTURE_DIR to save screenshots (needs a display).
var failed := false
var checks := 0
var capture_dir := OS.get_environment("SUNI_CAPTURE_DIR")

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func frames(n := 3) -> void:
	for i in n:
		await process_frame

func capture(file: String) -> void:
	if capture_dir.is_empty():
		return
	await frames(6)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir + "/" + file)

func boss_event(open: bool) -> Dictionary:
	return {
		"id": "evt_ui", "name": "Đại Chiến Boss - Săn Boss Nhận Quà", "description": "", "banner": "Một sinh vật bí ẩn xuất hiện!",
		"intro": "Lập đội săn Boss.", "badge_name": "Huy Hiệu Boss", "phase": "running", "window": "progress",
		"start_at": "2026-10-19T00:00:00+00:00", "end_at": "2026-10-26T00:00:00+00:00", "claim_end_at": "2026-10-29T00:00:00+00:00",
		"open": open, "in_session": open, "next_session": "2026-10-19T12:00:00+00:00", "server_time": "2026-10-19T08:00:00+00:00",
		"rules": {
			"display_name": "Boss Sự Kiện", "map_id": "harbor", "min_players": 1, "max_players": 8, "duration_seconds": 300,
			"hp_solo": 1000, "hp_full": 4850, "phase_thresholds": [0.7, 0.35], "skills": ["boss_basic_hit", "boss_aoe_mark"],
			"items": ["dart"], "mount": true, "reward_private_room": false, "full_reward_limit_per_day": 3,
			"win_rewards": [{"type": "gold", "amount": 150}, {"type": "token", "amount": 30, "label": "Huy Hiệu Boss"}],
			"lose_rewards": [{"type": "gold", "amount": 20}], "sessions": [{"days_of_week": [1, 2, 3, 4, 5, 6, 7], "local_start": "19:00", "local_end": "22:00"}],
		},
		"me": {"wins": 2, "full_rewards_today": 1, "pending_rewards": 1, "badges": 60},
		"quests": [], "shop": [],
	}

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("timeout"); quit(1))
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/boss_snapshots.json"))
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(4)
	var arena = root.get_node("OnlineArena")
	arena.session_id = "me"
	game.show_pc_screen("online")
	var online = game.pc_screens["online"]
	await frames()

	# Waiting room: boss title, solo allowed, seats from the event.
	arena.snapshot = fixtures.waiting
	online._on_snapshot(fixtures.waiting)
	await frames()
	check(online.title_label.text.contains("Đại Chiến Boss") and online.title_label.text.contains("Boss Sự Kiện"), "Room title names the boss: " + online.title_label.text)
	check(online.status_label.text.contains("Tối thiểu 1"), "Solo raids allowed: " + online.status_label.text)
	check(not online.ready_button.disabled, "Ready while waiting")
	await capture("boss-room.png")

	# Playing: boss on its footprint, the telegraph tiles of the server, HP bar.
	arena.snapshot = fixtures.playing
	online._on_snapshot(fixtures.playing)
	await frames()
	var boss: Dictionary = fixtures.playing.boss
	check(online.battle_view.visible and online.boss_view.visible and online.boss_hud.visible, "Boss board and HUD shown")
	check(online.boss_view.boss.get("casts", []).size() == 1, "The server's cast is drawn")
	check(online.boss_view.boss.casts[0].tiles == boss.casts[0].tiles, "Same warning tiles as the server")
	check(online.boss_title.text == "Boss Sự Kiện" and online.boss_phase.text == "PHASE 1", "Boss name and phase")
	check(is_equal_approx(online.boss_bar.hp, float(boss.hp)) and online.boss_bar.thresholds == boss.thresholds, "HP bar and phase ticks")
	check(online.boss_note.text.begins_with("⚠"), "Current skill named: " + online.boss_note.text)
	check(online.stat_status.text.contains("Boss"), "Boss hint in the status bar")
	var footprint: Rect2 = online.boss_view.footprint()
	check(footprint.position == Vector2(7, 5) * 64 and footprint.size == Vector2(192, 192), "Footprint 3x3 at (7,5)")
	check(online.boss_view.art != null and online.boss_view.current_anim() == "cast", "Slime King art, casting pose during a telegraph")
	check(online.boss_view.throws_slimes(boss.casts[0]) and not online.boss_view.minis.mini_bomb.is_empty(), "The boss throws mini slimes at the warned cells")
	# Grows and shrinks, but never leaves its 3x3 footprint (phase 3, mid-throw too).
	var view = online.boss_view
	var widths := []
	for phase in [1, 3]:
		view.boss.phase = phase
		for kick in [0.0, 0.175]:
			view.throw_kick = kick
			for i in 40:
				view.clock = i * 0.07
				for anim in ["idle", "cast", "move", "defeat"]:
					var size: Vector2 = view.art_size(view.textures.idle, anim)
					widths.append(size.x)
					check(size.x <= 192.01 and size.y <= 192.01, "%s fits 3x3 at phase %d: %s" % [anim, phase, size])
	view.boss.phase = 1
	view.throw_kick = 0.0
	check(widths.max() > widths.min() * 1.15, "The boss grows and shrinks: %d..%d px" % [widths.min(), widths.max()])
	await create_timer(1.6).timeout
	var cast: Dictionary = boss.casts[0]
	online.boss_view.now = float(cast.castAt) + 200.0  # slimes in the air
	online.boss_view.set_process(false)
	online.boss_view.queue_redraw()
	await capture("boss-throw.png")
	online.boss_view.now = float(cast.resolveAt) - 150.0  # landed, about to burst
	online.boss_view.queue_redraw()
	await capture("boss-battle.png")
	online.boss_view.set_process(true)

	# Finished WIN: server result, then the API result (none offline).
	arena.snapshot = fixtures.finished
	online._on_snapshot(fixtures.finished)
	await frames()
	check(online.result_box.visible and online.result_title.text == "ĐÃ HẠ BOSS!", "WIN result from the snapshot")
	check(online.boss_view.current_anim() == "defeat" and online.boss_view.defeat_time >= 0.0, "Defeat effect starts when HP reaches 0")
	check(online.boss_view.art == online.boss_view.textures.idle, "Same Slime King art in every state")
	check(online.boss_view.bursts.size() == 1 and online.boss_view.bursts[0].kind == "mini_bomb", "Thrown slimes burst when the server resolves the hit")
	check(online.raid_match == "p1.fixture.1", "Fetches the result of this raid id")
	check(not online.claim_button.visible, "No claim button before the server says so")
	online.raid_info = {"me": {"damage": 50, "support": 0, "reward": "full", "reason": ""}, "grants": [{"id": "g1", "status": "ELIGIBLE", "kind": "full", "rewards": [{"type": "gold", "amount": 150}]}]}
	online.render_side(fixtures.finished)
	check(online.claim_button.visible and online.result_detail.text.contains("150 xu"), "Claim offered for an eligible grant")
	online.raid_info = {"me": {"damage": 0, "support": 0, "reward": "none", "reason": "AFK", "reason_text": "Không hoạt động (AFK)"}, "grants": []}
	online.render_side(fixtures.finished)
	check(not online.claim_button.visible and online.result_detail.text.contains("AFK"), "Ineligible shows the reason")
	online.result_box.hide()
	for spec in [[0.3, "boss-defeat-1.png"], [0.75, "boss-defeat-2.png"], [1.3, "boss-defeat-3.png"]]:
		online.boss_view.set_process(false)
		online.boss_view.defeat_time = spec[0]
		online.boss_view.queue_redraw()
		await capture(spec[1])
	online.boss_view.set_process(true)
	online.render_side(fixtures.finished)
	await capture("boss-result.png")

	# Reconnect only for a boss raid in play, with the JOIN_ROOM token.
	arena.snapshot = fixtures.playing
	arena._reconnect_token = "abc"
	check(arena._resumable(), "A dropped boss raid is resumed")
	arena.snapshot = fixtures.finished
	check(not arena._resumable(), "No resume after the raid")
	arena._reconnect_token = ""
	arena.snapshot = {}

	# Robot Bom Dây Cót: directional art, its bombs on the server's cells, the mini chaser, walking.
	var chain: Dictionary = fixtures.robotChain
	arena.snapshot = chain
	online._on_snapshot(chain)
	await frames()
	view = online.boss_view
	check(view.walks.size() == 4 and view.walks.down.size() == 4, "Robot pack: 4 directions x 4 frames")
	check(view.walks[str(chain.boss.facing)].has(view.art), "Robot drawn turned to the server's facing (%s)" % chain.boss.facing)
	footprint = view.footprint()
	check(footprint.position == Vector2(float(chain.boss.x), float(chain.boss.y)) * 64 and footprint.size == Vector2(128, 128), "Footprint 2x2: %s" % footprint)
	check(view.boss.casts.size() == 3, "Bomb Chain: three bombs")
	for i in 3:
		check(view.boss.casts[i].bombs == chain.boss.casts[i].bombs and view.boss.casts[i].tiles == chain.boss.casts[i].tiles, "Same bomb cells and warned cells as the server")
	check(online.boss_note.text == "⚠ Chuỗi Boom", "Robot skill named: " + online.boss_note.text)
	check(online.walls.size() == 68, "Factory floor: border + 12 of 35 pillars (%d walls)" % online.walls.size())
	view.set_process(false)
	view.now = float(chain.boss.casts[0].castAt) + 150.0  # bombs in the air
	view.queue_redraw()
	await capture("robot-throw.png")
	view.now = float(chain.boss.casts[0].resolveAt) - 200.0  # landed, blinking
	view.queue_redraw()
	await capture("robot-chain.png")
	view.set_process(true)
	var chaser: Dictionary = fixtures.robotChaser
	online._on_snapshot(chaser)
	await frames()
	var mini: Array = chaser.boss.casts[0].mini
	check(view.minis_at.has(int(chaser.boss.casts[0].id)), "Mini chaser tracked")
	check(view.mini_drawn(view.minis_at[int(chaser.boss.casts[0].id)]) == (Vector2(float(mini[0]), float(mini[1])) + Vector2(0.5, 0.5)) * 64, "Mini chaser on the server's cell")
	await capture("robot-chaser.png")
	var walk: Dictionary = fixtures.robotWalk
	online._on_snapshot(walk)
	await frames()
	check(view.walking() and view.slide_t < 1.0, "Robot slides to its new cell")
	check(view.walks.down.has(view.art) and str(walk.boss.facing) == "down", "Walking frames face the step")
	await create_timer(float(walk.boss.walkMs) / 1000.0 + 0.2).timeout
	check(view.footprint().position == Vector2(float(walk.boss.x), float(walk.boss.y)) * 64, "Slide ends on the server cell")
	await capture("robot-walk.png")

	# SĂN BOSS page (popup of the lobby): open event -> three ways in; closed -> disabled.
	game.show_pc_screen("lobby")
	var lobby = game.pc_screens["lobby"]
	var page = lobby.store_page("boss")
	lobby.open_shop("boss")
	await frames()
	check(lobby.store_title.text == "ĐẠI CHIẾN BOSS", "Boss popup title")
	var played := []
	# The lobby would join the arena; record the request instead.
	page.play.disconnect(lobby.play_boss)
	page.play.connect(func(event_id, mode): played.append([event_id, mode]))
	page.state = "ok"
	page.events = [boss_event(true)]
	page.render()
	await frames()
	var solo: Button = page.find_child("Play_solo", true, false)
	var team: Button = page.find_child("Play_team", true, false)
	check(solo != null and not solo.disabled and not team.disabled, "Open event: Solo / Ghép đội enabled")
	solo.pressed.emit()
	team.pressed.emit()
	check(played == [["evt_ui", "solo"], ["evt_ui", "team"]], "Buttons ask the lobby to join: %s" % [played])
	var private_button: Button = page.find_child("Play_private", true, false)
	private_button.pressed.emit()
	check(page.modal.visible and played.size() == 2, "Private room warns about rewards first")
	page.close_modal()
	check(page.tokens_label.text.contains("60"), "Badge balance shown")
	page.events = [boss_event(false)]
	page.render()
	await frames()
	solo = page.find_child("Play_solo", true, false)
	check(solo.disabled, "Closed event: no new raid")
	page.rewards = [{"id": "g1", "kind": "full", "status": "ELIGIBLE", "rewards": [{"type": "gold", "amount": 150}]}]
	page.set_tab("rewards")
	await frames()
	check(page.find_child("Grant_g1", true, false) != null, "Pending raid reward listed")
	page.set_tab("raid")
	# Two boss events at once (Slime King + robot): both cards on the page together.
	var robot_event := boss_event(true)
	robot_event.id = "evt_robot"
	robot_event.name = "Nhà Máy Bom Dây Cót"
	robot_event.rules = robot_event.rules.duplicate()
	robot_event.rules.display_name = "Robot Bom Dây Cót"
	page.events = [robot_event, boss_event(true)]
	page.render()
	await frames()
	var robot_card: Control = page.find_child("BossRaid_evt_robot", true, false)
	var slime_card: Control = page.find_child("BossRaid_evt_ui", true, false)
	check(robot_card != null and slime_card != null, "Both boss events shown at once")
	check(page.header.text.begins_with("2 sự kiện Boss"), "Header counts the events: " + page.header.text)
	robot_card.find_child("Play_team", true, false).pressed.emit()
	slime_card.find_child("Play_solo", true, false).pressed.emit()
	check(played.slice(-2) == [["evt_robot", "team"], ["evt_ui", "solo"]], "Each card joins its own event: %s" % [played.slice(-2)])
	page.set_tab("quests")
	await frames()
	check(page.find_child("Section_evt_robot", true, false) != null and page.find_child("Section_evt_ui", true, false) != null, "Quests grouped per event")
	page.set_tab("raid")
	await capture("boss-page-two.png")
	page.events = [boss_event(true)]
	page.render()
	await frames()
	check(page.find_child("BossRaid", true, false) != null and page.find_child("Section_evt_ui", true, false) == null, "One event: the single layout")
	await capture("boss-page.png")
	if not failed:
		print("BOSS_UI_OK checks=", checks)
	quit(1 if failed else 0)
