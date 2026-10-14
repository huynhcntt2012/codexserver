import { createServer } from 'node:http';
import express from 'express';
import rateLimit from 'express-rate-limit';
import { Server, matchMaker } from '@colyseus/core';
import { WebSocketTransport } from '@colyseus/ws-transport';
import { authenticate } from './auth.js';
import { ArenaRoom } from './room.js';

export function createArenaServer() {
  if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
    throw new Error('JWT_SECRET must contain at least 32 characters');
  }
  const app = express();
  app.disable('x-powered-by');
  app.get('/health', (_req, res) => res.json({ status: 'ok' }));
  app.use(
    '/matchmake',
    rateLimit({
      windowMs: 60_000,
      limit: 30,
      standardHeaders: 'draft-7',
      legacyHeaders: false,
    }),
  );
  app.get(
    '/rooms',
    rateLimit({ windowMs: 60_000, limit: 120 }),
    async (req, res) => {
      res.setHeader('Cache-Control', 'no-store');
      try {
        const authorization = req.headers.authorization;
        await authenticate(
          authorization?.startsWith('Bearer ')
            ? authorization.slice(7)
            : undefined,
        );
      } catch {
        res.status(401).json({ error: 'Invalid access token' });
        return;
      }
      try {
        const listings = await matchMaker.query({
          name: 'arena',
          private: false,
        });
        const rooms = listings.flatMap((listing) => {
          const room = matchMaker.getLocalRoomById(listing.roomId);
          if (
            !(room instanceof ArenaRoom) ||
            room.game.phase !== 'waiting' ||
            !room.game.players.size
          )
            return [];
          return [
            {
              roomId: listing.roomId,
              players: room.game.players.size,
              maxPlayers: room.maxClients,
              ready: [...room.game.players.values()].filter(
                (player) => player.ready,
              ).length,
              joinable: !room.locked && listing.clients < room.maxClients,
            },
          ];
        });
        res.json({ rooms });
      } catch {
        res.status(503).json({ error: 'Room list unavailable' });
      }
    },
  );
  app.use(express.json({ limit: '8kb' }));
  const httpServer = createServer();
  const server = new Server({
    transport: new WebSocketTransport({ server: httpServer, maxPayload: 1024 }),
    greet: false,
  });
  server.define('arena', ArenaRoom);
  async function listen(port: number, hostname = '0.0.0.0') {
    await server.listen(port, hostname);
    // Colyseus 0.17 binds its router ahead of Express. Wrap the bound handlers
    // so size/rate limits run BEFORE matchmaking, including chunked requests.
    const routes = httpServer.listeners('request');
    httpServer.removeAllListeners('request');
    app.use((req, res) => {
      for (const handler of routes) handler.call(httpServer, req, res);
    });
    httpServer.on('request', app);
  }
  return { server, httpServer, listen };
}
