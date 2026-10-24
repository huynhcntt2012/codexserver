import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { SignJWT } from 'jose';
import WebSocket from 'ws';
import { createArenaServer } from '../src/server.js';
import {
  VOICE_ALL,
  VOICE_RATE,
  VOICE_SAMPLES,
  VOICE_TEAM,
  VoiceLimiter,
  voiceFrame,
} from '../src/voice.js';

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
    if (Date.now() > end) throw new Error('Timed out');
    await delay(20);
  }
}

test('voice frames carry the server-side speaker id and stay small', () => {
  const audio = new Uint8Array(1 + VOICE_SAMPLES).fill(0x7f);
  audio[0] = VOICE_ALL;
  const frame = voiceFrame('abc123', audio);
  assert.ok(frame);
  assert.equal(frame.channel, VOICE_ALL);
  assert.equal(frame.bytes[1], 6);
  assert.equal(Buffer.from(frame.bytes.subarray(2, 8)).toString(), 'abc123');
  assert.equal(frame.bytes.length, 2 + 6 + VOICE_SAMPLES);
  assert.equal(voiceFrame('a', new Uint8Array([7, 1, 2])), null, 'channel');
  assert.equal(voiceFrame('a', new Uint8Array([VOICE_ALL])), null, 'empty');
  const big = new Uint8Array(2 + VOICE_SAMPLES);
  big[0] = VOICE_TEAM;
  assert.equal(voiceFrame('a', big), null, 'longer than 60 ms');
  const limiter = new VoiceLimiter();
  let sent = 0;
  for (let i = 0; i < VOICE_RATE + 10; i++)
    if (limiter.allow('a', 1000)) sent++;
  assert.equal(sent, VOICE_RATE);
  assert.ok(limiter.allow('a', 2001), 'a new second');
});

test(
  'voice over the wire: relayed to the room, team channel empty in free-for-all, limits',
  { timeout: 20_000 },
  async () => {
    process.env.JWT_SECRET = secret;
    const { server, httpServer, listen } = createArenaServer();
    await listen(0, '127.0.0.1');
    const address = httpServer.address();
    assert.ok(address && typeof address !== 'string');
    const base = `http://127.0.0.1:${address.port}`;
    const sockets: WebSocket[] = [];
    const join = async (id: string, roomId?: string) => {
      const route = roomId ? `joinById/${roomId}` : 'create/arena';
      const reply = await fetch(`${base}/matchmake/${route}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: await token(id) }),
      });
      const seat = (await reply.json()) as {
        sessionId: string;
        roomId: string;
        processId: string;
      };
      const ws = new WebSocket(
        `${base.replace('http', 'ws')}/${seat.processId}/${seat.roomId}?sessionId=${seat.sessionId}`,
      );
      sockets.push(ws);
      const state = { joined: false, voice: [] as Buffer[], closed: false };
      ws.on('message', (raw) => {
        const bytes = Buffer.from(raw as Buffer);
        if (bytes[0] === 10) {
          ws.send(Buffer.from([10]));
          state.joined = true;
        }
        if (bytes[0] === 17 && bytes[1] === 2)
          state.voice.push(bytes.subarray(2));
      });
      ws.on('close', () => (state.closed = true));
      await waitUntil(() => state.joined);
      const talk = (channel: number, audio: Buffer) =>
        ws.send(Buffer.concat([Buffer.from([17, 2, channel]), audio]));
      return { state, talk, id: seat.sessionId, roomId: seat.roomId };
    };
    try {
      const ana = await join('ana');
      const bo = await join('bo', ana.roomId);
      const cy = await join('cy', ana.roomId);
      await delay(200);

      ana.talk(VOICE_ALL, Buffer.alloc(VOICE_SAMPLES, 0x55));
      await waitUntil(
        () => bo.state.voice.length === 1 && cy.state.voice.length === 1,
      );
      const got = bo.state.voice[0]!;
      assert.equal(got[0], VOICE_ALL);
      assert.equal(
        got.subarray(2, 2 + got[1]!).toString(),
        ana.id,
        'speaker set by the server',
      );
      assert.equal(got.length, 2 + got[1]! + VOICE_SAMPLES);
      assert.equal(ana.state.voice.length, 0, 'no echo to the speaker');

      // Free-for-all has no teams; malformed and oversized frames are dropped.
      ana.talk(VOICE_TEAM, Buffer.alloc(VOICE_SAMPLES, 1));
      ana.talk(9, Buffer.alloc(100, 1));
      ana.talk(VOICE_ALL, Buffer.alloc(VOICE_SAMPLES + 40, 1));
      await delay(300);
      assert.equal(bo.state.voice.length, 1);

      // A burst over the per-second budget is cut, and the talker stays seated.
      await delay(1100);
      for (let i = 0; i < VOICE_RATE + 15; i++)
        ana.talk(VOICE_ALL, Buffer.alloc(320, 2));
      await delay(500);
      assert.equal(bo.state.voice.length - 1, VOICE_RATE);
      assert.equal(ana.state.closed, false);
    } finally {
      for (const ws of sockets) ws.close();
      await server.gracefullyShutdown(false);
    }
  },
);
