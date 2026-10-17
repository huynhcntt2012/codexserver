import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { SignJWT } from 'jose';
import WebSocket from 'ws';
import { createServer as createHttpServer } from 'node:http';
import { createArenaServer } from '../src/server.js';
import { resetRemoteMaps, toMapDef } from '../src/maps.js';
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
    const list = async () => {
      const response = await fetch(`${base}/rooms`, {
        headers: { Authorization: `Bearer ${await token('browser')}` },
      });
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('cache-control'), 'no-store');
      return (await response.json()) as {
        rooms: {
          roomId: string;
          players: number;
          ready: number;
          joinable: boolean;
        }[];
      };
    };
    try {
      // Public documentation must work through the same HTTP router as rooms.
      for (const path of ['/documents', '/documents/']) {
        const response = await fetch(`${base}${path}`);
        assert.equal(response.status, 200);
        assert.match(response.headers.get('content-type')!, /text\/html/);
        assert.equal(response.headers.get('cache-control'), 'no-cache');
        assert.match(
          response.headers.get('content-security-policy')!,
          /default-src 'none'/,
        );
        const html = await response.text();
        assert.match(html, /<html lang="vi">/);
        assert.match(html, /<h1[^>]*>Server realtime Colyseus/);
        assert.match(html, /<table>/);
        assert.match(html, /href="#message-va-snapshot-version-1"/);
        assert.match(html, /id="message-va-snapshot-version-1"/);
        assert.match(
          html,
          /https:\/\/github.com\/huynhcntt2012\/codexserver\/blob\/suni\/06-client-polish\/apps\/arena\/src\/game.ts/,
        );
        assert.doesNotMatch(html, /<script\b|__STYLESHEET__|href="\.\.\//);
        const stylesheet = html.match(/rel="stylesheet" href="([^"]+)"/);
        assert.ok(stylesheet?.[1]);
        const css = await fetch(new URL(stylesheet[1], `${base}${path}`));
        assert.equal(css.status, 200);
        assert.match(css.headers.get('content-type')!, /text\/css/);
        assert.match(await css.text(), /\.table-scroll/);
      }
      assert.deepEqual(await (await fetch(`${base}/health`)).json(), {
        status: 'ok',
      });
      assert.equal((await fetch(`${base}/rooms`)).status, 401);
      assert.equal(
        (
          await fetch(`${base}/rooms`, {
            headers: { Authorization: 'Bearer forged' },
          })
        ).status,
        401,
      );
      assert.deepEqual((await list()).rooms, []);
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
        if (i === 0) {
          const rooms = (await list()).rooms;
          assert.equal(rooms.length, 1);
          assert.deepEqual(rooms[0], {
            roomId,
            players: 1,
            maxPlayers: 8,
            ready: 0,
            joinable: true,
          });
          const duplicate = await reserve('0', roomId);
          const duplicateClient = wireClient(
            base,
            (await duplicate.json()) as Seat,
          );
          clients.push(duplicateClient);
          await waitUntil(() => duplicateClient.state.rejected);
          duplicateClient.ws.close();
          clients.pop();
        }
      }
      await waitUntil(() => clients[0]!.state.snapshot?.players.length === 8);
      const full = (await list()).rooms.find((room) => room.roomId === roomId);
      assert.equal(full?.players, 8);
      assert.equal(full?.joinable, false);
      const ninth = await reserve('ninth', roomId);
      assert.ok(ninth.status >= 400);
      clients[0]!.send('ready');
      await waitUntil(
        () => clients[0]!.state.snapshot?.players[0]?.ready === true,
      );
      assert.equal(clients[0]!.state.snapshot?.phase, 'waiting');
      assert.equal((await list()).rooms[0]?.ready, 1);
      for (const c of clients.slice(1)) c.send('ready');
      await waitUntil(() => clients[0]!.state.snapshot?.phase === 'countdown');
      assert.deepEqual((await list()).rooms, []);
      assert.ok((await reserve('late', roomId)).status >= 400);
      await waitUntil(() => clients[0]!.state.snapshot?.phase === 'playing');
      assert.deepEqual((await list()).rooms, []);
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

test(
  'protocol v2 rooms: map choice, numbered list with friends ids, full rooms and a real round',
  { timeout: 20_000 },
  async () => {
    process.env.JWT_SECRET = secret;
    const { server, httpServer, listen } = createArenaServer();
    await listen(0, '127.0.0.1');
    const address = httpServer.address();
    assert.ok(address && typeof address !== 'string');
    const base = `http://127.0.0.1:${address.port}`;
    const clients: ReturnType<typeof wireClient>[] = [];
    const reserve = async (id: string, route: string, extra = {}) =>
      fetch(`${base}/matchmake/${route}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: await token(id), ...extra }),
      });
    type Listed = {
      roomId: string;
      number: number;
      map: string;
      phase: string;
      players: number;
      maxPlayers: number;
      ready: number;
      joinable: boolean;
      accountIds: string[];
    };
    const list = async () => {
      const response = await fetch(`${base}/rooms/v2`, {
        headers: { Authorization: `Bearer ${await token('browser')}` },
      });
      assert.equal(response.status, 200);
      const body = (await response.json()) as {
        version: number;
        rooms: Listed[];
      };
      assert.equal(body.version, 2);
      return body.rooms;
    };
    const join = async (id: string, route: string, extra = {}) => {
      const response = await reserve(id, route, extra);
      assert.equal(response.status, 200, await response.clone().text());
      const client = wireClient(base, (await response.json()) as Seat);
      clients.push(client);
      await waitUntil(() => client.state.joined && !!client.state.snapshot);
      return client;
    };
    try {
      assert.equal((await fetch(`${base}/rooms/v2`)).status, 401);
      // Unknown or missing maps never create a room.
      assert.ok(
        (await reserve('x', 'create/arena2', { map: 'mars' })).status >= 400,
      );
      assert.ok((await reserve('x', 'create/arena2')).status >= 400);
      // A 17 x 13 Boom World map: own size and 8 spawns, then the room closes.
      const moon = await join('moon', 'create/arena2', { map: 'moon' });
      const moonSnap = moon.state.snapshot as unknown as Record<
        string,
        unknown
      >;
      assert.deepEqual(
        [moonSnap.map, moonSnap.width, moonSnap.height],
        ['moon', 17, 13],
      );
      assert.equal((moonSnap.grid as unknown[]).length, 13);
      moon.ws.close();
      clients.splice(clients.indexOf(moon), 1);
      await delay(200);
      const host = await join('host', 'create/arena2', {
        map: 'frost',
        hero: 'lala',
      });
      const snap = host.state.snapshot as unknown as Record<string, unknown>;
      assert.equal(snap.version, 2);
      assert.equal(snap.map, 'frost');
      assert.equal(snap.number, 1);
      assert.equal(snap.width, 15);
      assert.equal(snap.height, 11);
      assert.match(String(snap.roomKey), /^arena:[0-9a-f]{8}:/);
      assert.equal(host.state.snapshot?.players[0]?.x, 1);
      assert.equal(
        (host.state.snapshot?.players[0] as { hero?: string }).hero,
        'lala',
      );
      // joinOrCreate filters by map: a park request opens a second room.
      const other = await join('solo', 'joinOrCreate/arena2', { map: 'park' });
      assert.equal((other.state.snapshot as { number?: number }).number, 2);
      const guest = await join('guest', 'joinOrCreate/arena2', {
        map: 'frost',
        hero: 'not-a-hero',
      });
      await waitUntil(() => host.state.snapshot?.players.length === 2);
      const seated = guest.state.snapshot?.players.find(
        (p) => p.id === guest.id,
      ) as { hero?: string; x: number; y: number };
      assert.equal(seated.hero, 'mimi'); // invalid hero falls back by slot
      assert.deepEqual([seated.x, seated.y], [13, 9]);
      let rooms = await list();
      assert.deepEqual(
        rooms.map((r) => [r.number, r.map, r.players, r.joinable]),
        [
          [1, 'frost', 2, true],
          [2, 'park', 1, true],
        ],
      );
      assert.deepEqual(rooms[0]!.accountIds.sort(), ['guest', 'host']);
      assert.equal(rooms[0]!.maxPlayers, 8);
      // Fill the park room to 8/8: listed as full, a ninth seat is refused.
      const parkId = rooms[1]!.roomId;
      for (let i = 0; i < 7; i++) await join(`p${i}`, `joinById/${parkId}`);
      rooms = await list();
      assert.equal(rooms[1]!.players, 8);
      assert.equal(rooms[1]!.joinable, false);
      assert.ok((await reserve('ninth', `joinById/${parkId}`)).status >= 400);
      // A real round on frost: playing rooms stay listed but are not joinable.
      host.send('ready');
      guest.send('ready');
      await waitUntil(() => host.state.snapshot?.phase === 'playing');
      rooms = await list();
      assert.equal(rooms[0]!.phase, 'playing');
      assert.equal(rooms[0]!.joinable, false);
      host.send('down');
      await waitUntil(
        () =>
          host.state.snapshot?.players.find((p) => p.id === host.id)?.y === 2,
      );
      host.send('bomb');
      await waitUntil(() => host.state.snapshot?.bombs.length === 1);
      await waitUntil(
        () =>
          host.state.snapshot?.players.find((p) => p.id === host.id)?.alive ===
          false,
      );
      await waitUntil(() => guest.state.snapshot?.phase === 'finished');
      assert.equal(guest.state.snapshot?.winner, guest.id);
      // The v1 list never shows v2 rooms, so older clients are unaffected.
      const v1 = await fetch(`${base}/rooms`, {
        headers: { Authorization: `Bearer ${await token('browser')}` },
      });
      assert.deepEqual(((await v1.json()) as { rooms: unknown[] }).rooms, []);
    } finally {
      for (const c of clients) c.ws.close();
      await delay(100);
      await server.gracefullyShutdown(false);
    }
  },
);

test(
  'admin maps published through the API open real rooms; bad ones are refused',
  { timeout: 20_000 },
  async () => {
    process.env.JWT_SECRET = secret;
    const layout = [
      '#############',
      '#...........#',
      '#.#.#C#C#.#.#',
      '#.....C.....#',
      '#.#C#.#.#C#.#',
      '#...........#',
      '#.#C#.#.#C#.#',
      '#.....C.....#',
      '#.#.#C#C#.#.#',
      '#...........#',
      '#############',
    ];
    const level = {
      id: 'candy_maze',
      name: 'MÊ CUNG KẸO',
      subtitle: 'Dễ • Thử nghiệm',
      columns: 13,
      rows: 11,
      layout,
      arena_spawns: [
        [1, 1],
        [11, 9],
        [11, 1],
        [1, 9],
        [6, 1],
        [6, 9],
        [1, 5],
        [11, 5],
      ],
    };
    // A wall on a seat or a builtin id is never accepted from the API.
    assert.equal(toMapDef({ ...level, id: 'moon' }), null);
    assert.equal(
      toMapDef({ ...level, layout: ['##', ...layout.slice(1)] }),
      null,
    );
    const broken = { ...level, id: 'broken_map', arena_spawns: [[2, 2]] };
    let calls = 0;
    const api = createHttpServer((req, res) => {
      if (req.url === '/v1/maps') {
        calls++;
        res.setHeader('Content-Type', 'application/json');
        res.end(JSON.stringify({ version: 'x', maps: [level, broken] }));
        return;
      }
      res.statusCode = 204; // arena event ingest
      res.end();
    });
    await new Promise<void>((done) => api.listen(0, '127.0.0.1', done));
    const apiAddress = api.address();
    assert.ok(apiAddress && typeof apiAddress !== 'string');
    process.env.API_URL = `http://127.0.0.1:${apiAddress.port}`;
    resetRemoteMaps();
    const { server, httpServer, listen } = createArenaServer();
    await listen(0, '127.0.0.1');
    const address = httpServer.address();
    assert.ok(address && typeof address !== 'string');
    const base = `http://127.0.0.1:${address.port}`;
    const clients: ReturnType<typeof wireClient>[] = [];
    const reserve = async (id: string, map: string) =>
      fetch(`${base}/matchmake/create/arena2`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: await token(id), map }),
      });
    try {
      assert.ok((await reserve('a', 'broken_map')).status >= 400);
      const response = await reserve('a', 'candy_maze');
      assert.equal(response.status, 200, await response.clone().text());
      const client = wireClient(base, (await response.json()) as Seat);
      clients.push(client);
      await waitUntil(() => client.state.joined && !!client.state.snapshot);
      const snap = client.state.snapshot as unknown as Record<string, unknown>;
      assert.deepEqual(
        [snap.map, snap.width, snap.height],
        ['candy_maze', 13, 11],
      );
      // Cached: a second room within 15 s does not refetch the list.
      const again = await reserve('b', 'candy_maze');
      assert.equal(again.status, 200);
      assert.equal(calls, 1);
      const rooms = await fetch(`${base}/rooms/v2`, {
        headers: { Authorization: `Bearer ${await token('browser')}` },
      });
      const listed = (await rooms.json()) as { rooms: { map: string }[] };
      assert.ok(listed.rooms.some((room) => room.map === 'candy_maze'));
    } finally {
      for (const c of clients) c.ws.close();
      await delay(100);
      await server.gracefullyShutdown(false);
      api.close();
      delete process.env.API_URL;
      resetRemoteMaps();
    }
  },
);
