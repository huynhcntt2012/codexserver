import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BLOCK_MS,
  BossArena,
  bossHp,
  CHAIN_GAP,
  CHASE_MS,
  CHASER_CAST,
  DASH_BOMB_MS,
  DEFAULT_RULES,
  OVERHEAT_GAP,
  REACTOR_WAVE_GAP,
  ROBOT_RULES,
  ROBOT_SKILLS,
  SKILL_TIMING,
  TIRED_MS,
  WEAK_MS,
  type BossRules,
  type BossSkill,
  type RaidSummary,
} from '../src/boss.js';
import { FUSE_MS, Tile } from '../src/game.js';
import { MAPS } from '../src/maps.js';
import { parseRules } from '../src/boss_room.js';

/** Harbor (17 x 13): the boss footprint covers x 7-9, y 5-7. */
const harbor = MAPS.harbor!;

function raid(rules: Partial<BossRules> = {}, players = 1) {
  const g = new BossArena(harbor, { skills: [], ...rules }, 7);
  const ended: RaidSummary[] = [];
  g.onRaidEnd = (s) => ended.push(s);
  const ids = 'abcdefgh'.slice(0, players).split('');
  for (const id of ids) g.addPlayer(id, id.toUpperCase());
  for (const id of ids) g.input(id, 'ready');
  g.tick(3000);
  return { g, ended, p: g.players.get('a')! };
}

/** Puts a's bomb on (x, y), then steps a back to its spawn. */
function bombAt(g: BossArena, x: number, y: number, owner = 'a') {
  const p = g.players.get(owner)!;
  const home = [p.x, p.y];
  p.x = x;
  p.y = y;
  g.input(owner, 'bomb');
  g.tick(50);
  [p.x, p.y] = home as [number, number];
}

test('HP scales with the team when the raid starts: 1 000 solo, 4 850 for eight', () => {
  assert.equal(bossHp(DEFAULT_RULES, 1), 1000);
  assert.equal(bossHp(DEFAULT_RULES, 8), 4850);
  const solo = raid();
  assert.equal(solo.g.phase, 'playing'); // one player may start (min_players 1)
  assert.equal(solo.g.hpMax, 1000);
  assert.equal(raid({}, 8).g.hpMax, 4850);
});

test('eight seats: the ninth raider is refused; max_players from the event', () => {
  const g = new BossArena(harbor, {}, 1);
  for (const id of 'abcdefgh') assert.ok(g.addPlayer(id, id));
  assert.equal(g.addPlayer('i', 'i'), false);
  const small = new BossArena(harbor, { maxPlayers: 2 }, 1);
  assert.ok(small.addPlayer('a', 'a') && small.addPlayer('b', 'b'));
  assert.equal(small.addPlayer('c', 'c'), false);
});

test('a closed (paused / ended) event starts no raid', () => {
  const g = new BossArena(harbor, {}, 1);
  g.open = false;
  g.addPlayer('a', 'A');
  g.input('a', 'ready');
  g.tick(3000);
  assert.equal(g.phase, 'waiting');
  g.open = true;
  g.input('a', 'ready');
  g.tick(3000);
  assert.equal(g.phase, 'playing');
});

test('the footprint blocks walking and blasts; each bomb hurts once, chains included', () => {
  const { g } = raid({}, 2);
  assert.ok(!g.isWalkable(8, 6) && !g.isWalkable(7, 5) && g.isWalkable(6, 5));
  // Two separate bombs (one per raider at a time): 50 each.
  bombAt(g, 7, 4, 'a');
  bombAt(g, 9, 4, 'b');
  g.tick(FUSE_MS);
  assert.equal(g.hp, g.hpMax - 100);
  assert.equal(g.raid.get('a')!.damage, 50);
  // The blast stops at the boss: nothing burns on the far side.
  assert.ok(!g.flames.has('7,6') && !g.flames.has('8,5'));
  g.tick(600);
  // A chain (5,5) -> (6,5): only the second bomb reaches the boss, once.
  bombAt(g, 5, 5, 'a');
  bombAt(g, 6, 5, 'b');
  g.tick(FUSE_MS);
  assert.equal(g.hp, g.hpMax - 150);
  assert.equal(g.raid.get('b')!.damage, 100);
});

test('phases change once at 70 % and 35 %, never back', () => {
  const { g } = raid({ bombDamage: 350 });
  bombAt(g, 7, 4);
  g.tick(FUSE_MS);
  assert.deepEqual([g.hp, g.bossPhase, g.seq], [650, 2, 1]);
  g.tick(600);
  bombAt(g, 9, 4);
  g.tick(FUSE_MS);
  assert.deepEqual([g.hp, g.bossPhase, g.seq], [300, 3, 2]);
  // A single big hit crossing both thresholds still steps through each once.
  const big = raid({ bombDamage: 700 }).g;
  bombAt(big, 7, 4);
  big.tick(FUSE_MS);
  assert.deepEqual([big.bossPhase, big.seq], [3, 2]);
});

test('HP 0 before the clock: WIN from the server, with damage per raider', () => {
  const { g, ended } = raid({ baseHp: 60 }, 2);
  bombAt(g, 7, 4, 'a');
  bombAt(g, 9, 4, 'b');
  g.tick(FUSE_MS);
  assert.equal(g.phase, 'finished');
  assert.equal(ended[0]!.result, 'WIN');
  const hp = bossHp({ ...DEFAULT_RULES, baseHp: 60 }, 2); // 93
  assert.equal(ended[0]!.hpMax, hp);
  assert.deepEqual(
    ended[0]!.players.map((p) => [p.id, p.damage]),
    [
      ['a', 50],
      ['b', Math.min(50, hp - 50)],
    ],
  );
});

test('the clock runs out: TIMEOUT; everyone out: LOSE; everyone gone: ABORT', () => {
  const timeout = raid({ durationSeconds: 2 });
  timeout.g.tick(2100);
  assert.equal(timeout.ended[0]!.result, 'TIMEOUT');

  const lose = raid({ skills: ['boss_aoe_mark'] });
  lose.g.tick(1600); // first cast: AOE on the only raider
  assert.equal(lose.g.casts.length, 1);
  lose.g.tick(SKILL_TIMING.boss_aoe_mark.telegraph);
  assert.equal(lose.ended[0]!.result, 'LOSE');

  const abort = raid();
  abort.g.removePlayer('a');
  assert.equal(abort.ended[0]!.result, 'ABORT');
});

test('telegraphed tiles are the tiles that hit; stepping out in time is safe', () => {
  const { g, p } = raid({ skills: ['boss_aoe_mark'] });
  p.x = 1;
  p.y = 5;
  g.tick(1600);
  const cast = g.casts[0]!;
  assert.equal(cast.skill, 'boss_aoe_mark');
  assert.ok(cast.tiles.some(([x, y]) => x === 1 && y === 5));
  assert.equal(
    cast.resolveAt - cast.castAt,
    SKILL_TIMING.boss_aoe_mark.telegraph,
  );
  const snap = g.snapshot();
  assert.deepEqual(snap.boss.casts[0]!.tiles, cast.tiles);
  // Two steps right leaves the 3 x 3 mark before it resolves.
  g.input('a', 'right');
  g.tick(150);
  g.input('a', 'right');
  g.tick(150);
  assert.deepEqual([p.x, p.y], [3, 5]);
  g.tick(cast.resolveAt - g.now);
  assert.ok(p.alive);
  assert.equal(g.phase, 'playing');
});

test('a shield or the mount takes a boss hit', () => {
  const { g, p } = raid({ skills: ['boss_aoe_mark'] });
  g.gear.get('a')!.shieldUntil = g.now + 10_000;
  g.tick(1600 + SKILL_TIMING.boss_aoe_mark.telegraph);
  assert.ok(p.alive);
});

test('no cast without a way out: a boxed-in raider is never targeted', () => {
  const { g, p } = raid({ skills: ['boss_aoe_mark'] });
  // (1,1) with both exits walled in.
  g.grid[1]![2] = Tile.Wall;
  g.grid[2]![1] = Tile.Wall;
  assert.deepEqual([p.x, p.y], [1, 1]);
  assert.equal(g.plan('boss_aoe_mark'), null);
  g.tick(5000);
  assert.ok(p.alive && !g.casts.some((c) => c.skill === 'boss_aoe_mark'));
  // The basic hit around the boss is far from it: allowed.
  assert.ok(g.plan('boss_basic_hit'));
});

test('Block Lane raises walls for 3 s, then clears them', () => {
  const { g } = raid({ skills: ['boss_block_lane'] });
  g.bossPhase = 2; // a phase-2 skill
  g.tick(1600);
  const cast = g.casts[0]!;
  assert.equal(cast.skill, 'boss_block_lane');
  g.tick(SKILL_TIMING.boss_block_lane.telegraph);
  assert.ok(cast.tiles.every(([x, y]) => g.grid[y]![x] === Tile.Wall));
  g.tick(BLOCK_MS);
  assert.ok(cast.tiles.every(([x, y]) => g.grid[y]![x] === Tile.Floor));
});

test('Wave Push slides raiders in the warned band the warned way', () => {
  const { g, p } = raid({ skills: ['boss_wave_push'] });
  g.bossPhase = 2; // a phase-2 skill
  g.tick(1600);
  const cast = g.casts[0]!;
  const horizontal = cast.dir === 'left' || cast.dir === 'right';
  // A cell of the band with room to slide both ways.
  [p.x, p.y] = horizontal ? [3, 5] : [7, 3];
  const before = [p.x, p.y];
  g.tick(SKILL_TIMING.boss_wave_push.telegraph);
  const moved = [p.x - before[0]!, p.y - before[1]!];
  const expect = {
    left: [-2, 0],
    right: [2, 0],
    up: [0, -2],
    down: [0, 2],
  }[cast.dir!];
  // Walls can stop the slide early, never send it the other way.
  assert.ok(
    moved[0]! * expect[0]! >= 0 && moved[1]! * expect[1]! >= 0,
    `${cast.dir}: moved ${moved}`,
  );
  assert.ok(Math.abs(moved[0]!) + Math.abs(moved[1]!) <= 2);
});

test('the weak point takes x1.5 damage for 3 s (phase 3)', () => {
  const { g } = raid({
    skills: ['boss_weak_point'],
    phaseThresholds: [0.99, 0.98],
    bombDamage: 20,
  });
  bombAt(g, 7, 4);
  g.tick(FUSE_MS);
  assert.equal(g.bossPhase, 3);
  const cast = g.casts.find((c) => c.skill === 'boss_weak_point');
  assert.ok(cast, 'weak point cast in phase 3');
  assert.equal(
    cast.resolveAt - cast.castAt,
    SKILL_TIMING.boss_weak_point.telegraph,
  );
  g.tick(cast.resolveAt - g.now);
  assert.ok(g.weakUntil > g.now && g.weakUntil - g.now <= WEAK_MS);
  const hp = g.hp;
  bombAt(g, 9, 4);
  g.tick(FUSE_MS);
  assert.equal(hp - g.hp, 30);
});

test('item whitelist and mount switch come from the event', () => {
  const { g } = raid({ items: ['dart'], mount: false });
  assert.equal(g.input('a', 'use_throw_bomb'), false);
  assert.equal(g.input('a', 'use_dart'), true);
  assert.equal(g.input('a', 'mount'), false);
});

test('support actions and active time are tracked for reward eligibility', () => {
  const { g, ended } = raid({ items: ['blue_shield'] }, 2);
  g.gear.get('a')!.items.blue_shield = 1;
  g.input('a', 'use_blue_shield');
  g.tick(50);
  assert.equal(g.raid.get('a')!.support, 1);
  g.tick(1000);
  g.removePlayer('b');
  g.tick(1000);
  g.removePlayer('a');
  const [a, b] = ended[0]!.players;
  assert.equal(a!.activeMs, 2050);
  assert.equal(b!.activeMs, 1050);
  // Match EXP: a acted in phase 1; b never acted; nobody rescued anyone.
  assert.deepEqual([a!.phases, b!.phases, a!.rescues], [1, 0, 0]);
});

test('event rules from the API are clamped and checked', () => {
  const rules = parseRules('evt', {
    base_hp: 5,
    max_players: 20,
    min_players: 0,
    phase_thresholds: [0.35, 0.7, 2],
    skills: ['boss_aoe_mark', 'teleport'],
    duration_seconds: 99999,
    items: ['dart', 'laser'],
    map_id: 'harbor',
  });
  assert.equal(rules.baseHp, 50);
  assert.equal(rules.maxPlayers, 8);
  assert.equal(rules.minPlayers, 1);
  assert.deepEqual(rules.phaseThresholds, [0.7, 0.35]);
  assert.deepEqual(rules.skills, ['boss_aoe_mark']);
  assert.equal(rules.durationSeconds, 1800);
  assert.deepEqual(rules.items, ['dart']);
});

test('the snapshot carries the boss, casts and raid state', () => {
  const { g } = raid({ skills: ['boss_basic_hit'] });
  g.tick(1600);
  const snap = g.snapshot();
  assert.equal(snap.mode, 'boss');
  assert.deepEqual(
    [snap.boss.x, snap.boss.y, snap.boss.size, snap.boss.hp, snap.boss.phase],
    [7, 5, 3, 1000, 1],
  );
  assert.equal(snap.boss.casts[0]!.skill, 'boss_basic_hit');
  assert.equal(snap.raid.result, null);
});

// ------------------------------------------------------------ Clockwork Bomb Robot

/** The robot (2 x 2 at x 7-8, y 5-6 on Harbor) with one skill; walking off unless asked. */
function robot(skill: BossSkill | null, players = 1, walk = false) {
  const r = raid(
    { ...ROBOT_RULES, minPlayers: 1, skills: skill ? [skill] : [] },
    players,
  );
  if (!walk) r.g.rules.walkMs = 0;
  r.g.bossPhase = skill ? SKILL_TIMING[skill].phase : 1;
  return r;
}

const has = (tiles: [number, number][], x: number, y: number) =>
  tiles.some(([tx, ty]) => tx === x && ty === y);

test('robot preset: 2 x 2 footprint, spec HP 6 000 x (1 + 0.55 (n - 1)), factory floor', () => {
  const { g } = robot(null, 2);
  assert.equal(g.size, 2);
  assert.deepEqual([g.bossX, g.bossY], [7, 5]);
  assert.equal(g.hpMax, 9300);
  assert.equal(bossHp({ ...DEFAULT_RULES, ...ROBOT_RULES }, 6), 22500);
  assert.ok(!g.isWalkable(8, 6) && g.isWalkable(9, 6));
  // Pillars stay only on every fourth cell, the border stays closed.
  assert.equal(g.grid[2]![2], Tile.Wall);
  assert.equal(g.grid[2]![4], Tile.Floor);
  assert.equal(g.grid[0]![4], Tile.Wall);
  const snap = g.snapshot();
  assert.deepEqual(
    [snap.boss.size, snap.boss.facing, snap.boss.walkMs],
    [2, 'down', 0],
  );
});

test('robot skills open by phase: SK01-02, then SK03-04, then SK05-07', () => {
  const { g } = robot(null);
  g.rules.skills = [...ROBOT_SKILLS];
  assert.deepEqual(g.pool(), ['robot_bomb_launch', 'robot_bomb_chain']);
  g.bossPhase = 2;
  assert.deepEqual(g.pool(), ROBOT_SKILLS.slice(0, 4));
  g.bossPhase = 3;
  assert.deepEqual(g.pool(), [...ROBOT_SKILLS]);
});

test('SK01 Bomb Launch: one bomb 1-2 cells in front, its + of 2 is the warned set', () => {
  const { g, p } = robot('robot_bomb_launch');
  [p.x, p.y] = [8, 10]; // below the robot
  g.tick(1600);
  const cast = g.casts[0]!;
  assert.equal(cast.skill, 'robot_bomb_launch');
  assert.equal(g.facing, 'down');
  assert.equal(cast.resolveAt - cast.castAt, 1950);
  const [bx, by] = cast.bombs![0]!;
  assert.ok(by === 8 || by === 9, `lands 1-2 cells below: ${by}`);
  assert.deepEqual(cast.tiles, g.blast(bx, by, 2));
  // Stand on a warned cell (not the bomb) until it goes off.
  const [hx, hy] = cast.tiles.find(([x, y]) => x !== bx || y !== by)!;
  [p.x, p.y] = [hx, hy];
  const hp = g.hp;
  g.tick(cast.resolveAt - g.now);
  assert.equal(p.alive, false);
  assert.equal(g.hp, hp, 'its own bombs never hurt the robot');
  assert.ok(g.snapshot().flames.some((f) => f.x === bx && f.y === by));
});

test('robot blasts stop at walls, crates and the robot itself', () => {
  const { g } = robot(null);
  g.grid[3]![10] = Tile.Crate;
  const tiles = g.blast(10, 5, 2);
  assert.ok(!has(tiles, 10, 3) && has(tiles, 10, 4), 'crate stops it');
  assert.ok(!has(tiles, 8, 5), 'the robot stops it');
  assert.ok(!has(tiles, 9 - 1, 5));
  assert.ok(has(tiles, 9, 5) && has(tiles, 12, 5));
});

test('SK02 Bomb Chain: front, left and right bombs go off 0.4 s apart', () => {
  const { g, p } = robot('robot_bomb_chain');
  [p.x, p.y] = [8, 10];
  g.tick(1600);
  assert.equal(g.casts.length, 3);
  const times = g.casts.map((c) => c.resolveAt - c.castAt);
  assert.deepEqual(times, [2400, 2400 + CHAIN_GAP, 2400 + 2 * CHAIN_GAP]);
  assert.ok(g.casts.every((c) => c.bombs!.length === 1));
  // Out of the way; no new cast while the chain is on the board.
  [p.x, p.y] = [1, 1];
  g.tick(2400);
  assert.equal(g.casts.length, 2);
  g.tick(2 * CHAIN_GAP);
  assert.equal(g.casts.length, 0);
  assert.ok(p.alive);
});

test('SK03 Mini Chaser runs after its target, stops and warns 0.8 s before its + of 1', () => {
  const { g, p } = robot('robot_mini_chaser');
  [p.x, p.y] = [8, 11];
  g.tick(1600);
  const cast = g.casts[0]!;
  assert.equal(cast.skill, 'robot_mini_chaser');
  assert.deepEqual(cast.tiles, []);
  const start = cast.mini!;
  const distance = () =>
    Math.abs(cast.mini![0] - p.x) + Math.abs(cast.mini![1] - p.y);
  const before = distance();
  // Runs (one cell per 0.3 s) until it reaches its target or the chase ends.
  for (
    let t = 0;
    t < CHASER_CAST + CHASE_MS + 100 && !cast.tiles.length;
    t += 50
  )
    g.tick(50);
  assert.ok(cast.tiles.length > 0);
  assert.ok(distance() < before, `${start} -> ${cast.mini} closed in`);
  assert.equal(
    cast.resolveAt - g.now,
    SKILL_TIMING.robot_mini_chaser.telegraph,
  );
  const [mx, my] = cast.mini!;
  assert.deepEqual(cast.bombs, [[mx, my]]);
  assert.ok(has(cast.tiles, mx, my));
  // The snapshot shows the mini bomb where the server has it.
  assert.deepEqual(g.snapshot().boss.casts[0]!.mini, [mx, my]);
});

test('SK04 Recoil Dash: warned lane, raider in it is hit, bomb left on the start cells', () => {
  const { g, p } = robot('robot_recoil_dash', 2);
  const b = g.players.get('b')!;
  [p.x, p.y] = [7, 11]; // below: the robot dashes down columns 7-8
  [b.x, b.y] = [1, 1];
  g.tick(1600);
  const cast = g.casts[0]!;
  assert.equal(cast.skill, 'robot_recoil_dash');
  assert.equal(cast.dir, 'down');
  assert.equal(cast.resolveAt - cast.castAt, 900);
  const [tx, ty] = cast.to!;
  assert.ok(tx === 7 && ty - 5 >= 2 && ty - 5 <= 4, `${tx},${ty}`);
  assert.ok(has(cast.tiles, 8, ty + 1) && !has(cast.tiles, 8, 6));
  // b walks into the warned lane and stays there.
  [b.x, b.y] = [8, 7];
  g.tick(cast.resolveAt - g.now);
  assert.deepEqual([g.bossX, g.bossY], [tx, ty]);
  assert.equal(b.alive, false);
  assert.ok(g.movedAt === g.now && g.facing === 'down');
  const follow = g.casts[0]!;
  assert.equal(follow.skill, 'robot_recoil_dash');
  assert.deepEqual(follow.bombs, [[7, 5]]);
  assert.equal(follow.resolveAt - g.now, DASH_BOMB_MS);
  assert.ok(has(follow.tiles, 7, 5) && !g.isBoss(7, 5));
});

test('SK05 Magnet Pull: a + reaching 2 cells out of every side, after 2.2 s', () => {
  const { g } = robot('robot_magnet_pull');
  g.tick(1600);
  const cast = g.casts[0]!;
  assert.equal(cast.resolveAt - cast.castAt, 2200);
  for (const [x, y] of [
    [7, 4],
    [7, 3],
    [9, 5],
    [10, 5],
    [8, 7],
    [6, 5],
  ] as const)
    assert.ok(has(cast.tiles, x, y), `${x},${y}`);
  assert.ok(!has(cast.tiles, 9, 4), 'not the corners');
});

test('SK06 Overheat: eight bombs around the robot, warned 2.9 s, one after another', () => {
  const { g } = robot('robot_overheat');
  g.tick(1600);
  assert.equal(g.casts.length, 8);
  g.casts.forEach((c, i) =>
    assert.equal(c.resolveAt - c.castAt, 2900 + i * OVERHEAT_GAP),
  );
  const bombs = g.casts.map((c) => c.bombs![0]!);
  assert.equal(new Set(bombs.map((b) => b.join())).size, 8);
});

test('SK07 Reactor: two waves on rows then columns, safe lanes left, then tired', () => {
  const { g, p } = robot('robot_reactor');
  g.tick(1600);
  assert.equal(g.casts.length, 2);
  const [rows, cols] = g.casts;
  assert.equal(rows!.resolveAt - rows!.castAt, 3500);
  assert.equal(cols!.resolveAt - rows!.resolveAt, REACTOR_WAVE_GAP);
  const lines = new Set([...rows!.tiles, ...cols!.tiles].map((t) => t.join()));
  let floor = 0;
  for (let y = 0; y < g.grid.length; y++)
    for (let x = 0; x < g.grid[0]!.length; x++)
      if (g.grid[y]![x] === Tile.Floor && !g.isBoss(x, y)) floor++;
  assert.ok(lines.size < floor * 0.75, 'never the whole board');
  assert.ok(!has([...rows!.tiles, ...cols!.tiles], p.x, p.y) || p.alive);
  g.tick(rows!.resolveAt - g.now);
  assert.equal(g.weakUntil > g.now, false);
  g.tick(REACTOR_WAVE_GAP);
  assert.equal(g.weakUntil, g.now + TIRED_MS);
});

test('no robot cast without a way out: a boxed-in raider is never on a reactor line', () => {
  const { g, p } = robot('robot_reactor');
  g.grid[1]![2] = Tile.Wall;
  g.grid[2]![1] = Tile.Wall;
  assert.deepEqual([p.x, p.y], [1, 1]);
  for (let i = 0; i < 5; i++) {
    const waves = g.plan('robot_reactor');
    assert.ok(waves);
    assert.ok(waves.every((w) => !has(w.tiles, 1, 1)));
  }
});

test('the robot walks toward the team between casts, around pillars, up to crates', () => {
  const { g, p } = robot(null, 1, true);
  [p.x, p.y] = [7, 11];
  const gap = () =>
    Math.max(g.bossX - p.x, p.x - (g.bossX + 1), 0) +
    Math.max(g.bossY - p.y, p.y - (g.bossY + 1), 0);
  g.tick(1600);
  assert.deepEqual([g.bossX, g.bossY, g.facing], [7, 6, 'down']);
  assert.equal(g.movedAt, g.now);
  for (let i = 0; i < 10; i++) g.tick(ROBOT_RULES.walkMs!);
  // Close enough to throw: it stops 2 cells away.
  assert.equal(gap(), 2);
  assert.equal(g.snapshot().boss.y, g.bossY);
  // Walled off by crates (Harbor's x 10-11): it gets as close as it can.
  [p.x, p.y] = [15, 6];
  for (let i = 0; i < 20; i++) g.tick(ROBOT_RULES.walkMs!);
  assert.ok(g.bossX + 1 >= 9, `${g.bossX},${g.bossY}`);
});

test('robot event rules from the API: footprint and walk_ms are clamped', () => {
  const rules = parseRules('evt', {
    skills: ['robot_bomb_launch', 'robot_reactor', 'nope'],
    footprint: 9,
    walk_ms: -5,
  });
  assert.deepEqual(rules.skills, ['robot_bomb_launch', 'robot_reactor']);
  assert.equal(rules.footprint, 3);
  assert.equal(rules.walkMs, 0);
  assert.equal(parseRules('evt', { footprint: 2, walk_ms: 700 }).footprint, 2);
});
