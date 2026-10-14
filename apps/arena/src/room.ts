import { Room, type Client, ServerError } from '@colyseus/core';
import { authenticate } from './auth.js';
import { Arena, TICK_MS } from './game.js';

export class ArenaRoom extends Room {
  maxClients = 8;
  maxMessagesPerSecond = 40;
  game = new Arena();

  onCreate() {
    this.onMessage(0, (client, action: unknown) => {
      this.game.input(client.sessionId, action);
    });
    this.setSimulationInterval(() => {
      this.game.tick();
      const mustLock = this.game.phase !== 'waiting';
      if (mustLock && !this.locked) void this.lock();
      if (!mustLock && this.locked && this.clients.length < this.maxClients)
        void this.unlock();
      this.broadcastBytes(
        1,
        Buffer.from(JSON.stringify(this.game.snapshot())),
        {},
      );
    }, TICK_MS);
    // No schema serializer: snapshots use ROOM_DATA_BYTES with numeric type 1.
    this.setPatchRate(null);
  }

  async onAuth(_client: Client, options: { token?: unknown }) {
    return authenticate(options?.token);
  }

  onJoin(
    client: Client,
    _options: unknown,
    auth: { accountId: string; name: string },
  ) {
    if (
      this.clients.some(
        (c) => c !== client && c.auth?.accountId === auth.accountId,
      )
    ) {
      throw new ServerError(409, 'Account already in room');
    }
    if (!this.game.addPlayer(client.sessionId, auth.name))
      throw new ServerError(409, 'Round already starting');
    client.sendBytes(1, Buffer.from(JSON.stringify(this.game.snapshot())));
  }

  onLeave(client: Client) {
    this.game.removePlayer(client.sessionId);
  }
}
