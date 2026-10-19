import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  Arena,
  createMap,
  Tile,
  SPAWNS,
  FUSE_MS,
  FLAME_MS,
  ROUND_MS,
  createLayoutMap,
  type RoundResult,
} from '../src/game.js';
import { MAPS } from '../src/maps.js';

function playing() {
  const g = new Arena();
  g.addPlayer('a', 'Suni');
  g.addPlayer('b', 'Mochi');
  g.input('a', 'ready');
  g.input('b', 'ready');
  g.tick(3000);
  return g;
}
function act(g: Arena, id: string, action: unknown, ms = 150) {
  g.input(id, action);
  g.tick(ms);
}

test('original map is 15 x 13, enclosed, with eight distinct safe spawns', () => {
  const grid = createMap();
  assert.equal(grid.length, 13);
  assert.ok(grid.every((row) => row.length === 15));
  for (let y = 0; y < 13; y++) {
    assert.equal(grid[y]![0], Tile.Wall);
    assert.equal(grid[y]![14], Tile.Wall);
  }
  assert.ok(grid[0]!.every((t) => t === Tile.Wall));
  assert.ok(grid[12]!.every((t) => t === Tile.Wall));
  assert.equal(new Set(SPAWNS.map((s) => s.join(','))).size, 8);
  for (const [x, y] of SPAWNS) assert.equal(grid[y]![x], Tile.Floor);
});
test('eight-player cap and freed slot reuse; no joining after countdown', () => {
  const g = new Arena();
  for (let i = 0; i < 8; i++) assert.ok(g.addPlayer(String(i), 'Pilot'));
  assert.equal(g.addPlayer('extra', 'Pilot'), false);
  g.removePlayer('2');
  assert.ok(g.addPlayer('replacement', 'Pilot'));
  assert.equal(g.players.get('replacement')!.slot, 2);
  for (const id of g.players.keys()) g.input(id, 'ready');
  assert.equal(g.phase, 'countdown');
  assert.equal(g.addPlayer('late', 'Pilot'), false);
});
test('requires two players ready; countdown disconnect cancels readiness', () => {
  const g = new Arena();
  g.addPlayer('a', 'Suni');
  g.input('a', 'ready');
  g.tick(4000);
  assert.equal(g.phase, 'waiting');
  g.addPlayer('b', 'Mochi');
  g.input('b', 'ready');
  assert.equal(g.phase, 'countdown');
  g.removePlayer('b');
  assert.equal(g.phase, 'waiting');
  assert.equal(g.players.get('a')!.ready, false);
});
test('rejects fabricated state, unknown sessions and input before play', () => {
  const g = new Arena();
  g.addPlayer('a', 'Suni');
  assert.equal(g.input('a', 'right'), false);
  assert.equal(g.input('a', { x: 12, winner: 'a' }), false);
  assert.equal(g.input('fake', 'bomb'), false);
});
test('walls, crates, occupied cells and arena bounds block movement', () => {
  const g = playing();
  const p = g.players.get('a')!;
  act(g, 'a', 'left');
  assert.equal(p.x, 1);
  g.grid[1]![2] = Tile.Crate;
  act(g, 'a', 'right');
  assert.equal(p.x, 1);
  g.grid[1]![2] = Tile.Floor;
  Object.assign(g.players.get('b')!, { x: 2, y: 1 });
  act(g, 'a', 'right');
  assert.equal(p.x, 1);
  assert.equal(g.isWalkable(-1, 0), false);
  assert.equal(g.isWalkable(15, 13), false);
});
test('spam cannot increase move speed or create multiple bombs', () => {
  const g = playing();
  for (let i = 0; i < 100; i++) g.input('a', 'right');
  g.tick();
  assert.equal(g.players.get('a')!.x, 2);
  act(g, 'a', 'right', 50);
  assert.equal(g.players.get('a')!.x, 2);
  act(g, 'a', 'right', 100);
  assert.equal(g.players.get('a')!.x, 3);
  act(g, 'a', 'bomb');
  act(g, 'a', 'left');
  act(g, 'a', 'bomb');
  assert.equal(g.bombs.size, 1);
});
test('owner may leave a bomb but cannot walk back through it', () => {
  const g = playing();
  act(g, 'a', 'bomb');
  act(g, 'a', 'right');
  act(g, 'a', 'left');
  assert.equal(g.players.get('a')!.x, 2);
});
test('fuse, four-direction blast, wall blocking, crate destruction and flame expiry', () => {
  const g = playing();
  for (let y = 1; y < 12; y++)
    for (let x = 1; x < 14; x++) g.grid[y]![x] = Tile.Floor;
  Object.assign(g.players.get('a')!, { x: 7, y: 5 });
  g.grid[5]![8] = Tile.Crate;
  g.grid[4]![7] = Tile.Wall;
  act(g, 'a', 'bomb');
  Object.assign(g.players.get('a')!, { x: 1, y: 1 });
  g.tick(FUSE_MS - 1);
  assert.equal(g.bombs.size, 1);
  g.tick(1);
  assert.equal(g.bombs.size, 0);
  assert.equal(g.grid[5]![8], Tile.Floor);
  for (const k of ['7,5', '8,5', '6,5', '5,5', '7,6', '7,7'])
    assert.ok(g.flames.has(k), k);
  for (const k of ['9,5', '7,4', '7,3', '4,5'])
    assert.equal(g.flames.has(k), false, k);
  g.tick(FLAME_MS);
  assert.equal(g.flames.size, 0);
});
test('chain reactions detonate immediately, without recursive cycles', () => {
  const g = playing();
  g.bombs.set(10, { id: 10, owner: 'a', x: 3, y: 1, explodeAt: g.now + 50 });
  g.bombs.set(11, { id: 11, owner: 'b', x: 5, y: 1, explodeAt: g.now + 1000 });
  g.grid[1]![4] = Tile.Floor;
  g.grid[1]![5] = Tile.Floor;
  g.tick();
  assert.equal(g.bombs.size, 0);
  assert.ok(g.flames.has('5,1'));
});
test('same-tick deaths resolve to draw, never a premature winner', () => {
  const g = playing();
  for (const p of g.players.values())
    g.bombs.set(p.slot, {
      id: p.slot,
      owner: p.id,
      x: p.x,
      y: p.y,
      explodeAt: g.now + 50,
    });
  g.tick();
  assert.equal(g.phase, 'finished');
  assert.equal(g.winner, null);
  assert.equal(g.input('a', 'bomb'), false);
});
test('last survivor wins and the room resets to a fresh ready lobby', () => {
  const g = playing();
  act(g, 'a', 'bomb');
  g.tick(FUSE_MS);
  assert.equal(g.phase, 'finished');
  assert.equal(g.winner, 'b');
  g.tick(8000);
  assert.equal(g.phase, 'waiting');
  assert.equal(g.round, 2);
  assert.equal(g.players.get('a')!.alive, true);
  assert.equal(g.bombs.size, 0);
  assert.equal(g.players.get('b')!.ready, false);
});
test('entering a live flame is fatal; disconnection forfeits; timeout is draw', () => {
  const g = playing();
  g.flames.set('2,1', { x: 2, y: 1, expiresAt: g.now + 500 });
  act(g, 'a', 'right');
  assert.equal(g.winner, 'b');
  const h = playing();
  h.removePlayer('b');
  assert.equal(h.winner, 'a');
  const t = playing();
  t.tick(ROUND_MS);
  assert.equal(t.phase, 'finished');
  assert.equal(t.winner, null);
});

test('early movement is buffered once, latest direction wins, and cannot accelerate movement', () => {
  const g = playing();
  g.input('a', 'right');
  g.tick(50);
  assert.equal(g.players.get('a')!.x, 2);
  for (let i = 0; i < 100; i++) g.input('a', 'right');
  g.tick(50);
  assert.equal(g.players.get('a')!.x, 2);
  g.input('a', 'left');
  g.tick(50);
  assert.equal(g.players.get('a')!.x, 2);
  g.tick(50);
  assert.equal(g.players.get('a')!.x, 1);
  g.tick(500);
  assert.equal(g.players.get('a')!.x, 1);
});

test('buffer does not move disconnected players or survive a finished round', () => {
  const g = playing();
  g.input('a', 'right');
  g.tick(50);
  g.input('a', 'right');
  g.tick(50);
  g.removePlayer('a');
  g.tick(8000);
  assert.equal(g.phase, 'waiting');
  g.addPlayer('a', 'Again');
  g.input('a', 'ready');
  g.input('b', 'ready');
  g.tick(3000);
  g.tick(500);
  assert.equal(g.players.get('a')!.x, 1);
});
test('round stats credit bombs and knockouts outside the snapshot', () => {
  const g = playing();
  let result: RoundResult | null = null;
  g.onRoundEnd = (value) => (result = value);
  const a = g.players.get('a')!;
  const b = g.players.get('b')!;
  // Mochi stands beside Suni's bomb; Suni is moved out of the blast.
  [b.x, b.y] = [a.x + 1, a.y];
  act(g, 'a', 'bomb', 50);
  [a.x, a.y] = SPAWNS[1];
  g.tick(FUSE_MS);
  assert.equal(g.phase, 'finished');
  const done = result as RoundResult | null;
  assert.ok(done);
  assert.equal(done.winner, 'a');
  assert.deepEqual(
    done.players.map((p) => [p.name, p.placement, p.bombs, p.kills, p.winner]),
    [
      ['Suni', 1, 1, 1, true],
      ['Mochi', 2, 0, 0, false],
    ],
  );
  const snapshot = g.snapshot();
  assert.ok(snapshot.players.every((p) => !('kills' in p)));
  assert.ok(snapshot.flames.every((f) => !('owner' in f)));
});

test('v2 maps match the PC level files and keep every spawn safe', async () => {
  assert.equal(Object.keys(MAPS).length, 15);
  const { readFileSync } = await import('node:fs');
  for (const map of Object.values(MAPS)) {
    const level = JSON.parse(
      readFileSync(
        new URL(`../../practice/levels/${map.id}.json`, import.meta.url),
        'utf8',
      ),
    ) as { layout: string[]; name: string; columns: number; rows: number };
    assert.deepEqual([...map.layout], level.layout);
    assert.equal(map.name, level.name);
    assert.deepEqual([map.width, map.height], [level.columns, level.rows]);
    const grid = createLayoutMap(map);
    assert.equal(grid.length, map.height);
    assert.ok(grid.every((row) => row.length === map.width));
    assert.equal(new Set(map.spawns.map((s) => s.join(','))).size, 8);
    for (const [x, y] of map.spawns) {
      assert.equal(grid[y]![x], Tile.Floor);
      // Escape corridor: at least two walkable neighbours.
      const open = [
        [1, 0],
        [-1, 0],
        [0, 1],
        [0, -1],
      ].filter(([dx, dy]) => grid[y + dy!]![x + dx!] === Tile.Floor);
      assert.ok(open.length >= 1, `${map.id} spawn ${x},${y}`);
    }
    const g = new Arena(map);
    for (let i = 0; i < 8; i++) assert.ok(g.addPlayer(`p${i}`, `P${i}`, 'kai'));
    assert.equal(g.addPlayer('p9', 'P9'), false);
    const snap = g.snapshot();
    assert.deepEqual([snap.width, snap.height], [map.width, map.height]);
    assert.equal((snap.players[0] as { hero?: string }).hero, 'kai');
  }
  // v1 snapshots keep their exact shape (no hero field).
  const v1 = new Arena();
  v1.addPlayer('a', 'A', 'kai');
  assert.equal('hero' in v1.snapshot().players[0]!, false);
});

test('server bots plant bombs, escape their own blasts and only send intents', async () => {
  const { BotBrain, danger } = await import('../src/bots.js');
  let seed = 7;
  const random = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 2 ** 32;
  let survived = 0;
  let planted = 0;
  for (const mapId of ['park', 'frost', 'pastry', 'moon']) {
    const g = new Arena(MAPS[mapId]!);
    g.addPlayer('bot', 'Bot', 'kai');
    g.addPlayer('far', 'Far', 'mimi');
    g.input('bot', 'ready');
    g.input('far', 'ready');
    g.tick(3000);
    const brain = new BotBrain('bot', random);
    let bombs = 0;
    for (let t = 0; t < 400 && g.phase === 'playing'; t++) {
      const action = brain.think(g);
      if (action) g.input('bot', action);
      g.tick();
      bombs = Math.max(bombs, g.stats.get('bot')?.bombs ?? 0);
    }
    planted += bombs;
    const bot = g.players.get('bot')!;
    // Alive after 20 s, or killed by someone else's flame (never stuck in its own).
    if (bot.alive) survived++;
    assert.ok(!danger(g).has(`${bot.x},${bot.y}`) || !bot.alive);
  }
  assert.ok(planted >= 4, `bots planted ${planted} bombs`);
  assert.equal(survived, 4);
});

test('v2 items: throw, dart, shield, speed, freeze, push and the mount follow the rules', () => {
  // Open test map: walls only on the border and even-even pillars.
  const map = {
    ...MAPS.park!,
    id: 'test',
    layout: MAPS.park!.layout.map((row) => row.replace(/C/g, '.')),
  };
  const g = new Arena(map);
  g.addPlayer('a', 'A');
  g.addPlayer('b', 'B');
  const used: string[] = [];
  g.onItemUsed = (_id, item) => used.push(item);
  g.setLoadout(
    'a',
    {
      throw_bomb: 1,
      dart: 2,
      blue_shield: 1,
      speed_shoes: 1,
      freeze_bomb: 1,
      push_glove: 1,
    },
    'pet_bunny',
  );
  g.input('a', 'ready');
  g.input('b', 'ready');
  g.tick(3000);
  const a = g.players.get('a')!;
  const b = g.players.get('b')!;
  const gear = g.gear.get('a')!;
  // A pet owner starts the round riding; Q gets off and back on.
  assert.ok(gear.mounted && !g.gear.get('b')!.mounted);
  act(g, 'a', 'mount', 50);
  assert.ok(!gear.mounted);
  // Face right from (1,1): a move sets the facing.
  act(g, 'a', 'right');
  assert.equal(gear.facing, 'right');
  // Throw: lands 3 cells ahead, does not use the normal bomb.
  act(g, 'a', 'use_throw_bomb', 50);
  const thrown = [...g.bombs.values()].find((x) => x.thrown)!;
  assert.deepEqual([thrown.x, thrown.y], [a.x + 3, a.y]);
  assert.equal(gear.items.throw_bomb, 0);
  // Out of stock or on cooldown: nothing happens, nothing is reported.
  act(g, 'a', 'use_throw_bomb', 50);
  assert.equal([...g.bombs.values()].filter((x) => x.thrown).length, 1);
  act(g, 'a', 'bomb', 50);
  assert.equal(g.bombs.size, 2);
  // Dart: the thrown bomb on its path explodes at once.
  act(g, 'a', 'use_dart', 50);
  assert.ok(!g.bombs.has(thrown.id));
  assert.equal(gear.items.dart, 1);
  act(g, 'a', 'use_dart', 50); // still on cooldown (0.8 s)
  assert.equal(gear.items.dart, 1);
  // Shield: one hit absorbed. Stand on the own bomb's blast.
  act(g, 'a', 'use_blue_shield', 50);
  assert.ok(gear.shieldUntil > g.now);
  g.tick(2000);
  assert.ok(a.alive && gear.shieldUntil === 0);
  // Speed: shorter steps for 5 s.
  act(g, 'a', 'use_speed_shoes', 50);
  assert.ok(g.moveMs(a) < 150);
  // Freeze: B two cells ahead is slowed (after the last flames are gone).
  g.tick(600);
  b.x = a.x + 2;
  b.y = a.y;
  act(g, 'a', 'use_freeze_bomb', 50);
  assert.ok(g.moveMs(b) > 150);
  // Push: a bomb right in front slides until blocked.
  b.x = 13;
  b.y = 9;
  g.bombs.clear();
  g.bombs.set(99, {
    id: 99,
    owner: 'b',
    x: a.x + 1,
    y: a.y,
    explodeAt: g.now + 1500,
  });
  act(g, 'a', 'use_push_glove', 50);
  assert.ok(g.bombs.get(99)!.x > a.x + 1);
  // Mount: faster, absorbs one hit, then cannot be ridden again this round.
  act(g, 'a', 'mount', 50);
  assert.ok(gear.mounted);
  g.flames.set(`${a.x},${a.y}`, { x: a.x, y: a.y, expiresAt: g.now + 400 });
  g.tick(50);
  assert.ok(a.alive && !gear.mounted && gear.petUsed);
  act(g, 'a', 'mount', 50);
  assert.ok(!gear.mounted);
  assert.deepEqual(used, [
    'throw_bomb',
    'dart',
    'blue_shield',
    'speed_shoes',
    'freeze_bomb',
    'push_glove',
  ]);
  const view = g
    .snapshot()
    .players.find((p) => p.id === 'a') as unknown as Record<string, unknown>;
  assert.equal((view.items as Record<string, number>).dart, 1);
  assert.equal(view.petUsed, true);
});
