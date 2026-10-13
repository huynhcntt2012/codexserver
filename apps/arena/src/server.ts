import { createServer } from 'node:http';
import express from 'express';
import rateLimit from 'express-rate-limit';
import { Server } from '@colyseus/core';
import { WebSocketTransport } from '@colyseus/ws-transport';
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
