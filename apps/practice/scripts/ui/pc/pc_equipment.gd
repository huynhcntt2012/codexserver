extends "res://scripts/ui/pc/pc_kit.gd"
## PC equipment ("TRANG BỊ"): category menu on the left; the hero on a podium in
## the middle, wearing its wings, halo and pet, with the seven loadout slots around it and the hero switcher; on the
## right the hero's stats (segmented bars) and the owned-item list with rarity,
## stars and a TRANG BỊ button. Only real data: catalog items, the demo/server
## inventory and the hero stats from characters.json (items give no stat bonus).
signal navigate(destination: String)
const SLOTS := [["hat", "Mũ"], ["wings", "Cánh"], ["outfit", "Trang phục"], ["bomb_skin", "Bom skin"], ["effect", "Hiệu ứng nổ"], ["pet", "Pet"], ["accessory", "Phụ kiện"]]
const LEFT_SLOTS := ["hat", "wings", "outfit", "pet"]
const RIGHT_SLOTS := ["bomb_skin", "effect", "accessory"]
const TABS := [["", "Tất cả"], ["wings", "Cánh"], ["pet", "Pet"], ["outfit", "Tr.Phục"], ["bomb_skin", "Bom"], ["effect", "Hiệu ứng"], ["accessory", "Phụ kiện"]]
const STATS := [["speed", "Tốc độ", "res://assets/items/shoe.png", Color("ffbe3c")], ["bombs", "Số bom", "res://assets/items/extra_bomb.png", Color("3aa6e6")], ["range", "Tầm nổ", "res://assets/items/flame.png", Color("ff6959")]]
const STAT_MAX := 5
const RARITY := {"common": ["Thường", Color("8fa3bf"), 1], "rare": ["Hiếm", Color("3aa6e6"), 2], "epic": ["Epic", Color("a98bf0"), 3], "legendary": ["Huyền thoại", Color("f4738d"), 3]}
const HeroPreview := preload("res://scripts/ui/hero_preview.gd")
const PANEL := Color("1567ae")
const PANEL_EDGE := Color("74d3f0")

var parts: Dictionary
var category := ""
var saved: Dictionary = {}
var hero_art: Control
var hero_name: Label
var hero_desc: Label
var stat_bars: Dictionary = {}  # key -> {segments: Array[Panel], value: Label}
var equipped_count: Label
var slot_icons: Dictionary = {}
var slot_names: Dictionary = {}
var menu: Dictionary = {}
var tabs: Dictionary = {}
var grid: GridContainer
var empty: VBoxContainer
var list_count: Label

func _init() -> void:
	super("sky")

func _ready() -> void:
	name = "PcEquipment"
	setup()
	var root := page(canvas)
	if not embedded:
		parts = top_bar("Trang bị", func(): navigate.emit("home"), open_settings)
		root.add_child(parts.bar)
		var switch := sized(candy("Cửa hàng", func(): navigate.emit("shop"), "coral", 16), Vector2(120, 48))
		switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		parts.bar.add_child(switch)
		parts.bar.move_child(switch, (parts.title as Label).get_index() + 1)
	var body := row(14, root)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_menu(body)
	build_stage(body)
	build_right(body)
	build_modal()
	UIState.loadout_changed.connect(refresh)
	UIState.inventory_changed.connect(refresh)
	UIState.profile_changed.connect(_on_hero_changed)
	visibility_changed.connect(func(): if is_visible_in_tree(): refresh())
	saved = UIState.profile.get("loadout", {}).duplicate(true)
	refresh()

func blue_panel(parent: Control, pad := 12) -> PanelContainer:
	var holder := card(PANEL, PANEL_EDGE, 22, 4, pad)
	parent.add_child(holder)
	return holder

## Ribbon heading: star badge and white title on a coral pill.
func ribbon(value: String, parent: Control) -> HBoxContainer:
	var line := row(8, parent)
	var badge := card(SUN, Color.WHITE, 18, 3, 0)
	badge.custom_minimum_size = Vector2(36, 36)
	line.add_child(badge)
	badge.add_child(Glyph.new("star", Color.WHITE, 30))
	pill(value, CORAL, Color.WHITE, 17, line)
	return line

func category_icon(key: String) -> Texture2D:
	for item in UIState.items:
		if str(item.get("category", "")) == key:
			return icon_texture(str(item.get("icon", "")))
	return null

# ------------------------------------------------------------------ left menu

func build_menu(body: Control) -> void:
	var holder := blue_panel(body, 10)
	holder.custom_minimum_size = Vector2(196, 0)
	var stack := column(8, holder)
	for spec in [["", "Tất cả"]] + SLOTS:
		var key: String = spec[0]
		var entry := candy("", func(): set_category(key), "ghost", 15)
		entry.name = "Menu_" + (key if key != "" else "all")
		entry.custom_minimum_size = Vector2(0, 54)
		entry.toggle_mode = true
		entry.add_theme_stylebox_override("normal", lipped(Color("0f4f8f"), Color("08284f"), 4))
		entry.add_theme_stylebox_override("hover", lipped(Color("1a62a8"), Color("08284f"), 4))
		entry.add_theme_stylebox_override("pressed", lipped(SUN, Color("e39b14"), 4))
		entry.add_theme_stylebox_override("hover_pressed", lipped(SUN.lightened(0.08), Color("e39b14"), 4))
		for state in ["font_color", "font_hover_color", "font_focus_color"]:
			entry.add_theme_color_override(state, Color.WHITE)
		stack.add_child(entry)
		var line := row(8, entry)
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 10
		line.offset_bottom = -4
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = category_icon(key)
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if key == "":
			line.add_child(Glyph.new("star", Color.WHITE, 32))
		else:
			line.add_child(icon)
		var label := text(spec[1], 17, Color.WHITE, line)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_vertical = Control.SIZE_FILL
		menu[key] = {"button": entry, "label": label}
	spacer(stack, true)
	var undo := candy("Hoàn tác", undo_loadout, "ghost", 16)
	undo.name = "Undo"
	undo.tooltip_text = "Về lần lưu trước"
	undo.custom_minimum_size = Vector2(0, 46)
	stack.add_child(undo)
	var save := candy("LƯU", save_loadout, "mint", 19)
	save.name = "Save"
	save.custom_minimum_size = Vector2(0, 50)
	stack.add_child(save)

# ------------------------------------------------------------------ stage

func build_stage(body: Control) -> void:
	var holder := card(Color("dff3ff"), PANEL_EDGE, 26, 4, 12)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_stretch_ratio = 1.0
	body.add_child(holder)
	# The kit's sky scene behind the hero, clipped to the rounded card.
	holder.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	holder.add_child(Backdrop.new("sky"))
	var stack := column(8, holder)
	var middle := row(10, stack)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var left := column(10, middle)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.z_index = 1  # slot cards stay above the hero's wings
	for key in LEFT_SLOTS:
		left.add_child(slot_card(key))
	# Hero stands on a glowing podium in front of a soft spotlight.
	var center := Control.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.custom_minimum_size = Vector2(280, 330)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(center)
	var glow := Panel.new()
	glow.add_theme_stylebox_override("panel", box(Color(1, 1, 1, 0.35), Color.TRANSPARENT, 150, 0, 0))
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.anchor_left = 0.08
	glow.anchor_right = 0.92
	glow.anchor_top = 0.04
	glow.anchor_bottom = 0.8
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(glow)
	for ring in [[0.04, 0.96, 0.73, 0.88, Color("4fb7f5"), Color("2b88cf")], [0.14, 0.86, 0.71, 0.81, Color("bff3ff"), Color("8fe3f3")]]:
		var disc := Panel.new()
		var style := box(ring[4], ring[5], 60, 4, 0)
		style.shadow_color = Color(0.3, 0.8, 1.0, 0.45)
		style.shadow_size = 12
		disc.add_theme_stylebox_override("panel", style)
		disc.anchor_left = ring[0]
		disc.anchor_right = ring[1]
		disc.anchor_top = ring[2]
		disc.anchor_bottom = ring[3]
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(disc)
	hero_art = HeroPreview.new()
	hero_art.name = "HeroArt"
	hero_art.anchor_left = 0.0
	hero_art.anchor_right = 1.0
	# The portrait's feet end on the podium; the halo uses the room above.
	hero_art.anchor_top = 0.0
	hero_art.anchor_bottom = 0.87
	center.add_child(hero_art)
	var right := column(10, middle)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.z_index = 1
	for key in RIGHT_SLOTS:
		right.add_child(slot_card(key))
	var plate := card(NAVY, PANEL_EDGE, 22, 3, 6)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.custom_minimum_size = Vector2(340, 0)
	stack.add_child(plate)
	var switch := row(8, plate)
	switch.add_child(round_icon("left", func(): cycle_hero(-1), "sun", 42))
	hero_name = title_text("", 26, Color.WHITE)
	hero_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	switch.add_child(hero_name)
	switch.add_child(round_icon("right", func(): cycle_hero(1), "sun", 42))
	hero_desc = text("", 14, MUTED, stack)
	hero_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

## One loadout slot: lavender label tab, item art on white, item name or "Trống".
func slot_card(key: String) -> Control:
	var label := ""
	for spec in SLOTS:
		if spec[0] == key:
			label = spec[1]
	var holder := column(0)
	var tag := pill(label, LAVENDER, Color.WHITE, 13)
	tag.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.add_child(tag.get_parent())
	var slot := candy("", func(): set_category(key), "ghost", 12)
	slot.name = "Slot_" + key
	slot.custom_minimum_size = Vector2(118, 84)
	slot.tooltip_text = label + " · bấm để xem vật phẩm loại này"
	holder.add_child(slot)
	var inner := column(2)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_top = 6
	inner.offset_bottom = -12
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(inner)
	var icon := picture("", Vector2(48, 48))
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(icon)
	var caption := text("Trống", 12, MUTED, inner)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.clip_text = true
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	slot_icons[key] = icon
	slot_names[key] = caption
	return holder

# ------------------------------------------------------------------ right side

func build_right(body: Control) -> void:
	var side := column(12, body)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 1.35
	var stats := blue_panel(side, 12)
	var stats_stack := column(8, stats)
	var head := row(8, stats_stack)
	ribbon("THÔNG SỐ NHÂN VẬT", head)
	spacer(head)
	equipped_count = pill("", NAVY, Color.WHITE, 14, head)
	var sheet := card(Color("eef8ff"), Color.WHITE, 16, 2, 10)
	stats_stack.add_child(sheet)
	var lines := column(8, sheet)
	for spec in STATS:
		var line := row(10, lines)
		line.add_child(picture(spec[2], Vector2(32, 32)))
		var name_label := text(spec[1], 16, INK, line)
		name_label.custom_minimum_size = Vector2(80, 0)
		var track := HBoxContainer.new()
		track.add_theme_constant_override("separation", 3)
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(track)
		var segments: Array[Panel] = []
		for i in STAT_MAX:
			var segment := Panel.new()
			segment.custom_minimum_size = Vector2(0, 18)
			segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
			track.add_child(segment)
			segments.append(segment)
		var value := text("", 16, INK, line)
		value.custom_minimum_size = Vector2(44, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat_bars[spec[0]] = {"segments": segments, "value": value, "color": spec[3]}
	var list := blue_panel(side, 12)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list_stack := column(10, list)
	var list_head := row(8, list_stack)
	ribbon("DANH SÁCH TRANG BỊ", list_head)
	list_count = text("", 13, Color("cfeeff"), list_head)
	spacer(list_head)
	var group := ButtonGroup.new()
	for spec in TABS:
		var key: String = spec[0]
		var button := tab(spec[1], func(): set_category(key), group)
		button.custom_minimum_size = Vector2(0, 36)
		button.button_pressed = key == category
		list_head.add_child(button)
		tabs[key] = button
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_stack.add_child(scroll)
	var content := column(12, scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid = GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	empty = column(12, content)
	var none := text("Chưa có vật phẩm loại này.", 18, Color.WHITE, empty)
	none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var go := sized(candy("Mở cửa hàng", func(): navigate.emit("shop"), "coral", 18), Vector2(200, 52))
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	empty.add_child(go)

func set_category(key: String) -> void:
	category = key
	for tab_key in tabs:
		(tabs[tab_key] as Button).set_pressed_no_signal(tab_key == key)
	for menu_key in menu:
		(menu[menu_key].button as Button).set_pressed_no_signal(menu_key == key)
		(menu[menu_key].label as Label).add_theme_color_override("font_color", Color("6b3d10") if menu_key == key else Color.WHITE)
	refresh()

func owned_items() -> Array:
	var found := []
	for item in UIState.items:
		var cat := str(item.get("category", ""))
		if cat in UIState.SLOTS and UIState.owned(str(item.id)) and (category == "" or cat == category):
			found.append(item)
	return found

func refresh() -> void:
	if grid == null:
		return
	if menu.has(category) and not (menu[category].button as Button).button_pressed:
		set_category(category)
		return
	var hero := str(UIState.profile.get("selected_character", "bombo"))
	if not parts.is_empty():
		refresh_top_bar(parts, hero)
	var info := UIState.get_character(hero)
	hero_art.show_hero(hero, UIState.profile.get("loadout", {}))
	hero_name.text = str(info.get("name", hero)).capitalize()
	hero_desc.text = str(info.get("desc", ""))
	for key in stat_bars:
		var bar: Dictionary = stat_bars[key]
		var value := clampi(int(info.get("stats", {}).get(key, 0)), 0, STAT_MAX)
		for i in STAT_MAX:
			var segment: Panel = bar.segments[i]
			var lit: bool = i < value
			segment.add_theme_stylebox_override("panel", box(bar.color if lit else Color("c9d8e8"), bar.color.darkened(0.25) if lit else Color.TRANSPARENT, 6, 2 if lit else 0))
		(bar.value as Label).text = "%d/%d" % [value, STAT_MAX]
	var loadout: Dictionary = UIState.profile.get("loadout", {})
	var worn := 0
	for key in slot_icons:
		var item := UIState.get_item(str(loadout.get(key, "")))
		(slot_icons[key] as TextureRect).texture = icon_texture(str(item.get("icon", "")))
		(slot_names[key] as Label).text = str(item.get("name", "Trống")) if not item.is_empty() else "Trống"
		(slot_names[key] as Label).tooltip_text = (slot_names[key] as Label).text
		worn += 0 if item.is_empty() else 1
	equipped_count.text = "Đang mặc %d/%d" % [worn, SLOTS.size()]
	for child in grid.get_children():
		child.queue_free()
	var shown := owned_items()
	for item in shown:
		grid.add_child(item_tile(item, hero))
	list_count.text = "%d vật phẩm" % shown.size()
	empty.visible = shown.is_empty()

## Item card: art on a soft tile, rarity badge, stars, then the action button.
func item_tile(item: Dictionary, hero: String) -> PanelContainer:
	var id := str(item.id)
	var bound := str(item.get("character_id", ""))
	var in_use := UIState.equipped(id)
	var locked := bound != "" and bound != hero
	var rarity: Array = RARITY.get(str(item.get("rarity", "common")), RARITY.common)
	var tile := card(Color("e9fbff") if not in_use else Color("e3fbef"), MINT if in_use else Color("b8e9f7"), 16, 3, 6)
	tile.name = "Own_" + id
	tile.custom_minimum_size = Vector2(0, 176)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.tooltip_text = "%s · %s" % [str(item.get("name", "")), rarity[0]]
	var stack := column(4, tile)
	var top := row(4, stack)
	spacer(top)
	if str(item.get("rarity", "common")) != "common":
		pill(rarity[0], rarity[1], Color.WHITE, 11, top)
	else:
		top.custom_minimum_size = Vector2(0, 20)
	var icon := picture(str(item.get("icon", "")), Vector2(70, 70))
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(icon)
	var stars := text("★".repeat(int(rarity[2])), 15, SUN, stack)
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stars.add_theme_color_override("font_outline_color", Color("b0700a"))
	stars.add_theme_constant_override("outline_size", 3)
	var title := text(str(item.get("name", "")), 12, INK, stack)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Taking an item off shows the hero as it was before the item.
	var slot := str(item.get("category", ""))
	var action := candy("THÁO" if in_use else "TRANG BỊ", (func(): UIState.unequip(slot)) if in_use else (func(): equip(id)), "coral" if in_use else "mint", 13)
	action.name = "Equip"
	action.custom_minimum_size = Vector2(0, 34)
	if in_use:
		action.tooltip_text = "Đang trang bị · bấm để tháo"
	elif locked:
		action.text = "Chỉ cho " + bound.to_upper()
		action.disabled = true
	stack.add_child(action)
	return tile

func equip(id: String) -> void:
	if UIState.equipped(id):
		UIState.toast_requested.emit("Vật phẩm đang được dùng")
		return
	UIState.equip(id)

func save_loadout() -> void:
	saved = UIState.profile.get("loadout", {}).duplicate(true)
	UIState.toast_requested.emit("Đã lưu trang bị (dữ liệu demo trên máy)")

func undo_loadout() -> void:
	UIState.profile["loadout"] = saved.duplicate(true)
	UIState.loadout_changed.emit()
	UIState.toast_requested.emit("Đã hoàn tác về lần lưu trước")

func cycle_hero(step: int) -> void:
	var ids: Array = UIState.characters.map(func(c): return str(c.id))
	var current := ids.find(str(UIState.profile.get("selected_character", "")))
	UIState.choose_hero(ids[posmod(current + step, ids.size())])

## Each hero keeps its own loadout, so the undo point follows the hero.
func _on_hero_changed() -> void:
	saved = UIState.profile.get("loadout", {}).duplicate(true)
	refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		if modal.visible:
			get_viewport().set_input_as_handled()
			close_modal()
		elif not embedded:
			get_viewport().set_input_as_handled()
			navigate.emit("home")
