extends Control
signal navigate(destination: String)
const UISkin = preload("res://scripts/ui/ui_skin.gd")
const EquipCard = preload("res://scenes/ui/components/equipment_card.tscn")
const Stat = preload("res://scenes/ui/components/stat_bar.tscn")
const Slot = preload("res://scenes/ui/components/loadout_slot.tscn")
const EQUIP_TABS = [
	["outfit", "Áo"], ["hat", "Mũ"], ["bomb_skin", "Bom"],
	["effect", "Hiệu ứng"], ["pet", "Pet"], ["accessory", "Phụ kiện"]
]
var tab = "outfit"
var hero_index = 1

func _ready() -> void:
	UISkin.panel($ScreenFrame/VBox/Body/LeftMenu)
	UISkin.panel($ScreenFrame/VBox/Body/HeroPanel, "hero")
	UISkin.panel($ScreenFrame/VBox/Body/InventoryPanel/LoadoutPanel, "blue")
	UISkin.button($ScreenFrame/VBox/Body/HeroPanel/HeroVBox/HeroSwitch/Prev)
	UISkin.button($ScreenFrame/VBox/Body/HeroPanel/HeroVBox/HeroSwitch/Next)
	$ScreenFrame/VBox/Body/HeroPanel/HeroVBox/HeroSwitch/Prev.pressed.connect(_cycle_hero.bind(-1))
	$ScreenFrame/VBox/Body/HeroPanel/HeroVBox/HeroSwitch/Next.pressed.connect(_cycle_hero.bind(1))
	$ScreenFrame/VBox/TopBar.back_requested.connect(func(): navigate.emit("home"))
	$ScreenFrame/VBox/BottomNav.navigate.connect(func(page): navigate.emit(page))
	$ScreenFrame/VBox/BottomNav.set_active("equipment")
	UIState.inventory_changed.connect(_render_items)
	UIState.loadout_changed.connect(_refresh_loadout)
	UIState.loadout_changed.connect(_render_items)
	UIState.profile_changed.connect(_show_hero)
	UIState.profile_changed.connect(_render_items)
	_create_tabs()
	_show_hero()
	_render_items()
	_refresh_loadout()

func _create_tabs() -> void:
	var row = $ScreenFrame/VBox/Body/InventoryPanel/CategoryRow
	var left = $ScreenFrame/VBox/Body/LeftMenu/LeftSideVBox/LeftTabs
	for pair in EQUIP_TABS:
		var tab_id = str(pair[0])
		var label = str(pair[1])
		var btn = Button.new()
		btn.name = "Tab_%s" % tab_id
		btn.text = label
		btn.icon = load(UIState.get_item(_tab_icon_item(tab_id)).get("icon", "res://assets/items/mystery.png"))
		btn.expand_icon = true
		btn.custom_minimum_size = Vector2(91, 47)
		row.add_child(btn)
		btn.pressed.connect(_select_tab.bind(tab_id))
		var left_btn = Button.new()
		left_btn.name = "Nav_%s" % tab_id
		left_btn.text = label
		left_btn.icon = btn.icon
		left_btn.expand_icon = true
		left_btn.custom_minimum_size = Vector2(119, 50)
		left.add_child(left_btn)
		left_btn.pressed.connect(_select_tab.bind(tab_id))
	_style_tabs()

func _select_tab(category: String) -> void:
	tab = category
	_style_tabs()
	_render_items()

func _style_tabs() -> void:
	for row in [$ScreenFrame/VBox/Body/InventoryPanel/CategoryRow, $ScreenFrame/VBox/Body/LeftMenu/LeftSideVBox/LeftTabs]:
		for btn in row.get_children():
			var category = str(btn.name).trim_prefix("Tab_").trim_prefix("Nav_")
			UISkin.button(btn, "gold" if category == tab else "blue")

func _cycle_hero(step: int) -> void:
	hero_index = posmod(hero_index + step, UIState.characters.size())
	UIState.choose_hero(str(UIState.characters[hero_index]["id"]))

func _show_hero() -> void:
	var current = str(UIState.profile.get("selected_character", "mimi"))
	for i in range(UIState.characters.size()):
		if str(UIState.characters[i]["id"]) == current:
			hero_index = i
			break
	var info = UIState.get_character(current)
	$ScreenFrame/VBox/Body/HeroPanel/HeroVBox/HeroName.text = str(info.get("name", ""))
	UISkin.heading($ScreenFrame/VBox/Body/HeroPanel/HeroVBox/HeroName, 30, UISkin.YELLOW)
	$ScreenFrame/VBox/Body/HeroPanel/HeroVBox/HeroDescription.text = str(info.get("desc", ""))
	$ScreenFrame/VBox/Body/HeroPanel/HeroVBox/HeroArt.texture = load(str(info.get("portrait", "")))
	var stats = $ScreenFrame/VBox/Body/HeroPanel/HeroVBox/Stats
	for c in stats.get_children(): c.queue_free()
	var st: Dictionary = info.get("stats", {})
	for pair in [["Tốc độ", "speed"], ["Số bom", "bombs"], ["Tầm nổ", "range"]]:
		var line = Stat.instantiate()
		stats.add_child(line)
		line.configure(pair[0], int(st.get(pair[1], 0)), 5)

func _render_items() -> void:
	var grid = $ScreenFrame/VBox/Body/InventoryPanel/Scroll/Items
	for child in grid.get_children(): child.queue_free()
	for item in UIState.items:
		if str(item.get("category", "")) != tab: continue
		var card = EquipCard.instantiate()
		grid.add_child(card)
		card.bind_item(item)
		card.equip_requested.connect(_equip_requested)

func _equip_requested(id: String) -> void:
	if UIState.owned(id):
		UIState.equip(id)
	else:
		navigate.emit("shop")

func _refresh_loadout() -> void:
	var row = $ScreenFrame/VBox/Body/InventoryPanel/LoadoutPanel/LoadoutVBox/SlotRow
	for child in row.get_children(): child.queue_free()
	for pair in EQUIP_TABS:
		var slot = Slot.instantiate()
		row.add_child(slot)
		slot.bind_slot(str(pair[0]), str(pair[1]))

func _tab_icon_item(tab_id: String) -> String:
	match tab_id:
		"outfit": return "outfit_mimi"
		"hat": return "hat_ice"
		"bomb_skin": return "bomb_skin_black"
		"effect": return "effect_star"
		"pet": return "pet_bunny"
		"accessory": return "accessory_heart"
		_: return ""
