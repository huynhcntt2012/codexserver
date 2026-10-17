import { Room, type Client, ServerError } from '@colyseus/core';
import { authenticate } from './auth.js';
import { Arena, TICK_MS, type RoundResult } from './game.js';
import { processId as ingestProcess, report } from './ingest.js';
import { findMap } from './maps.js';

/** Short public room numbers (001-999), unique among this process's live rooms. */
const numbers = new Set<number>();
function takeNumber(): number {
  for (let n = 1; n <= 999; n++)
    if (!numbers.has(n)) {
      numbers.add(n);
      return n;
    }
  return 0;
}

export class ArenaRoom extends Room {
  /** Wire protocol of this room type; v1 is the original fixed map. */
  readonly protocol: 1 | 2 = 1;
  number = 0;
  maxClients = 8;
  maxMessagesPerSecond = 40;
  game = new Arena();
  /** sessionId -> account, from the verified JWT; never from client messages. */
  private accounts = new Map<string, { accountId: string; name: string }>();
  private reported = '';

  async onCreate(options?: { map?: unknown }) {
    if (this.protocol === 2) {
      // Built-in maps or a map an admin published through the API.
      const map = await findMap(options?.map);
      if (!map) throw new ServerError(400, 'Unknown map');
      this.game = new Arena(map);
      this.number = takeNumber();
      void this.setMetadata({ map: map.id, number: this.number });
    }
    this.onMessage(0, (client, action: unknown) => {
      this.game.input(client.sessionId, action);
    });
    this.game.onRoundEnd = (result) => this.reportRound(result);
    this.setSimulationInterval(() => {
      this.game.tick();
      const mustLock = this.game.phase !== 'waiting';
      if (mustLock && !this.locked) void this.lock();
      if (!mustLock && this.locked && this.clients.length < this.maxClients)
        void this.unlock();
      this.reportRoom();
      this.broadcastBytes(1, this.snapshotBytes(), {});
    }, TICK_MS);
    // No schema serializer: snapshots use ROOM_DATA_BYTES with numeric type 1.
    this.setPatchRate(null);
  }

  async onAuth(_client: Client, options: { token?: unknown }) {
    return authenticate(options?.token);
  }

  /** v2 adds the map id, room number and chat key; v1 bytes are unchanged. */
  snapshotBytes(): Buffer {
    const snapshot = this.game.snapshot();
    return Buffer.from(
      JSON.stringify(
        this.protocol === 1
          ? snapshot
          : {
              ...snapshot,
              version: 2,
              map: this.game.map!.id,
              number: this.number,
              roomKey: `arena:${ingestProcess}:${this.roomId}`,
            },
      ),
    );
  }

  private mapName(): string {
    return this.game.map?.name ?? 'Neon Garden';
  }

  /** Account ids of seated players (for the friends filter of the v2 list). */
  members(): string[] {
    return [...this.accounts.values()].map((a) => a.accountId);
  }

  onJoin(
    client: Client,
    options: { hero?: unknown } | undefined,
    auth: { accountId: string; name: string },
  ) {
    if (
      this.clients.some(
        (c) => c !== client && c.auth?.accountId === auth.accountId,
      )
    ) {
      throw new ServerError(409, 'Account already in room');
    }
    if (!this.game.addPlayer(client.sessionId, auth.name, options?.hero))
      throw new ServerError(409, 'Round already starting');
    this.accounts.set(client.sessionId, auth);
    client.sendBytes(1, this.snapshotBytes());
    this.reportRoom();
  }

  onLeave(client: Client) {
    this.game.removePlayer(client.sessionId);
    this.accounts.delete(client.sessionId);
    this.reportRoom();
  }

  onDispose() {
    numbers.delete(this.number);
    report({
      type: 'closed',
      room_id: this.roomId,
      map_name: this.mapName(),
      map_id: this.game.map?.id ?? '',
    });
  }

  /** Sends the room state only when the phase or the player set changed. */
  private reportRoom() {
    const players = [...this.game.players.keys()].flatMap((id) => {
      const account = this.accounts.get(id);
      return account
        ? [{ account_id: account.accountId, name: account.name }]
        : [];
    });
    const phase = this.game.phase === 'finished' ? 'playing' : this.game.phase;
    const signature = `${phase}|${players.map((p) => p.account_id).join(',')}`;
    if (signature === this.reported) return;
    this.reported = signature;
    report({
      type: 'room',
      room_id: this.roomId,
      phase,
      players,
      max_players: this.maxClients,
      map_name: this.mapName(),
      map_id: this.game.map?.id ?? '',
    });
  }

  private reportRound(result: RoundResult) {
    report({
      type: 'match',
      room_id: this.roomId,
      map_name: this.mapName(),
      map_id: this.game.map?.id ?? '',
      round: result.round,
      duration_ms: result.durationMs,
      results: result.players.map((p) => ({
        account_id: this.accounts.get(p.id)?.accountId ?? null,
        name: p.name,
        placement: p.placement,
        kills: p.kills,
        bombs: p.bombs,
        survived_ms: p.survivedMs,
        winner: p.winner,
      })),
    });
  }
}

/** Protocol v2: one of the shared 15 x 11 maps, chosen when the room is created. */
export class ArenaRoomV2 extends ArenaRoom {
  override readonly protocol = 2;
}
