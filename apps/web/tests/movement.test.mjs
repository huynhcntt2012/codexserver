import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MovementVisual } from '../public/movement.mjs';
const state = () => ({
  phase: 'playing',
  round: 1,
  grid: [
    [1, 1, 1, 1, 1],
    [1, 0, 0, 0, 1],
    [1, 1, 1, 1, 1],
  ],
  players: [{ id: 'a', x: 1, y: 1, alive: true }],
  bombs: [],
});
test('immediate visual feedback is bounded and does not mutate authoritative state', () => {
  const s = state(),
    original = structuredClone(s),
    v = new MovementVisual();
  v.sample(s, 'a', 0);
  v.intent(s, 'a', 'right', 0);
  assert.ok(v.sample(s, 'a', 16).get('a').x > 1);
  assert.ok(v.sample(s, 'a', 100).get('a').x <= 1.25);
  v.intent(s, 'a', 'right', 150);
  assert.equal(v.sample(s, 'a', 300).get('a').x, 1);
  assert.deepEqual(s, original);
});
test('walls, bombs and players prevent anticipation; death and round changes reset it', () => {
  for (const obstacle of ['wall', 'bomb', 'player']) {
    const s = state(),
      v = new MovementVisual();
    if (obstacle === 'wall') s.grid[1][2] = 1;
    if (obstacle === 'bomb') s.bombs.push({ x: 2, y: 1 });
    if (obstacle === 'player')
      s.players.push({ id: 'b', x: 2, y: 1, alive: true });
    v.sample(s, 'a', 0);
    v.intent(s, 'a', 'right', 0);
    assert.equal(v.sample(s, 'a', 50).get('a').x, 1);
  }
  const s = state(),
    v = new MovementVisual();
  v.sample(s, 'a', 0);
  v.intent(s, 'a', 'right', 0);
  v.sample(s, 'a', 50);
  s.players[0].alive = false;
  assert.equal(v.sample(s, 'a', 60).get('a').x, 1);
  s.round++;
  s.players[0].alive = true;
  assert.equal(v.sample(s, 'a', 70).get('a').x, 1);
});
test('server confirmation replaces anticipation and remote motion is smoothed', () => {
  const s = state(),
    v = new MovementVisual();
  v.sample(s, 'a', 0);
  v.intent(s, 'a', 'right', 0);
  v.sample(s, 'a', 50);
  s.players[0].x = 2;
  assert.equal(v.sample(s, 'a', 100).get('a').x, 2);
  assert.equal(v.cue, null);
});
