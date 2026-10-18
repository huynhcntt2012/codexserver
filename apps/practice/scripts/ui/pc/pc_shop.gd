extends "res://scripts/ui/pc/pc_kit.gd"
## PC shop ("SHOP"): category menu on the left; a striped awning and banner over
## the item grid (art, name, description, price, MUA); on the right the hero as
## shop mascot with a speech bubble about the selected item and its buy button.
## Wings and halos are tried on the mascot before buying.
## Purchases go through UIState (server wallet when signed in, demo wallet
## otherwise); there is no real payment and no invented discount.
signal navigate(destination: String)
const CATEGORIES := [
	["", "Tất cả"], ["consumable", "Vật phẩm"], ["outfit", "Trang phục"], ["hat", "Mũ"], ["wings", "Cánh"],
	["bomb_skin", "Skin bom"], ["effect", "Hiệu ứng"], ["pet", "Pet"], ["accessory", "Phụ kiện"],
]
const RARITY := {"common": ["Thường", Color("8fa3c0")], "rare": ["Hiếm", Color("4fb7f5")], "epic": ["Epic", Color("a98bf0")], "legendary": ["Huyền thoại", Color("ff7083")]}
const HeroPreview := preload("res://scripts/ui/hero_preview.gd")
const TRY_ON := ["hat", "wings"]
const PANEL := Color("1567ae")
const PANEL_EDGE := Color("74d3f0")

## Red and white scalloped shop awning.
class Awning extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 34)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var count := maxi(6, int(size.x / 70.0))
		var step := size.x / count
		var band := size.y * 0.5
		var drop := size.y - band
		for i in count:
			var fill := Color("ff6b7f") if i % 2 == 0 else Color.WHITE
			draw_rect(Rect2(i * step, 0, step, band), fill)
			# Scallop hanging below the band (lower half-ellipse).
			var points := PackedVector2Array()
			for k in 13:
				var angle := PI * k / 12.0
				points.append(Vector2(i * step + step / 2.0 + cos(angle) * step / 2.0, band + sin(angle) * drop))
			draw_colored_polygon(points, fill)
		draw_rect(Rect2(0, 0, size.x, 5), Color("d74d63"))

var parts: Dictionary
var category := ""
var selected := ""
var grid: GridContainer
var tiles: Dictionary = {}
var menu: Dictionary = {}
var preview_hero: Control
var preview_icon: TextureRect
var preview_name: Label
var preview_rarity: Label
var preview_price: Label
var preview_desc: Label
var buy_button: Button
var count_label: Label

func _init() -> void:
	super("candy")

func _ready() -> void:
	name = "PcShop"
	setup()
	var root := page(canvas)
	if not embedded:
		parts = top_bar("Cửa hàng", func(): navigate.emit("home"), open_settings)
		root.add_child(parts.bar)
		var switch := sized(candy("Trang bị", func(): navigate.emit("equipment"), "lavender", 16), Vector2(120, 48))
		switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		parts.bar.add_child(switch)
		parts.bar.move_child(switch, (parts.title as Label).get_index() + 1)
	var body := row(14, root)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	build_menu(body)
	build_store(body)
	build_mascot(body)
	build_modal()
	UIState.inventory_changed.connect(refresh)
	UIState.wallet_changed.connect(refresh)
	UIState.profile_changed.connect(refresh)
	UIState.loadout_changed.connect(refresh)
	visibility_changed.connect(func(): if is_visible_in_tree(): render_grid())
	render_grid()

func category_icon(key: String) -> Texture2D:
	for item in UIState.items:
		if str(item.get("category", "")) == key:
			return icon_texture(str(item.get("icon", "")))
	return null

# ------------------------------------------------------------------ left menu

func build_menu(body: Control) -> void:
	var holder := card(PANEL, PANEL_EDGE, 22, 4, 10)
	holder.custom_minimum_size = Vector2(196, 0)
	body.add_child(holder)
	var stack := column(8, holder)
	for entry in CATEGORIES:
		var key: String = entry[0]
		var button := candy("", func(): set_category(key), "ghost", 15)
		button.name = "Tab_" + (key if key != "" else "all")
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 52)
		button.add_theme_stylebox_override("normal", lipped(Color("0f4f8f"), Color("08284f"), 4))
		button.add_theme_stylebox_override("hover", lipped(Color("1a62a8"), Color("08284f"), 4))
		button.add_theme_stylebox_override("pressed", lipped(SUN, Color("e39b14"), 4))
		button.add_theme_stylebox_override("hover_pressed", lipped(SUN.lightened(0.08), Color("e39b14"), 4))
		stack.add_child(button)
		var line := row(8, button)
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 10
		line.offset_bottom = -4
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if key == "":
			line.add_child(Glyph.new("star", Color.WHITE, 32))
		else:
			var icon := TextureRect.new()
			icon.texture = category_icon(key)
			icon.custom_minimum_size = Vector2(34, 34)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(icon)
		var label := text(entry[1], 17, Color.WHITE, line)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_vertical = Control.SIZE_FILL
		menu[key] = {"button": button, "label": label}
	spacer(stack, true)
	var note := text("Không thanh toán thật.\nVàng/KC lấy từ ví tài khoản (hoặc ví demo khi chơi khách).", 11, Color("cfeeff"), stack)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

# ------------------------------------------------------------------ store front

func build_store(body: Control) -> void:
	var front := column(0, body)
	front.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	front.add_child(Awning.new())
	var holder := card(PANEL, PANEL_EDGE, 18, 4, 12)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	front.add_child(holder)
	var stack := column(12, holder)
	stack.add_child(banner())
	var head := row(8, stack)
	title_text("VẬT PHẨM", 18, Color.WHITE, head)
	count_label = text("", 13, Color("cfeeff"), head)
	count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

## Banner: candy sky, big title and a row of the game's own art.
func banner() -> Control:
	var holder := card(Color("ffb9d0"), Color.WHITE, 20, 4, 0)
	holder.custom_minimum_size = Vector2(0, 130)
	holder.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	holder.add_child(Backdrop.new("candy"))
	var line := row(14)
	holder.add_child(line)
	var margin := Control.new()
	margin.custom_minimum_size = Vector2(10, 0)
	line.add_child(margin)
	line.add_child(picture("res://assets/items/mystery.png", Vector2(96, 96)))
	var words := column(4, line)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := title_text("CỬA HÀNG BỤP BỤP!", 40, Color.WHITE, words)
	title.add_theme_color_override("font_outline_color", Color("d74d63"))
	title.add_theme_constant_override("outline_size", 14)
	pill("Trang phục · Skin bom · Hiệu ứng nổ · Vật phẩm", Color("ffcb52"), Color("8a4b1f"), 15, words)
	for art in ["res://assets/bombs/strong_black.png", "res://assets/bombs/star.png", "res://assets/bombs/pink.png", "res://assets/items/shield.png"]:
		var piece := picture(art, Vector2(74, 74))
		piece.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(piece)
	var tail := Control.new()
	tail.custom_minimum_size = Vector2(10, 0)
	line.add_child(tail)
	return holder

# ------------------------------------------------------------------ mascot

func build_mascot(body: Control) -> void:
	var side := column(8, body)
	side.custom_minimum_size = Vector2(300, 0)
	var bubble := card(Color.WHITE, Color("ffd0e1"), 30, 4, 12)
	side.add_child(bubble)
	var bubble_stack := column(4, bubble)
	preview_name = title_text("", 22, Color("d74d63"), bubble_stack)
	preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_desc = text("", 14, INK, bubble_stack)
	preview_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(300, 260)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(stage)
	preview_hero = HeroPreview.new()
	preview_hero.name = "PreviewHero"
	preview_hero.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(preview_hero)
	var badge := card(Color.WHITE, Color("ffd0e1"), 46, 4, 6)
	badge.anchor_left = 0.62
	badge.anchor_right = 0.62
	badge.anchor_top = 0.62
	badge.anchor_bottom = 0.62
	badge.custom_minimum_size = Vector2(92, 92)
	stage.add_child(badge)
	preview_icon = picture("", Vector2(76, 76))
	badge.add_child(preview_icon)
	var deal := card(PANEL, PANEL_EDGE, 20, 4, 10)
	side.add_child(deal)
	var deal_stack := column(8, deal)
	var deal_line := row(8, deal_stack)
	preview_rarity = pill("", MUTED, Color.WHITE, 13, deal_line)
	spacer(deal_line)
	preview_price = title_text("", 24, SUN, deal_line)
	buy_button = candy("", request_buy, "mint", 22)
	buy_button.name = "Buy"
	buy_button.custom_minimum_size = Vector2(0, 58)
	deal_stack.add_child(buy_button)

# ------------------------------------------------------------------ data

func items_in(key: String) -> Array:
	var found := []
	for item in UIState.items:
		if bool(item.get("shop_enabled", false)) and (key == "" or str(item.get("category", "")) == key):
			found.append(item)
	return found

func set_category(key: String) -> void:
	category = key
	render_grid()

func render_grid() -> void:
	if grid == null:
		return
	for key in menu:
		(menu[key].button as Button).set_pressed_no_signal(key == category)
		(menu[key].label as Label).add_theme_color_override("font_color", Color("6b3d10") if key == category else Color.WHITE)
	for child in grid.get_children():
		child.queue_free()
	tiles.clear()
	var shown := items_in(category)
	if not shown.is_empty() and not shown.any(func(item): return str(item.id) == selected):
		selected = str(shown[0].id)
	for item in shown:
		grid.add_child(item_tile(item))
	count_label.text = "%d món" % shown.size()
	refresh()

## Item card: art, name, short description, price pill and MUA.
func item_tile(item: Dictionary) -> PanelContainer:
	var id := str(item.id)
	var tile := card(Color("eef8ff"), Color("b8e9f7"), 16, 3, 6)
	tile.name = "Item_" + id
	tile.custom_minimum_size = Vector2(0, 214)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: select(id))
	var stack := column(3, tile)
	var top := row(4, stack)
	top.custom_minimum_size = Vector2(0, 20)
	spacer(top)
	var rarity := str(item.get("rarity", "common"))
	if rarity != "common":
		pill(RARITY.get(rarity, RARITY.common)[0], RARITY.get(rarity, RARITY.common)[1], Color.WHITE, 11, top)
	var icon := picture(str(item.get("icon", "")), Vector2(76, 76))
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(icon)
	var title := text(str(item.get("name", "")), 15, INK, stack)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var desc := text(str(item.get("description", "")), 11, MUTED, stack)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.clip_text = true
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.tooltip_text = desc.text
	var price_box := card(NAVY, Color("9fd7ff"), 14, 2, 2)
	price_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	price_box.custom_minimum_size = Vector2(110, 0)
	stack.add_child(price_box)
	var price_line := row(6, price_box)
	price_line.alignment = BoxContainer.ALIGNMENT_CENTER
	price_line.add_child(Glyph.new("gem" if str(item.get("currency", "gold")) == "gem" else "coin", Color.WHITE, 22))
	var price := text(grouped(int(item.get("price", 0))), 15, Color.WHITE, price_line)
	var buy := candy("MUA", func(): select(id); request_buy(), "mint", 14)
	buy.name = "Buy_" + id
	buy.custom_minimum_size = Vector2(0, 34)
	stack.add_child(buy)
	tiles[id] = {"button": tile, "price": price, "buy": buy}
	return tile

func select(id: String) -> void:
	selected = id
	refresh()

func price_text(item: Dictionary) -> String:
	return "%s %s" % [grouped(int(item.get("price", 0))), "KC" if str(item.get("currency", "gold")) == "gem" else "vàng"]

func owned_text(item: Dictionary) -> String:
	var id := str(item.id)
	if str(item.get("category", "")) == "consumable":
		var stock := int(UIState.profile.get("consumables", {}).get(id, 0))
		return "" if stock == 0 else "Trong kho: %d" % stock
	if UIState.equipped(id):
		return "Đang dùng"
	return "Đã sở hữu" if UIState.owned(id) else ""

func refresh() -> void:
	if grid == null:
		return
	var hero := str(UIState.profile.get("selected_character", "bombo"))
	if not parts.is_empty():
		refresh_top_bar(parts, hero)
	for id in tiles:
		var item := UIState.get_item(id)
		var consumable := str(item.get("category", "")) == "consumable"
		var owned := not consumable and UIState.owned(id)
		var buy: Button = tiles[id].buy
		buy.disabled = owned
		buy.text = owned_text(item).to_upper() if owned else ("MUA THÊM" if owned_text(item) != "" else "MUA")
		var style := tiles[id].button.get_theme_stylebox("panel") as StyleBoxFlat
		style.border_color = SUN if id == selected else Color("b8e9f7")
		style.set_border_width_all(4 if id == selected else 3)
		style.bg_color = Color("fff6dc") if id == selected else Color("eef8ff")
	var item := UIState.get_item(selected)
	var bound := str(item.get("character_id", ""))
	# The mascot wears the current loadout plus the selected wings/halo on trial.
	var look: Dictionary = UIState.profile.get("loadout", {}).duplicate()
	var slot := str(item.get("category", ""))
	var trying := slot in TRY_ON and not UIState.equipped(selected)
	if trying:
		look[slot] = selected
	preview_hero.show_hero(bound if bound != "" else hero, look)
	preview_icon.texture = icon_texture(str(item.get("icon", "")))
	preview_name.text = str(item.get("name", "Chọn vật phẩm"))
	var rarity: Array = RARITY.get(str(item.get("rarity", "")), RARITY.common)
	preview_rarity.text = rarity[0]
	(preview_rarity.get_parent().get_theme_stylebox("panel") as StyleBoxFlat).bg_color = rarity[1]
	preview_price.text = price_text(item) if not item.is_empty() else ""
	var note := str(item.get("description", ""))
	if bound != "":
		note += "\nChỉ dành cho " + bound.to_upper() + "."
	var stock := owned_text(item)
	if stock != "":
		note += "\n" + stock
	if trying:
		note += "\nĐang mặc thử" + (" · bấm MẶC NGAY để giữ" if UIState.owned(selected) else "")
	preview_desc.text = note
	var owned_already := not item.is_empty() and str(item.get("category", "")) != "consumable" and UIState.owned(selected)
	# A bought wing/halo can be put on from here, the try-on becoming the real look.
	var wear := owned_already and trying
	buy_button.disabled = item.is_empty() or (owned_already and not wear)
	buy_button.text = "MẶC NGAY" if wear else ("ĐÃ SỞ HỮU" if owned_already else ("MUA THÊM" if stock != "" else "MUA"))

func request_buy() -> void:
	var item := UIState.get_item(selected)
	if item.is_empty():
		return
	if str(item.get("category", "")) in TRY_ON and UIState.owned(selected):
		UIState.equip(selected)
		return
	notice("XÁC NHẬN MUA", "Mua %s với giá %s?\nKhông thanh toán bằng tiền thật." % [item.get("name", ""), price_text(item)], func(): UIState.buy(selected), "MUA")

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		if modal.visible:
			get_viewport().set_input_as_handled()
			close_modal()
		elif not embedded:
			get_viewport().set_input_as_handled()
			navigate.emit("home")
