/**
 * Writes boss raid snapshots (waiting / playing with a telegraph / WIN, and the
 * Clockwork Bomb Robot: Bomb Chain, Mini Chaser, walking) for the PC app's UI
 * test (apps/practice/tests/boss.gd), from the real simulation:
 *   npx tsx scripts/boss_fixture.ts ../practice/tests/fixtures/boss_snapshots.json
 *   npx prettier --write ../practice/tests/fixtures/boss_snapshots.json
 */
import { writeFileSync } from 'node:fs';
import { BossArena, ROBOT_RULES } from '../src/boss.js';
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
writeFileSync(
  process.argv[2]!,
  JSON.stringify({
    waiting,
    playing,
    finished,
    robotChain,
    robotChaser,
    robotWalk,
  }),
);
console.log(
  playing.boss.casts.length,
  finished.raid.result,
  finished.raid.matchId,
  robotChain.boss.casts.length,
  robotChaser.boss.casts[0]?.mini,
  [robotWalk.boss.x, robotWalk.boss.y, robotWalk.boss.facing],
);
