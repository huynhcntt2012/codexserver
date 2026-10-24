/**
 * Writes boss raid snapshots (waiting / playing with a telegraph / WIN, and the
 * Clockwork Bomb Robot: Bomb Chain, Mini Chaser, walking; the Cactus King and
 * the Thunder Ram mid-skill, a trapped raider) for the PC app's UI
 * test (apps/practice/tests/boss.gd), from the real simulation:
 *   npx tsx scripts/boss_fixture.ts ../practice/tests/fixtures/boss_snapshots.json
 *   npx prettier --write ../practice/tests/fixtures/boss_snapshots.json
 */
import { writeFileSync } from 'node:fs';
import {
  BossArena,
  CACTUS_RULES,
  RAM_RULES,
  ROBOT_RULES,
  type BossSkill,
} from '../src/boss.js';
import { Tile } from '../src/game.js';
import { MAPS } from '../src/maps.js';

const g = new BossArena(
  MAPS.harbor!,
  {
    eventId: 'evt_fixture',
    skills: ['boss_aoe_mark', 'boss_wave_push'],
    baseHp: 60,
  },
  3,
);
g.matchPrefix = 'p1.fixture';
const wrap = (s: ReturnType<BossArena['snapshot']>) => ({
  ...s,
  version: 2,
  map: 'harbor',
  number: 7,
  roomKey: 'arena:p1:fixture',
});
g.addPlayer('me', 'Ana', 'mimi');
g.addPlayer('bo', 'Bo', 'kai');
const waiting = wrap(g.snapshot());
g.input('me', 'ready');
g.input('bo', 'ready');
g.tick(3000);
g.tick(1600);
const playing = wrap(g.snapshot());
// Each raider bombs next to the boss from a safe cell, then steps away.
for (const [id, x, home] of [
  ['me', 7, [1, 5]],
  ['bo', 9, [15, 5]],
] as const) {
  const p = g.players.get(id)!;
  p.x = x;
  p.y = 4;
  g.input(id, 'bomb');
  g.tick(50);
  [p.x, p.y] = home;
}
g.tick(2000);
const finished = wrap(g.snapshot());

// The robot (round 2, so the app builds its factory floor afresh): walks
// toward the team, then casts.
const robot = (skill: 'robot_bomb_chain' | 'robot_mini_chaser') => {
  const r = new BossArena(
    MAPS.harbor!,
    { ...ROBOT_RULES, eventId: 'evt_robot', minPlayers: 1, skills: [skill] },
    5,
  );
  r.matchPrefix = 'p1.robot';
  r.addPlayer('me', 'Ana', 'mimi');
  r.addPlayer('bo', 'Bo', 'kai');
  r.input('me', 'ready');
  r.input('bo', 'ready');
  r.tick(3000);
  r.bossPhase = skill === 'robot_bomb_chain' ? 1 : 2;
  return r;
};
const factory = (r: BossArena) => ({ ...wrap(r.snapshot()), round: 2 });
const chain = robot('robot_bomb_chain');
chain.tick(1600);
const robotChain = factory(chain);
const chaser = robot('robot_mini_chaser');
chaser.tick(1600);
for (let t = 0; t < 1200; t += 50) chaser.tick(50);
const robotChaser = factory(chaser);
const walker = robot('robot_bomb_chain');
walker.rules.skills = [];
const me = walker.players.get('me')!;
[me.x, me.y] = [8, 11];
walker.tick(1600);
const robotWalk = factory(walker);
// Cactus King / Thunder Ram: one skill each, `ms` after the cast starts.
const twin = (
  preset: typeof CACTUS_RULES,
  skill: BossSkill,
  me: [number, number],
  ms: number,
) => {
  const r = new BossArena(
    MAPS.harbor!,
    { ...preset, eventId: 'evt_twin', skills: [skill] },
    9,
  );
  r.matchPrefix = 'p1.twin';
  r.addPlayer('me', 'Ana', 'mimi');
  r.addPlayer('bo', 'Bo', 'kai');
  r.input('me', 'ready');
  r.input('bo', 'ready');
  r.tick(3000);
  r.rules.walkMs = 0;
  for (const row of r.grid)
    row.forEach((t, x) => {
      if (t === Tile.Crate) row[x] = Tile.Floor;
    });
  r.bossPhase = skill.endsWith('storm') ? 3 : skill.endsWith('cross') ? 2 : 1;
  const a = r.players.get('me')!;
  [a.x, a.y] = me;
  const b = r.players.get('bo')!;
  [b.x, b.y] = [15, 11];
  for (let i = 0; i < 60 && !r.casts.length; i++) r.tick(50);
  for (let t = 0; t < ms; t += 50) r.tick(50);
  return factory(r);
};
const twins = {
  cactusRoll: twin(CACTUS_RULES, 'cactus_thorn_roll', [7, 10], 300),
  cactusShot: twin(CACTUS_RULES, 'cactus_thorn_shot', [8, 1], 800),
  cactusCross: twin(CACTUS_RULES, 'cactus_thorn_cross', [1, 1], 600),
  cactusStorm: twin(CACTUS_RULES, 'cactus_thorn_storm', [1, 1], 800),
  ramCharge: twin(RAM_RULES, 'ram_thunder_charge', [1, 5], 300),
  ramBall: twin(RAM_RULES, 'ram_thunder_ball', [15, 5], 900),
  ramCross: twin(RAM_RULES, 'ram_lightning_cross', [1, 1], 600),
  ramStorm: twin(RAM_RULES, 'ram_thunder_storm', [7, 3], 600),
  // The cross lands on a raider who stays: trapped, waiting for a rescue.
  cactusTrapped: twin(CACTUS_RULES, 'cactus_thorn_cross', [7, 4], 1300),
};
writeFileSync(
  process.argv[2]!,
  JSON.stringify({
    waiting,
    playing,
    finished,
    robotChain,
    robotChaser,
    robotWalk,
    ...twins,
  }),
);
console.log(
  Object.entries(twins)
    .map(
      ([k, v]) =>
        `${k}:${v.boss.casts.length}/${Object.keys(v.boss.trapped).length}`,
    )
    .join(' '),
);
console.log(
  playing.boss.casts.length,
  finished.raid.result,
  finished.raid.matchId,
  robotChain.boss.casts.length,
  robotChaser.boss.casts[0]?.mini,
  [robotWalk.boss.x, robotWalk.boss.y, robotWalk.boss.facing],
);
