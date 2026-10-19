/**
 * Writes boss raid snapshots (waiting / playing with a telegraph / WIN) for the
 * PC app's UI test (apps/practice/tests/boss.gd), from the real simulation:
 *   npx tsx scripts/boss_fixture.ts ../practice/tests/fixtures/boss_snapshots.json
 *   npx prettier --write ../practice/tests/fixtures/boss_snapshots.json
 */
import { writeFileSync } from 'node:fs';
import { BossArena } from '../src/boss.js';
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
writeFileSync(process.argv[2]!, JSON.stringify({ waiting, playing, finished }));
console.log(
  playing.boss.casts.length,
  finished.raid.result,
  finished.raid.matchId,
);
