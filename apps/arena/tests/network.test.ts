import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { SignJWT } from 'jose';
import WebSocket from 'ws';
import { createArenaServer } from '../src/server.js';
import type { Arena } from '../src/game.js';

type Snapshot = ReturnType<Arena['snapshot']>;
type Seat = { sessionId: string; roomId: string; processId: string };
const secret = 'integration-test-only-secret-at-least-32-chars';
async function token(id: string) {
  return new SignJWT({ name: `Pilot-${id}` })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(id)
    .setIssuer('suni-api')
    .setAudience('suni-arena')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(new TextEncoder().encode(secret));
}

async function waitUntil(predicate: () => boolean, ms = 5000) {
  const end = Date.now() + ms;
  while (!predicate()) {
    if (Date.now() > end)
      throw new Error('Timed out waiting for server snapshot');
    await delay(20);
  }
}

function wireClient(base: string, seat: Seat) {
  const ws = new WebSocket(
    `${base.replace('http', 'ws')}/${seat.processId}/${seat.roomId}?sessionId=${seat.sessionId}`,
  );
  const state: { snapshot?: Snapshot; joined: boolean; rejected: boolean } = {
    joined: false,
    rejected: false,
  };
  ws.on('message', (raw) => {
    const bytes = Buffer.from(raw as Buffer);
    if (bytes[0] === 10) {
      ws.send(Buffer.from([10]));
      state.joined = true;
    }
    if (bytes[0] === 11) state.rejected = true;
    if (bytes[0] === 17 && bytes[1] === 1)
      state.snapshot = JSON.parse(bytes.subarray(2).toString());
  });
  const send = (action: string) =>
    ws.send(
      Buffer.concat([
        Buffer.from([13, 0, 0xa0 + action.length]),
        Buffer.from(action),
      ]),
    );
  return { ws, state, send, id: seat.sessionId };
}

test(
  'real Colyseus handshake, 8-player limit, authoritative inputs and completed round',
  { timeout: 20_000 },
  async () => {
    process.env.JWT_SECRET = secret;
    const { server, httpServer, listen } = createArenaServer();
    await listen(0, '127.0.0.1');
    const address = httpServer.address();
    assert.ok(address && typeof address !== 'string');
    const base = `http://127.0.0.1:${address.port}`;
    const clients: ReturnType<typeof wireClient>[] = [];
    const reserve = async (id: string, roomId?: string) => {
      const route = roomId ? `joinById/${roomId}` : 'joinOrCreate/arena';
      return fetch(`${base}/matchmake/${route}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: await token(id) }),
      });
    };
    try {
      const oversized = await fetch(`${base}/matchmake/joinOrCreate/arena`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: 'x'.repeat(9000) }),
      });
      assert.equal(oversized.status, 413);
      const bad = await fetch(`${base}/matchmake/joinOrCreate/arena`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{"token":"forged"}',
      });
      const badSeat = (await bad.json()) as Seat;
      const rejected = wireClient(base, badSeat);
      clients.push(rejected);
      await waitUntil(() => rejected.state.rejected);
      assert.equal(rejected.state.joined, false);
      rejected.ws.close();
      clients.pop();
      let roomId = '';
      for (let i = 0; i < 8; i++) {
        const response = await reserve(String(i), roomId || undefined);
        assert.equal(response.status, 200, await response.clone().text());
        const seat = (await response.json()) as Seat;
        roomId = seat.roomId;
        const client = wireClient(base, seat);
        clients.push(client);
        await waitUntil(() => client.state.joined && !!client.state.snapshot);
      }
      await waitUntil(() => clients[0]!.state.snapshot?.players.length === 8);
      const ninth = await reserve('ninth', roomId);
      assert.ok(ninth.status >= 400);
      for (const c of clients) c.send('ready');
      await waitUntil(() => clients[0]!.state.snapshot?.phase === 'playing');
      const a = clients[0]!;
      a.send('right');
      await waitUntil(
        () => a.state.snapshot?.players.find((p) => p.id === a.id)?.x === 2,
      );
      a.send('win'); // Unknown action is ignored by the authority.
      await delay(100);
      assert.equal(a.state.snapshot?.phase, 'playing');
      a.send('bomb');
      await waitUntil(() => a.state.snapshot?.bombs.length === 1);
      await waitUntil(
        () =>
          a.state.snapshot?.players.find((p) => p.id === a.id)?.alive === false,
      );
      for (const c of clients.slice(1, 7)) c.ws.close();
      await waitUntil(() => clients[7]!.state.snapshot?.phase === 'finished');
      assert.equal(clients[7]!.state.snapshot?.winner, clients[7]!.id);
      let limited = false;
      for (let i = 0; i < 31; i++) {
        const response = await reserve('rate-check', 'nonexistent-room');
        if (response.status === 429) {
          limited = true;
          break;
        }
      }
      assert.ok(
        limited,
        'HTTP matchmaking limiter must run before the Colyseus router',
      );
    } finally {
      for (const c of clients) c.ws.close();
      await delay(100);
      await server.gracefullyShutdown(false);
    }
  },
);
