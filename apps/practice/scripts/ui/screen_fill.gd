extends RefCounted
## PC menus expand to any monitor or browser-window aspect; gameplay keeps its
## 1280×920 frame.

static func set_fill(tree: SceneTree, fill: bool) -> void:
	if tree == null:
		return
	var aspect := Window.CONTENT_SCALE_ASPECT_EXPAND if fill else Window.CONTENT_SCALE_ASPECT_KEEP
	if tree.root.content_scale_aspect != aspect:
		tree.root.content_scale_aspect = aspect
