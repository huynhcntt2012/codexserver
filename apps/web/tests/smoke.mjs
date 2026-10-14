import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { ArenaClient } from '../public/network.mjs';

// Run only against a development stack: creates a test account and a guest.
const base = process.env.SUNI_WEB_URL || 'http://127.0.0.1:8081';
const a = new ArenaClient(base),
  b = new ArenaClient(base);
const username = 'web_' + randomBytes(6).toString('hex');
const password = 'test-only-' + randomBytes(12).toString('hex');
async function until(predicate, timeout = 15000) {
  const end = Date.now() + timeout;
  while (!predicate()) {
    if (Date.now() > end)
      throw new Error('Timed out waiting for web multiplayer state');
    await delay(25);
  }
}

try {
  const response = await fetch(base);
  assert.equal(response.status, 200);
  assert.match(await response.text(), /Suni · Bomb Arena/);
  assert.match(
    response.headers.get('content-security-policy'),
    /connect-src 'self'/,
  );
  assert.equal((await fetch(`${base}/.env`)).status, 404);
  assert.match(
    (await fetch(`${base}/app.mjs`)).headers.get('content-type'),
    /javascript/,
  );
  await assert.rejects(
    a.join({ mode: 'login', username, password }),
    /Tên tài khoản/,
  );
  await a.join({
    mode: 'register',
    username,
    password,
    confirmation: password,
  });
  await until(() => a.snapshot?.players.length === 1);
  assert.equal(a.snapshot.players[0].name, username);
  const token = a.session.token;
  assert.equal((await a.request('/api/v1/me', undefined, token)).guest, false);
  assert.deepEqual(
    (await a.request('/api/v1/inventory', undefined, token)).items,
    ['pilot_default'],
  );
  assert.equal(
    (await a.request('/api/v1/vip', undefined, token)).active,
    false,
  );
  a.leave();
  assert.equal(a.hasSession(), true);
  await delay(150);
  await a.join({ mode: 'session' });
  await b.join();
  await until(
    () => a.snapshot?.players.length === 2 && b.snapshot?.players.length === 2,
  );
  assert.equal(a.roomId, b.roomId);
  a.send('ready');
  b.send('ready');
  await until(() => a.snapshot?.phase === 'playing');
  a.send('right');
  await until(() => a.snapshot.players.find((p) => p.id === a.id)?.x === 2);
  a.send('bomb');
  await until(() => a.snapshot.bombs.length === 1);
  await until(() => a.snapshot.phase === 'finished');
  assert.equal(a.snapshot.winner, b.id);
  await until(() => a.snapshot.phase === 'waiting');
  assert.equal(a.snapshot.round, 2);
  b.leave();
  await until(() => a.snapshot.players.length === 1);
  a.logout();
  assert.equal(a.hasSession(), false);
  await assert.rejects(
    a.join({ mode: 'register', username, password, confirmation: password }),
    /đã được dùng/,
  );
  await a.join({ mode: 'login', username, password });
  assert.equal(a.connected, true);
  console.log(
    'WEB_MULTIPLAYER_SMOKE_OK: proxy, register/login, session, inventory/VIP, two clients, move, bomb, winner, next round, leave, logout',
  );
} finally {
  a.logout();
  b.logout();
}
