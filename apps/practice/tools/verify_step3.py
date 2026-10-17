#!/usr/bin/env python3
"""Static validation of a stage 3 Godot 4 project and its maps/assets."""
from pathlib import Path
from collections import deque
import struct
import hashlib
import json, wave
ROOT=Path(__file__).resolve().parents[1]
HEROES='bombo mimi zin lala kai'.split()
DIRS=((0,1),(0,-1),(1,0),(-1,0))
errors=[]
def require(cond,message):
 if not cond:errors.append(message)

def path_is_open(lines,x,y):
 return 0<=y<len(lines) and 0<=x<len(lines[0]) and lines[y][x]=='.'

def escapes_from_corner(lines,sp):
 sx,sy=sp
 for dx,dy in DIRS:
  if not path_is_open(lines,sx+dx,sy+dy):continue
  # A single freshly planted bomb can be escaped when two or more steps
  # can carry a bot around a corner (off the initial cross).
  queue=deque([(sx,sy,0)])
  seen={(sx,sy)}
  while queue:
   x,y,d=queue.popleft()
   if d and x!=sx and y!=sy:return True
   if d>=4:continue
   for ddx,ddy in DIRS:
    p=(x+ddx,y+ddy)
    if p not in seen and path_is_open(lines,*p):
     seen.add(p);queue.append((*p,d+1))
  break
 return False

for level_id in ['park','frost','coast']+sorted(q.stem for q in (ROOT/'levels').glob('*.json') if q.stem not in ('park','frost','coast')):
 p=ROOT/'levels'/f'{level_id}.json';require(p.is_file(),f'Missing {p.name}')
 if not p.is_file():continue
 level=json.loads(p.read_text(encoding='utf-8'))
 lines=level['layout']
 cols,rows=level.get('columns',15),level.get('rows',11)
 require((cols,rows) in ((15,11),(17,13)) and len(lines)==rows and all(len(row)==cols for row in lines),f'Bad dimensions {level_id}')
 require(all(set(row).issubset(set('.#C')) for row in lines),f'Bad symbols {level_id}')
 for x,y in [tuple(s) for s in level['spawns']]:
  require(path_is_open(lines,x,y),f'Blocked spawn {level_id} {x,y}')
  require(any(path_is_open(lines,x+dx,y+dy) for dx,dy in DIRS),f'Trapped spawn {level_id} {x,y}')
  # Escapable when the first bomb goes at the spawn or on a neighbouring safe
  # cell (17x13 maps keep an L-shaped 3-cell start, like the arena server).
  starts=[(x,y)]+[(x+dx,y+dy) for dx,dy in DIRS if path_is_open(lines,x+dx,y+dy)]
  require(any(escapes_from_corner(lines,s) for s in starts),f'No bomb exit path {level_id} {x,y}')
 for kind in (level['crate'],level['wall']):
  require((ROOT/'assets/obstacles'/kind/'00.png').exists(),f'Missing obstacle {kind}')
 for y in range(2):
  for x in range(4):
    require((ROOT/'assets/tiles'/level['theme']/f'{y}_{x}.png').is_file(),f'Missing {level_id} floor {y}_{x}')
 require((ROOT/'assets/bombs'/f'{level["bomb"]}.png').exists(),f'Missing bomb {level_id}')
 require((ROOT/'assets/level_previews'/f'{level_id}.png').exists(),f'Missing preview {level_id}')
 print(f'PASS map: {level["name"]} | crates={sum(row.count("C") for row in lines)}')

for hero in HEROES:
 for direction in ('walk_down','walk_up','walk_left','walk_right'):
  for i in range(1,7):
   p=ROOT/'assets/animations'/hero/direction/f'{i:02d}.png'
   require(p.exists(),f'Missing animation {p}')
   if p.exists():
    png=p.read_bytes()
    require(png[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack(">II",png[16:24])==(64,64) and png[25]==6,f'Wrong sprite data {p}')
 for action in ('idle','hit','win','lose','place_bomb','throw_item'):
  for i in (1,2):
   require((ROOT/'assets/characters'/hero/action/f'{i:02d}.png').exists(),f'Missing animation {hero}/{action}/{i}')
print('PASS sprites: 120 extra movement PNGs; 5 complete characters')

snd_ids='ui_select round_start footstep place_bomb bomb_tick explosion collect hit victory defeat music_loop'.split()
for name in snd_ids:
 p=ROOT/'assets/audio'/f'{name}.wav'
 require(p.exists(),f'Missing sound {name}')
 if p.exists():
  with wave.open(str(p)) as w:
   require(w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==22050,f'Invalid WAV {name}')
print('PASS audio: 11 synthesized 16-bit/22.05kHz mono WAVs')
for f in ('project.godot','scenes/main.tscn','scripts/game.gd','scripts/hero_sprite.gd','tests/headless_smoke.gd'):
 require((ROOT/f).exists(),f'Missing source {f}')
manifest=json.loads((ROOT/"PROVENANCE.json").read_text())
for name,digest in manifest["files"].items():
 require(hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,f"Changed source asset {name}")
if errors:
 for error in errors:print('FAIL:',error)
 raise SystemExit(f'FAIL: {len(errors)} error(s)')
print('PASS project: all static asset and map checks passed')
