# Game Boom — Starter 2D Art Pack

Original, AI-generated 2D artwork inspired by the _genre_ of tile-based cartoon bomber games. Not copied from the proprietary game Boom Online.

## Contents

- `characters/portraits/`: 5 character portraits at 160×160 pixels.
- `characters/<name>/<state>/`: 5 heroes × 10 action/pose categories × 2 pose images at 64×64 pixels. State names: idle, walk_down, walk_up, walk_left, walk_right, place_bomb, throw_item, hit, win, lose.
- `bombs/`: six bomb variants, each 96×96 pixels.
- `effects/`: four effect sequences, each with eight 96×96 snippets.
- `tiles/`: four floor themes, 8 tiles per theme at 64×64 pixels.
- `obstacles/`: wood crates, stone walls, special walls, shrubs, barrels and metal barrels.
- `items/`: 16 power-up icon crops (some contain pale UI-panel backgrounds).
- `decorations/`: 8 illustrated environment props.
- `ui/`: HUD and menu panel samples.
- `SOURCE_*.png`: the two original whole-sheet concepts for artistic reference.

## Godot 4 integration

Copy this folder to `res://assets/boom/`. Use a 64×64 grid size; for character movement, you can create `AnimatedSprite2D` animations by importing images from individual state folders. Set texture filtering to Linear for painterly/smooth images, or choose Nearest if you pixelate your game consistently.

## Limitations

These are starter art assets, extracted from a generative concept sheet, **not final production sprites**. Pose pairs are not guaranteed to be frame-perfect and some frames need manual retouching, transparency cleanup or registration for polished animations. UI items may include pale panels and Vietnamese labels. Character states (especially up/back views) should be visually tested in engine. Confirm final consistency and branding before release.

Counts by group: {"characters/portraits": 5, "characters/bombo/idle": 2, "characters/bombo/walk_down": 2, "characters/bombo/walk_up": 2, "characters/bombo/walk_left": 2, "characters/bombo/walk_right": 2, "characters/bombo/place_bomb": 2, "characters/bombo/throw_item": 2, "characters/bombo/hit": 2, "characters/bombo/win": 2, "characters/bombo/lose": 2, "characters/mimi/idle": 2, "characters/mimi/walk_down": 2, "characters/mimi/walk_up": 2, "characters/mimi/walk_left": 2, "characters/mimi/walk_right": 2, "characters/mimi/place_bomb": 2, "characters/mimi/throw_item": 2, "characters/mimi/hit": 2, "characters/mimi/win": 2, "characters/mimi/lose": 2, "characters/zin/idle": 2, "characters/zin/walk_down": 2, "characters/zin/walk_up": 2, "characters/zin/walk_left": 2, "characters/zin/walk_right": 2, "characters/zin/place_bomb": 2, "characters/zin/throw_item": 2, "characters/zin/hit": 2, "characters/zin/win": 2, "characters/zin/lose": 2, "characters/lala/idle": 2, "characters/lala/walk_down": 2, "characters/lala/walk_up": 2, "characters/lala/walk_left": 2, "characters/lala/walk_right": 2, "characters/lala/place_bomb": 2, "characters/lala/throw_item": 2, "characters/lala/hit": 2, "characters/lala/win": 2, "characters/lala/lose": 2, "characters/kai/idle": 2, "characters/kai/walk_down": 2, "characters/kai/walk_up": 2, "characters/kai/walk_left": 2, "characters/kai/walk_right": 2, "characters/kai/place_bomb": 2, "characters/kai/throw_item": 2, "characters/kai/hit": 2, "characters/kai/win": 2, "characters/kai/lose": 2, "bombs": 7, "effects/fire_horizontal": 8, "effects/fire_vertical": 8, "effects/ice": 8, "effects/heart": 8, "tiles/grass": 8, "tiles/snow": 8, "tiles/sand": 8, "tiles/lava": 8, "obstacles/wood_crate": 6, "obstacles/stone_wall": 4, "obstacles/special_wall": 4, "obstacles/shrub": 4, "obstacles/barrel": 6, "obstacles/metal_barrel": 4, "effects/water_splash": 6, "decorations": 8, "ui": 5, "items": 16}
