import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import {
  ArenaClient,
  encodeAction,
  validateCredentials,
} from '../public/classic/network.mjs';

test('only intent enums can be encoded, with the Colyseus wire format', () => {
  assert.deepEqual([...encodeAction('bomb')], [13, 0, 164, 98, 111, 109, 98]);
  for (const action of ['win', { x: 1, y: 2 }, '', null, 'bomb'.repeat(50)])
    assert.equal(encodeAction(action), null);
});

test('credentials match API boundaries and preserve spaces in passwords', () => {
  assert.equal(validateCredentials('guest', '', '', ''), '');
  for (const name of [
    'ab',
    'a'.repeat(25),
    'Uppercase',
    'pilot name',
    'pilot!',
  ])
    assert.ok(validateCredentials('login', name, 'long-password', ''));
  for (const n of [9, 129])
    assert.ok(validateCredentials('login', 'pilot', 'x'.repeat(n), ''));
  for (const n of [10, 128])
    assert.equal(
      validateCredentials('login', ' a_1 ', ' ' + 'x'.repeat(n - 2) + ' ', ''),
      '',
    );
  assert.ok(
    validateCredentials(
      'register',
      'pilot',
      'long-password',
      'different-password',
    ),
  );
});

test('HTTP failures release busy; successful registration survives arena failure without registering twice', async (t) => {
  let registrations = 0;
  const server = createServer((req, res) => {
    req.resume();
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/api/v1/register') {
      registrations++;
      res.end(
        JSON.stringify({
          access_token: 'fixture',
          name: 'pilot',
          expires_in: 3600,
        }),
      );
    } else if (req.url === '/api/v1/login') {
      res
        .writeHead(401)
        .end(JSON.stringify({ detail: 'DO_NOT_DISPLAY_PASSWORD' }));
    } else res.writeHead(503).end('{}');
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  const client = new ArenaClient(`http://127.0.0.1:${server.address().port}`);
  await assert.rejects(
    client.join({
      mode: 'login',
      username: 'pilot',
      password: 'long-password',
    }),
    /Tên tài khoản/,
  );
  assert.equal(client.busy, false);
  await assert.rejects(
    client.join({
      mode: 'register',
      username: 'pilot',
      password: 'long-password',
      confirmation: 'long-password',
    }),
    /chưa sẵn sàng/,
  );
  assert.equal(client.busy, false);
  assert.equal(client.hasSession(), true);
  await assert.rejects(client.join({ mode: 'session' }), /chưa sẵn sàng/);
  assert.equal(registrations, 1);
  client.session.deadline = 0;
  await assert.rejects(client.join({ mode: 'session' }), /hết hạn/);
  assert.equal(client.session, null);
  client.logout();
  assert.equal(client.hasSession(), false);
});

test('logout cancels in-flight authentication and cannot restore a stale session', async (t) => {
  let received;
  const started = new Promise((resolve) => {
    received = resolve;
  });
  const server = createServer((req, res) => {
    req.resume();
    received();
    setTimeout(
      () =>
        res.end(
          JSON.stringify({
            access_token: 'fixture',
            name: 'pilot',
            expires_in: 3600,
          }),
        ),
      40,
    );
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  const client = new ArenaClient(`http://127.0.0.1:${server.address().port}`);
  const pending = client.join({
    mode: 'login',
    username: 'pilot',
    password: 'long-password',
  });
  const rejected = assert.rejects(pending);
  await started;
  client.logout();
  await rejected;
  assert.equal(client.session, null);
  assert.equal(client.connected, false);
  assert.equal(client.busy, false);
});

test('authentication does not reserve a seat; room discovery requires a valid session', async (t) => {
  const requests = [];
  const server = createServer((req, res) => {
    req.resume();
    requests.push(req.url);
    res.setHeader('Content-Type', 'application/json');
    if (req.url === '/api/v1/login')
      res.end(
        JSON.stringify({
          access_token: 'fixture',
          name: 'pilot',
          expires_in: 3600,
        }),
      );
    else if (req.url === '/arena/rooms') {
      assert.equal(req.headers.authorization, 'Bearer fixture');
      res.end(
        JSON.stringify({
          rooms: [
            {
              roomId: 'chosen-room',
              players: 1,
              maxPlayers: 8,
              ready: 0,
              joinable: true,
            },
          ],
        }),
      );
    } else res.writeHead(404).end('{}');
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  const client = new ArenaClient(`http://127.0.0.1:${server.address().port}`);
  await assert.rejects(client.listRooms(), /hết hạn/);
  assert.equal(requests.length, 0);
  await client.authenticate({
    mode: 'login',
    username: 'pilot',
    password: 'long-password',
  });
  assert.equal(client.connected, false);
  assert.equal(client.busy, false);
  assert.deepEqual(requests, ['/api/v1/login']);
  assert.equal((await client.listRooms())[0].roomId, 'chosen-room');
  await assert.rejects(
    client.joinRoom({ roomId: 'chosen-room' }),
    /Phòng đã đầy/,
  );
  assert.equal(requests.at(-1), '/arena/matchmake/joinById/chosen-room');
  assert.equal(client.hasSession(), true);
  client.session.deadline = 0;
  await assert.rejects(client.listRooms(), /hết hạn/);
  assert.equal(client.session, null);
});
