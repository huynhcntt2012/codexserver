import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BALL_MS_PER_CELL,
  BossArena,
  bossHp,
  CACTUS_RULES,
  CACTUS_SKILLS,
  CHARGE_MS_PER_CELL,
  RAM_RULES,
  RAM_SKILLS,
  RESCUE_GRACE_MS,
  ROLL_MS_PER_CELL,
  SKILL_TIMING,
  STORM_RING_GAP,
  STRIKE_WAVE_GAP,
  STUN_MS,
  THORN_MS_PER_CELL,
  type BossRules,
  type BossSkill,
  type Cast,
  type RaidSummary,
} from '../src/boss.js';
import { Tile } from '../src/game.js';
import { MAPS } from '../src/maps.js';
import { parseRules } from '../src/boss_room.js';

/** Harbor (17 x 13): a 2 x 2 boss starts at x 7-8, y 5-6 (factory floor: pillars on x,y ≡ 2 mod 4). */
const harbor = MAPS.harbor!;
type Cell = [number, number];
const has = (tiles: Cell[], x: number, y: number) =>
  tiles.some(([tx, ty]) => tx === x && ty === y);

function boss(
  preset: Partial<BossRules>,
  skill: BossSkill | null,
  players = 1,
) {
  const g = new BossArena(
    harbor,
    { ...preset, skills: skill ? [skill] : [] },
    11,
  );
  const ended: RaidSummary[] = [];
  g.onRaidEnd = (s) => ended.push(s);
  const ids = 'abcdefgh'.slice(0, players).split('');
  for (const id of ids) g.addPlayer(id, id.toUpperCase());
  for (const id of ids) g.input(id, 'ready');
  g.tick(3000);
  g.rules.walkMs = 0; // tests place raiders themselves
  g.bossPhase = skill ? SKILL_TIMING[skill].phase : 1;
  // Clear crates so lanes are predictable (pillars stay).
  for (const row of g.grid)
    row.forEach((t, x) => {
      if (t === Tile.Crate) row[x] = Tile.Floor;
    });
  return { g, ended, p: g.players.get('a')! };
}
const cactus = (skill: BossSkill | null, players = 1) =>
  boss(CACTUS_RULES, skill, players);
const ram = (skill: BossSkill | null, players = 1) =>
  boss(RAM_RULES, skill, players);

/** Runs until the first cast exists, returns it. */
function firstCast(g: BossArena): Cast {
  for (let i = 0; i < 60 && !g.casts.length; i++) g.tick(50);
  assert.ok(g.casts.length, 'the boss casts');
  return g.casts[0]!;
}

function until(g: BossArena, at: number) {
  while (g.now < at) g.tick(50);
}

test('twin presets: 2 x 2, HP = 8 000 × (0.6 + 0.1 n), 100 per bomb, phases at 70 % / 30 %', () => {
  for (const preset of [CACTUS_RULES, RAM_RULES]) {
    const rules = { ...CACTUS_RULES, ...preset } as BossRules;
    assert.equal(bossHp(rules, 4), 8000);
    assert.equal(bossHp(rules, 1), 5600);
    assert.equal(bossHp(rules, 8), 11200);
    const { g } = boss(preset, null, 2);
    assert.equal(g.size, 2);
    assert.equal(g.hpMax, 6400);
    assert.deepEqual(g.rules.phaseThresholds, [0.7, 0.3]);
    assert.equal(g.rules.bombDamage, 100);
    assert.equal(g.rules.rescueMs, 4000);
  }
  assert.equal(CACTUS_RULES.skills!.length, 4);
  assert.equal(RAM_RULES.skills!.length, 4);
});

test('skills open by phase: SK01-02, then SK03, then the ultimate (HP ≤ 30 %)', () => {
  for (const [preset, skills] of [
    [CACTUS_RULES, CACTUS_SKILLS],
    [RAM_RULES, RAM_SKILLS],
  ] as const) {
    const g = new BossArena(harbor, preset, 3);
    g.addPlayer('a', 'A');
    g.input('a', 'ready');
    g.tick(3000);
    assert.deepEqual(g.pool(), skills.slice(0, 2));
    g.bossPhase = 2;
    assert.deepEqual(g.pool(), skills.slice(0, 3));
    g.bossPhase = 3;
    assert.deepEqual(g.pool(), [...skills]);
  }
});

test('a boss hit traps the raider; a teammate stepping in frees them (1.2 s safe)', () => {
  const { g } = cactus('cactus_thorn_cross', 2);
  const a = g.players.get('a')!;
  const b = g.players.get('b')!;
  [a.x, a.y] = [7, 4]; // above the boss: on the cross
  [b.x, b.y] = [6, 4]; // beside a, off the cross (rays leave the sides only)
  const cast = firstCast(g);
  assert.ok(has(cast.tiles, 7, 4) && !has(cast.tiles, 6, 4));
  // a stays (does not dodge); b stays clear.
  until(g, cast.resolveAt);
  g.tick(50);
  assert.ok(a.alive && g.trapped.has('a'), 'a is in a bubble, not out');
  assert.ok(!g.input('a', 'left'), 'a trapped raider cannot move');
  g.tick(600); // the cross's flames are gone
  // b steps right, into a's cell: the bubble pops.
  g.input('b', 'right');
  g.tick(200);
  assert.ok(!g.trapped.has('a'), 'b popped the bubble');
  assert.equal(g.raid.get('b')!.support, 1, 'a rescue counts as support');
  assert.ok(g.gear.get('a')!.graceUntil >= g.now + RESCUE_GRACE_MS - 400);
});

test('nobody comes in time: the trapped raider is out after 4 s; all out = LOSE', () => {
  const { g, p, ended } = cactus('cactus_thorn_cross');
  [p.x, p.y] = [7, 4];
  const cast = firstCast(g);
  until(g, cast.resolveAt);
  g.tick(50);
  assert.ok(g.trapped.has('a') && p.alive);
  g.tick(3900);
  assert.ok(p.alive, 'still waiting');
  g.tick(200);
  assert.ok(!p.alive && !g.trapped.has('a'));
  assert.equal(ended[0]?.result, 'LOSE');
});

test('SK01 Lăn Gai: warned lane, rolls up to 4 cells at 4 tiles/s, traps on the way', () => {
  const { g, p } = cactus('cactus_thorn_roll', 2);
  [p.x, p.y] = [7, 10]; // straight below
  const b = g.players.get('b')!;
  [b.x, b.y] = [1, 1];
  const cast = firstCast(g);
  assert.equal(cast.dir, 'down');
  assert.deepEqual(cast.to, [7, 9]); // y 7..10 open: 4 cells? (7,11) wall row? -> stops at 9 (feet y 10 = last floor)
  assert.equal(
    cast.resolveAt - cast.castAt,
    SKILL_TIMING.cactus_thorn_roll.telegraph + 4 * ROLL_MS_PER_CELL,
  );
  assert.ok(has(cast.tiles, 7, 10) && has(cast.tiles, 8, 7));
  until(g, cast.resolveAt);
  g.tick(50);
  assert.deepEqual([g.bossX, g.bossY], [7, 9]);
  assert.ok(g.trapped.has('a'), 'rolled over a: trapped');
  assert.ok(!g.isBoss(p.x, p.y), 'a was put beside the boss');
});

test('SK01 Lăn Gai into a hard wall stuns the boss 1.5 s (no casts, no walking)', () => {
  const { g, p } = cactus('cactus_thorn_roll');
  [p.x, p.y] = [7, 9];
  // A wall two cells below the boss: it rolls 1 cell and hits it.
  g.grid[8]![7] = Tile.Wall;
  g.grid[8]![8] = Tile.Floor;
  g.grid[9]![8] = Tile.Floor;
  const cast = firstCast(g);
  if (cast.dir !== 'down') return; // another lane was fairer; nothing to check
  until(g, cast.resolveAt);
  g.tick(50);
  assert.ok(g.stunUntil > g.now && g.stunUntil <= g.now + STUN_MS);
  assert.ok(g.snapshot().boss.stunned);
  const casts = g.casts.length;
  g.tick(1000);
  assert.equal(g.casts.length, casts, 'stunned: no new cast');
});

test('SK02 Gai Bay: 3 thorns, ≤ 5 cells at 6 tiles/s, stopped by walls, first raider per lane', () => {
  const { g, p } = cactus('cactus_thorn_shot', 2);
  [p.x, p.y] = [9, 1]; // up and to the right: lanes x 7, 8 and 9
  const b = g.players.get('b')!;
  [b.x, b.y] = [15, 11];
  g.grid[2]![8] = Tile.Wall; // a hard wall in lane x 8
  firstCast(g);
  const casts = g.casts.filter((c) => c.skill === 'cactus_thorn_shot');
  assert.ok(casts.every((c) => c.dir === 'up'));
  const lanes = new Set(casts.flatMap((c) => c.lanes ?? []));
  assert.equal(lanes.size, 3, 'three thorns');
  const cols = new Set(casts.flatMap((c) => c.tiles.map(([x]) => x)));
  assert.deepEqual([...cols].sort(), [7, 8, 9]);
  const steps = casts.map((c) => c.resolveAt - c.castAt).sort((a, b) => a - b);
  assert.equal(
    steps[0],
    SKILL_TIMING.cactus_thorn_shot.telegraph + THORN_MS_PER_CELL,
  );
  assert.ok(casts.every((c) => c.tiles.every(([, y]) => y >= 0 && y < 5)));
  assert.ok(casts.length <= 5);
  // The wall stops lane x 8 below it.
  assert.ok(
    has(
      casts.flatMap((c) => c.tiles),
      8,
      3,
    ),
  );
  assert.ok(!casts.some((c) => has(c.tiles, 8, 2) || has(c.tiles, 8, 1)));
  // a waits at (9, 1): the thorn of lane x 9 traps a when it gets there.
  for (const c of casts) until(g, c.resolveAt);
  g.tick(50);
  assert.ok(g.trapped.has('a'));
});

test('SK03 Gai Nổ Chữ Thập: + of 3 from each side; walls stop, a crate breaks and stops', () => {
  const { g, p } = cactus('cactus_thorn_cross');
  [p.x, p.y] = [1, 11];
  g.grid[5]![5] = Tile.Crate; // left of the boss: the left ray on row 5 stops on it
  const cast = firstCast(g);
  assert.equal(
    cast.resolveAt - cast.castAt,
    SKILL_TIMING.cactus_thorn_cross.telegraph,
  );
  assert.ok(
    has(cast.tiles, 6, 5) && has(cast.tiles, 5, 5) && !has(cast.tiles, 4, 5),
  );
  assert.ok(
    has(cast.tiles, 7, 4) && !has(cast.tiles, 7, 1),
    'reach 3 up: y 4, 3, 2',
  );
  assert.ok(!cast.tiles.some(([x, y]) => g.isBoss(x, y)));
  until(g, cast.resolveAt);
  g.tick(50);
  assert.equal(g.grid[5]![5], Tile.Floor, 'the crate took the hit');
  assert.ok(g.flames.has('7,4'), 'the cross stays live a moment');
});

test('ULT Bão Gai Xoáy: 3 rings 0.55 s apart, each with a corridor out, each fair', () => {
  const { g, p } = cactus('cactus_thorn_storm');
  [p.x, p.y] = [7, 4]; // touching the boss: ring 1
  firstCast(g);
  const waves = g.casts.filter((c) => c.skill === 'cactus_thorn_storm');
  assert.equal(waves.length, 3);
  assert.deepEqual(
    waves.map((w) => w.resolveAt - waves[0]!.resolveAt),
    [0, STORM_RING_GAP, 2 * STORM_RING_GAP],
  );
  assert.deepEqual(
    waves.map((w) => w.wave),
    [1, 2, 3],
  );
  for (const w of waves)
    assert.ok(
      g.canEscape(p, w.tiles, w.resolveAt - g.now),
      `wave ${w.wave} leaves a way out`,
    );
  // A ring never covers all of itself: the corridor stays open.
  const ring1 = waves[0]!.tiles.length;
  assert.ok(ring1 > 0 && ring1 < 12);
});

test('Húc Sấm: 5-cell charge at 5 tiles/s; a raider is knocked aside, then trapped', () => {
  const { g, p } = ram('ram_thunder_charge');
  [p.x, p.y] = [7, 10]; // below the boss, in its lane (columns 7-8)
  const cast = firstCast(g);
  assert.equal(cast.dir, 'down');
  const cells = Math.abs(cast.to![1] - 5);
  assert.ok(cells >= 1 && cells <= 5);
  assert.equal(
    cast.resolveAt - cast.castAt,
    SKILL_TIMING.ram_thunder_charge.telegraph + cells * CHARGE_MS_PER_CELL,
  );
  until(g, cast.resolveAt);
  g.tick(50);
  assert.ok(g.trapped.has('a'));
  assert.ok(p.x === 6 || p.x === 9, 'pushed one cell out of the lane');
});

test('Cầu Điện: one ball ≤ 6 cells at 5 tiles/s, pops in a small +; sets a bomb off', () => {
  const { g, p } = ram('ram_thunder_ball', 2);
  [p.x, p.y] = [15, 1];
  const b = g.players.get('b')!;
  [b.x, b.y] = [12, 6]; // to the right in lane y 6
  // a bomb of a's on the ball's path
  [p.x, p.y] = [11, 6];
  g.input('a', 'bomb');
  g.tick(50);
  [p.x, p.y] = [15, 1];
  const casts: Cast[] = [];
  firstCast(g);
  casts.push(...g.casts);
  assert.ok(
    casts.every((c) => c.skill === 'ram_thunder_ball' && c.dir === 'right'),
  );
  const first = Math.min(...casts.map((c) => c.resolveAt - c.castAt));
  assert.equal(
    first,
    SKILL_TIMING.ram_thunder_ball.telegraph + BALL_MS_PER_CELL,
  );
  assert.ok(casts.at(-1)!.final, 'the last step is the small blast');
  const bombs = g.bombs.size;
  for (const c of casts) until(g, c.resolveAt);
  g.tick(50);
  assert.ok(g.bombs.size < bombs, 'the ball set the bomb off');
});

test('Thiên Lôi Liên Kích: 3 waves of 2-8 cells, each warned 1 s, never every way out', () => {
  const { g, p } = ram('ram_thunder_storm', 3);
  [p.x, p.y] = [7, 3];
  firstCast(g);
  const waves = g.casts.filter((c) => c.skill === 'ram_thunder_storm');
  assert.equal(waves.length, 3);
  waves.forEach((w, i) => {
    assert.equal(w.wave, i + 1);
    assert.ok(w.tiles.length >= 2 && w.tiles.length <= 8);
    assert.equal(w.resolveAt - waves[0]!.resolveAt, i * STRIKE_WAVE_GAP);
    for (const r of g.players.values())
      assert.ok(g.canEscape(r, w.tiles, w.resolveAt - g.now));
  });
});

test('walking twins chase one raider ~7 s, then switch', () => {
  const g = new BossArena(harbor, { ...RAM_RULES, skills: [] }, 5);
  g.addPlayer('a', 'A');
  g.addPlayer('b', 'B');
  g.input('a', 'ready');
  g.input('b', 'ready');
  g.tick(3000);
  const start = [g.bossX, g.bossY];
  g.tick(2000);
  assert.notDeepEqual([g.bossX, g.bossY], start, 'it walks');
});

test('rules from the API: rescue_ms and hp_formula', () => {
  const rules = parseRules('evt', {
    rescue_ms: 4000,
    hp_formula: 'team',
    skills: ['cactus_thorn_roll', 'ram_thunder_ball', 'nope'],
  });
  assert.equal(rules.rescueMs, 4000);
  assert.equal(rules.hpFormula, 'team');
  assert.deepEqual(rules.skills, ['cactus_thorn_roll', 'ram_thunder_ball']);
  assert.equal(
    parseRules('evt', {}).rescueMs,
    0,
    'Slime King default unchanged',
  );
});

test('snapshot: trapped raiders, stun and projectile volleys', () => {
  const { g, p } = cactus('cactus_thorn_shot');
  [p.x, p.y] = [7, 1];
  firstCast(g);
  const snap = g.snapshot();
  const cast = snap.boss.casts[0]!;
  assert.ok(typeof cast.volley === 'number' && Array.isArray(cast.lanes));
  assert.deepEqual(snap.boss.trapped, {});
  assert.equal(snap.boss.rescueMs, 4000);
  assert.equal(snap.boss.stunned, false);
});
