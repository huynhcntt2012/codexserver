extends SceneTree

var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)
	checks += 1

func run() -> void:
	var state = root.get_node("UIState")
	state.reset_demo()
	check(state.items.size() == 34, "Catalog count")
	var ui = load("res://scenes/ui/ui_showcase.tscn").instantiate()
	root.add_child(ui)
	current_scene = ui
	await process_frame
	check(ui.shop.visible and not ui.equipment.visible, "Shop opens first")
	for category in ui.shop.CATEGORIES:
		ui.shop._choose_category(category[0])
		await process_frame
	var gold = state.profile.gold
	ui.shop._request_buy("bomb_basic_pack")
	var dialog = ui.shop.get_child(ui.shop.get_child_count() - 1)
	dialog.canceled.emit()
	await process_frame
	check(state.profile.gold == gold, "Cancel must not debit wallet")
	check(not is_instance_valid(dialog), "Canceled dialog must be freed")
	ui.shop._request_buy("bomb_basic_pack")
	dialog = ui.shop.get_child(ui.shop.get_child_count() - 1)
	dialog.confirmed.emit()
	await process_frame
	check(state.profile.gold == gold - 500, "Confirmed purchase debits once")
	check(state.profile.consumables.bomb_basic_pack == 10, "Consumable quantity")
	check(not state.buy("bomb_skin_black"), "Reject duplicate cosmetic")
	check(not state.buy("unknown"), "Reject unknown item")
	state.profile.gold = 0
	check(not state.buy("bomb_basic_pack"), "Reject insufficient funds")
	check(state.profile.gold == 0, "Insufficient funds leave wallet unchanged")
	ui.open_page("equipment")
	check(ui.equipment.visible and not ui.shop.visible, "Navigate to equipment")
	for character in state.characters:
		state.choose_hero(character.id)
		for tab in ui.equipment.EQUIP_TABS:
			ui.equipment._select_tab(tab[0])
			await process_frame
	state.choose_hero("mimi")
	check(state.equip("outfit_mimi"), "Equip matching outfit")
	state.choose_hero("bombo")
	check(not state.equipped("outfit_mimi"), "No other hero outfit carried over")
	check(not state.equip("outfit_mimi"), "Reject wrong hero outfit")
	check(state.equip("outfit_bombo"), "Equip second hero")
	state.choose_hero("mimi")
	check(state.equipped("outfit_mimi"), "Restore hero loadout")
	state.profile.gem = 1000
	check(state.buy("wings_red_flame") and state.equip("wings_red_flame"), "Buy and wear wings")
	check(state.buy("halo_red_flame") and state.equip("halo_red_flame"), "Buy and wear a halo")
	check(state.profile.loadout.hat == "halo_red_flame", "Halo fills the hat slot")
	var hero = load("res://scripts/hero_sprite.gd").new()
	root.add_child(hero)
	hero.configure("mimi")
	hero.dress(state.profile.loadout)
	check(hero.wings != null and hero.halo != null, "Hero sprite wears wings and halo")
	hero.action("walk_down")
	check(hero.wings.animation == "flap" and hero.wings.show_behind_parent, "Wings flap behind the body")
	hero.action("walk_up")
	check(not hero.wings.show_behind_parent, "Wings face the camera from the back")
	hero.action("idle")
	check(hero.wings.animation == "idle", "Wings rest when idle")
	state.unequip("wings")
	check(state.profile.loadout.wings == "", "Unequip empties the slot")
	hero.dress(state.profile.loadout)
	check(hero.wings == null and hero.halo != null, "Unequipped wings come off")
	hero.free()
	state.unequip("hat")
	state.choose_hero("kai")
	ui.open_page("battle")
	await process_frame
	await process_frame
	var game = current_scene
	check(game.HEROES[game.selected_hero] == "kai", "Battle retains selected hero")
	check(game.game_state == "menu", "Battle opens map selection")
	change_scene_to_file("res://scenes/ui/ui_showcase.tscn")
	await process_frame
	await process_frame
	check(current_scene.shop.visible, "Return to shop")
	check(state.profile.gold == 0, "Wallet survives scene navigation")
	state.reset_demo()
	check(state.profile.gold == gold, "Reset restores demo")
	print("UI PASS: ", checks, " checks; all categories, tabs and heroes loaded")
	quit()
