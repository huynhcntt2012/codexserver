extends SceneTree
## Draws assets/map_previews/<id>.png for every bundled level: floor tiles,
## the map's walls and crates (scripts/map_blocks.gd, same pick per cell as in
## a round) and four heroes on their spawns, at CELL px per tile. The original
## assets/level_previews (source assets in PROVENANCE.json) stay as they were.
## Usage: godot --headless --path . --script res://tools/render_level_previews.gd
const MapBlocks := preload("res://scripts/map_blocks.gd")
const CELL := 32
const HEROES := ["bombo", "mimi", "lala", "zin"]

func image_of(path: String, side: int) -> Image:
	var image: Image = (load(path) as Texture2D).get_image()
	image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(side, side * image.get_height() / image.get_width(), Image.INTERPOLATE_LANCZOS)
	return image

func _init():
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/map_previews"))
	for file in DirAccess.get_files_at("res://levels"):
		if not file.ends_with(".json"):
			continue
		var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/" + file))
		var columns := int(level.columns)
		var rows := int(level.rows)
		var out := Image.create(columns * CELL, rows * CELL, false, Image.FORMAT_RGBA8)
		var floors := []
		for n in 2:
			for m in 4:
				floors.append(image_of("res://assets/tiles/%s/%d_%d.png" % [level.theme, n, m], CELL))
		var props := {}
		for kind in ["wall", "crate"]:
			for name in MapBlocks.names(level, kind):
				props[name] = image_of(MapBlocks.path(name), CELL)
		for y in rows:
			for x in columns:
				var ground: Image = floors[(y % 2) * 4 + ((x + y) % 4)]
				out.blit_rect(ground, Rect2i(Vector2i.ZERO, ground.get_size()), Vector2i(x, y) * CELL)
		# Row by row, so a tall prop overlaps the cell above it as in a round.
		for y in rows:
			var line: String = level.layout[y]
			for x in columns:
				var kind := "wall" if line[x] == "#" else ("crate" if line[x] == "C" else "")
				if kind == "":
					continue
				var piece: Image = props[MapBlocks.pick(level, kind, Vector2i(x, y))]
				out.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(x * CELL, (y + 1) * CELL - piece.get_height()))
		for i in mini(HEROES.size(), level.spawns.size()):
			var hero := image_of("res://assets/characters/%s/idle/01.png" % HEROES[i], CELL)
			var spot := Vector2i(int(level.spawns[i][0]), int(level.spawns[i][1]))
			out.blend_rect(hero, Rect2i(Vector2i.ZERO, hero.get_size()), Vector2i(spot.x * CELL, (spot.y + 1) * CELL - hero.get_height()))
		out.save_png(ProjectSettings.globalize_path("res://assets/map_previews/%s.png" % level.id))
		print("preview ", level.id)
	quit()
