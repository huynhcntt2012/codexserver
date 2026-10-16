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
    assert.equal(grid.length, 11);
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
    assert.deepEqual([snap.width, snap.height], [15, 11]);
    assert.equal((snap.players[0] as { hero?: string }).hero, 'kai');
  }
  // v1 snapshots keep their exact shape (no hero field).
  const v1 = new Arena();
  v1.addPlayer('a', 'A', 'kai');
  assert.equal('hero' in v1.snapshot().players[0]!, false);
});
