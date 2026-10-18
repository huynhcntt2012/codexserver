extends RefCounted
## Battle HUD parts shared by the practice and online battle screens
## (docs/BATTLE_ITEMS.md): the "VẬT PHẨM" panel for the sidebar (selected item,
## count, cooldown, Ctrl DÙNG, Q THÚ CƯỠI) and the "CÁ NHÂN" quick slot bar 1-6.
## View only: `render(view)` takes the state from the practice rules or from the
## server snapshot; buttons call back into the screen that owns the rules.

const SLOTS := ["throw_bomb", "dart", "blue_shield", "speed_shoes", "freeze_bomb", "push_glove"]
const SHORT := {
	"throw_bomb": "Bom ném xa",
	"dart": "Phi tiêu",
	"blue_shield": "Khiên",
	"speed_shoes": "Tăng tốc",
	"freeze_bomb": "Đóng băng",
	"push_glove": "Đẩy bom",
}
const TITLE := {
	"throw_bomb": "BOM NÉM XA",
	"dart": "PHI TIÊU KÍCH NỔ",
	"blue_shield": "KHIÊN BẢO VỆ",
	"speed_shoes": "GIÀY TĂNG TỐC",
	"freeze_bomb": "BOM ĐÓNG BĂNG",
	"push_glove": "GĂNG ĐẨY BOM",
}
const REACH := {
	"throw_bomb": "Tầm tác dụng: 3 ô",
	"dart": "Tầm bay: 5 ô · chạm bom là nổ",
	"blue_shield": "Chặn 1 lần trúng bom · 8 giây",
	"speed_shoes": "+35% tốc độ · 5 giây",
	"freeze_bomb": "Làm chậm vùng 3×3 · 3 giây",
	"push_glove": "Đẩy bom phía trước",
}
const FALLBACK_ICON := {
	"throw_bomb": "res://assets/items/range.png",
	"dart": "res://assets/items/lightning.png",
	"blue_shield": "res://assets/items/shield.png",
	"speed_shoes": "res://assets/items/shoe.png",
	"freeze_bomb": "res://assets/items/ice.png",
	"push_glove": "res://assets/items/magnet.png",
}
const SELECTED := Color("ffd23c")
const SLOT_SIDE := 58.0

var kit: Control
var on_select: Callable
var on_use: Callable
var on_mount: Callable
var slots: Array[Dictionary] = []
var panel: PanelContainer
var active_icon: TextureRect
var active_count: Label
var active_name: Label
var active_reach: Label
var active_cooldown: Label
var use_button: Button
var mount_button: Button
var pet_icon: TextureRect
var pet_name: Label
var pet_state: Label

func _init(owner_kit: Control, select_action: Callable, use_action: Callable, mount_action: Callable) -> void:
	kit = owner_kit
	on_select = select_action
	on_use = use_action
	on_mount = mount_action

static func icon_path(id: String) -> String:
	var item: Dictionary = UIState.get_item(id)
	var path := str(item.get("icon", ""))
	return path if path != "" else str(FALLBACK_ICON.get(id, ""))

## Sidebar panel "VẬT PHẨM" (below the player list).
func build_panel(parent: Control) -> PanelContainer:
	panel = kit.card(Color("0d3f78"), Color("74d3f0"), 16, 3, 8)
	panel.name = "BattleItemPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(panel)
	var stack: VBoxContainer = kit.column(6, panel)
	kit.text("VẬT PHẨM", 13, Color("9fd7ff"), stack)
	var top: HBoxContainer = kit.row(8, stack)
	# Plain Control holder so the count badge can sit on the frame's corner.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(60, 60)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(holder)
	var frame: PanelContainer = kit.card(Color("e9f6ff"), SELECTED, 12, 3, 2)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(frame)
	active_icon = kit.picture("", Vector2(52, 52))
	frame.add_child(active_icon)
	active_count = kit.title_text("", 16, Color.WHITE, holder)
	active_count.add_theme_constant_override("outline_size", 6)
	active_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	active_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	active_count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	active_count.offset_right = -4
	var words: VBoxContainer = kit.column(-2, top)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_name = kit.stretch(kit.title_text("", 15, Color.WHITE, words))
	active_reach = kit.stretch(kit.text("", 11, Color("d5f3ff"), words))
	active_cooldown = kit.stretch(kit.text("", 12, Color("7ff0c2"), words))
	var buttons: HBoxContainer = kit.row(6, stack)
	use_button = kit.candy("Ctrl  DÙNG", func(): on_use.call(), "sun", 14)
	use_button.name = "UseItem"
	use_button.tooltip_text = "Dùng vật phẩm đang chọn theo hướng nhìn (Ctrl)"
	use_button.focus_mode = Control.FOCUS_NONE
	use_button.custom_minimum_size = Vector2(0, 38)
	use_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(use_button)
	mount_button = kit.candy("Q  THÚ CƯỠI", func(): on_mount.call(), "mint", 14)
	mount_button.name = "Mount"
	mount_button.tooltip_text = "Lên / xuống thú cưỡi (Q): +25% tốc độ, đỡ 1 lần trúng bom"
	mount_button.focus_mode = Control.FOCUS_NONE
	mount_button.custom_minimum_size = Vector2(0, 38)
	mount_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(mount_button)
	var pet_line: HBoxContainer = kit.row(6, stack)
	pet_icon = kit.picture("", Vector2(28, 28))
	pet_line.add_child(pet_icon)
	var pet_words: VBoxContainer = kit.column(-4, pet_line)
	pet_words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pet_name = kit.stretch(kit.text("", 12, Color.WHITE, pet_words))
	pet_state = kit.stretch(kit.text("", 11, Color("d5f3ff"), pet_words))
	return panel

## Bottom quick slot bar "CÁ NHÂN" with six slots on keys 1-6.
func build_bar(parent: Control) -> HBoxContainer:
	var line: HBoxContainer = kit.row(6, parent)
	line.name = "QuickSlotBar"
	var label: Label = kit.title_text("CÁ NHÂN", 16, Color.WHITE, line)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for i in SLOTS.size():
		var id: String = SLOTS[i]
		var slot := Button.new()
		slot.name = "QuickSlot%d" % (i + 1)
		slot.custom_minimum_size = Vector2(SLOT_SIDE, SLOT_SIDE)
		slot.focus_mode = Control.FOCUS_NONE
		slot.tooltip_text = "%d · %s\n%s" % [i + 1, TITLE[id].capitalize(), REACH[id]]
		slot.pressed.connect(func(): on_select.call(i))
		line.add_child(slot)
		var icon: TextureRect = kit.picture(icon_path(id), Vector2(SLOT_SIDE - 12, SLOT_SIDE - 12))
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		slot.add_child(icon)
		var shade := ColorRect.new()
		shade.color = Color(0.02, 0.06, 0.16, 0.62)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			shade.set_offset(side, 4.0 if side in [SIDE_LEFT, SIDE_TOP] else -4.0)
		slot.add_child(shade)
		var seconds: Label = kit.title_text("", 20, Color.WHITE, shade)
		seconds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		seconds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seconds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var hotkey: Label = kit.pill(str(i + 1), Color("0d2f5c"), Color.WHITE, 11, slot)
		var badge: PanelContainer = hotkey.get_parent()
		(badge.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 5
		(badge.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 5
		badge.position = Vector2(2, 2)
		var count: Label = kit.title_text("", 14, Color.WHITE, slot)
		count.add_theme_constant_override("outline_size", 6)
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		count.offset_right = -4
		slots.append({"button": slot, "icon": icon, "shade": shade, "seconds": seconds, "count": count, "style": ""})
	return line

func _slot_style(slot: Dictionary, state: String) -> void:
	if slot.style == state:
		return
	slot.style = state
	var fill := Color("e9f6ff")
	var edge := Color("9fd7ff")
	var width := 2
	if state == "selected":
		edge = SELECTED
		width = 4
	elif state == "empty":
		fill = Color("9aa6b8")
		edge = Color("6b7a9c")
	var button: Button = slot.button
	for name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var look: StyleBoxFlat = kit.box(fill.lightened(0.08) if name == "hover" else fill, edge, 12, width)
		button.add_theme_stylebox_override(name, look)

## view: {slots: [{id, count, cooldown (s), cooldown_total}], selected, pet,
## mounted, pet_used, shield, fast}.
func render(view: Dictionary) -> void:
	var states: Array = view.get("slots", [])
	var selected := int(view.get("selected", 0))
	for i in mini(slots.size(), states.size()):
		var slot: Dictionary = slots[i]
		var state: Dictionary = states[i]
		var count := int(state.get("count", 0))
		var left := float(state.get("cooldown", 0.0))
		(slot.count as Label).text = "x%d" % count
		(slot.icon as TextureRect).modulate = Color(0.55, 0.55, 0.55, 0.8) if count <= 0 else Color.WHITE
		(slot.shade as Control).visible = count > 0 and left > 0.0
		(slot.seconds as Label).text = "%d" % ceili(left) if left >= 1.0 else "%.1f" % left
		_slot_style(slot, "selected" if i == selected else ("empty" if count <= 0 else "ready"))
	if panel == null or selected >= states.size():
		return
	var current: Dictionary = states[selected]
	var id := str(current.get("id", SLOTS[selected]))
	var amount := int(current.get("count", 0))
	var wait := float(current.get("cooldown", 0.0))
	active_icon.texture = kit.icon_texture(icon_path(id))
	active_icon.modulate = Color(0.55, 0.55, 0.55) if amount <= 0 else Color.WHITE
	active_count.text = "x%d" % amount
	active_name.text = TITLE.get(id, id)
	active_reach.text = REACH.get(id, "")
	if amount <= 0:
		active_cooldown.text = "Hết vật phẩm · mua ở Cửa hàng"
		active_cooldown.add_theme_color_override("font_color", Color("ffb0ba"))
	elif wait > 0.0:
		active_cooldown.text = "Hồi chiêu: %.1f giây" % wait
		active_cooldown.add_theme_color_override("font_color", Color("ffe17b"))
	else:
		active_cooldown.text = "Cooldown: sẵn sàng"
		active_cooldown.add_theme_color_override("font_color", Color("7ff0c2"))
	use_button.disabled = amount <= 0 or wait > 0.0
	var pet := str(view.get("pet", ""))
	var mounted := bool(view.get("mounted", false))
	var used := bool(view.get("pet_used", false))
	mount_button.disabled = pet == "" or (used and not mounted)
	mount_button.text = "Q  XUỐNG THÚ" if mounted else "Q  THÚ CƯỠI"
	if pet == "":
		pet_icon.texture = null
		pet_name.text = "Chưa có thú cưỡi"
		pet_state.text = "Mua pet ở Cửa hàng để dùng phím Q"
		return
	var item: Dictionary = UIState.get_item(pet)
	pet_icon.texture = kit.icon_texture(str(item.get("icon", "")))
	pet_name.text = str(item.get("name", pet)).to_upper()
	pet_state.text = ("Đang cưỡi +25%" if mounted else "Chưa cưỡi") + " · Lá chắn: %s" % ("đã dùng" if used else "1 lượt")
	pet_state.tooltip_text = "Thú cưỡi: +25% tốc độ, chịu thay 1 lần trúng bom rồi biến mất tới ván sau"
