import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BLOCK_MS,
  BossArena,
  bossHp,
  DEFAULT_RULES,
  SKILL_TIMING,
  WEAK_MS,
  type BossRules,
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
