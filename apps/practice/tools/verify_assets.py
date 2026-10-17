"""Asset-only sanity check, without Godot executable.
Usage: python tools/verify_assets.py
"""
from pathlib import Path
import json
import re
from PIL import Image

root = Path(__file__).resolve().parents[1]
heroes = ['bombo','mimi','zin','lala','kai']
actions = ['idle','walk_down','walk_up','walk_left','walk_right','place_bomb','throw_item','hit','win','lose']
errors=[]
counts={'frames':0,'spritesheets':0,'png':0}
for h in heroes:
    p = root/'assets'/'spritesheets'/f'{h}.png'
    if not p.exists(): errors.append(f'Missing: {p}')
    else:
        im=Image.open(p)
        if im.size !=(128,640) or im.mode != 'RGBA': errors.append(f'Bad sheet: {p}')
        counts['spritesheets']+=1
    for action in actions:
        for frame in ['01','02']:
            p=root/'assets'/'characters'/h/action/f'{frame}.png'
            if not p.exists():errors.append(f'Missing {p}')
            elif Image.open(p).size != (64,64): errors.append(f'Wrong frame dimensions {p}')
            else: counts['frames']+=1
for p in (root/'assets').rglob('*.png'):
    counts['png']+=1
    try: Image.open(p).verify()
    except Exception as ex: errors.append(f'Corrupt PNG {p}: {ex}')
for rel in ['project.godot','scenes/main.tscn','scripts/game.gd','scripts/hero_sprite.gd','assets/backdrop.png','assets/tiles/grass/0_0.png','assets/bombs/water_blue.png']:
    if not (root/rel).is_file(): errors.append(f'Missing {rel}')
for gd in (root/'scripts').glob('*.gd'):
    source=gd.read_text(encoding='utf-8')
    for filename in re.findall(r'"(res://assets/[^"%]+\.png)"', source):
        if not (root/filename.removeprefix('res://')).exists():
            errors.append(f'Unresolved path in {gd.name}: {filename}')
if errors:
    print('\n'.join(errors))
    raise SystemExit(1)
print('PASS -',counts, '- all referenced fixed image paths found')
print('Note: This does not compile GDScript or execute Godot.')
