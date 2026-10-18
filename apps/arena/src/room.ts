import { Room, type Client, ServerError } from '@colyseus/core';
import { authenticate } from './auth.js';
import { Arena, TICK_MS, type RoundResult } from './game.js';
import { fetchLoadout, processId as ingestProcess, report } from './ingest.js';
import { findMap, HEROES } from './maps.js';
import { BotBrain } from './bots.js';

/** Practice rooms: humans plus server bots up to this many seats. */
export const PRACTICE_SEATS = 4;

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
  /** Practice room: private (invite only), bots fill the empty seats. */
  practice = false;
  private brains = new Map<string, BotBrain>();
  private botCount = 0;

  async onCreate(options?: { map?: unknown; practice?: unknown }) {
    if (this.protocol === 2) {
      // Built-in maps or a map an admin published through the API.
      const map = await findMap(options?.map);
      if (!map) throw new ServerError(400, 'Unknown map');
      this.game = new Arena(map);
      this.number = takeNumber();
      void this.setMetadata({ map: map.id, number: this.number });
      if (options?.practice === true) {
        this.practice = true;
        this.maxClients = PRACTICE_SEATS;
        // Hidden from room lists; friends join by id from an invite.
        void this.setPrivate(true);
      }
    }
    this.onMessage(0, (client, action: unknown) => {
      this.game.input(client.sessionId, action);
    });
    this.game.onRoundEnd = (result) => this.reportRound(result);
    // Each item use the simulation accepted is consumed once from the API stock.
    let uses = 0;
    this.game.onItemUsed = (playerId, item) => {
      const account = this.accounts.get(playerId);
      if (!account) return;
      report({
        type: 'use',
        room_id: this.roomId,
        account_id: account.accountId,
        item_id: item,
        use_id: `${ingestProcess}.${this.roomId}.${++uses}`,
      });
    };
    this.setSimulationInterval(() => {
      if (this.practice) this.driveBots();
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
              ...(this.practice
                ? { practice: true, seats: PRACTICE_SEATS }
                : {}),
            },
      ),
    );
  }

  private mapName(): string {
    return this.game.map?.name ?? 'Neon Garden';
  }

  /** Bots fill empty seats while waiting, are always ready, and play by intents. */
  private driveBots() {
    const game = this.game;
    if (game.phase === 'waiting' && this.accounts.size > 0) {
      while (game.players.size < PRACTICE_SEATS && this.addBot());
      for (const id of game.bots)
        if (!game.players.get(id)?.ready) game.input(id, 'ready');
    }
    for (const brain of this.brains.values()) {
      const action = brain.think(game);
      if (action) game.input(brain.id, action);
    }
  }

  private addBot(): boolean {
    const used = new Set(this.game.heroes.values());
    const hero =
      HEROES.find((h) => !used.has(h)) ??
      HEROES[this.botCount % HEROES.length]!;
    const id = `bot-${++this.botCount}`;
    const name = `Bot ${hero[0]!.toUpperCase()}${hero.slice(1)}`;
    if (!this.game.addPlayer(id, name, hero)) return false;
    this.game.bots.add(id);
    let seed = (this.botCount * 2654435761) >>> 0;
    this.brains.set(
      id,
      new BotBrain(id, () => {
        seed = (seed * 1664525 + 1013904223) >>> 0;
        return seed / 2 ** 32;
      }),
    );
    return true;
  }

  private removeBot(): boolean {
    const id = [...this.game.bots].at(-1);
    if (!id) return false;
    this.game.removePlayer(id);
    this.brains.delete(id);
    return true;
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
    // A friend takes a bot's seat in a practice room.
    if (this.practice && this.game.phase === 'waiting')
      while (this.game.players.size >= PRACTICE_SEATS && this.removeBot());
    if (!this.game.addPlayer(client.sessionId, auth.name, options?.hero))
      throw new ServerError(409, 'Round already starting');
    this.accounts.set(client.sessionId, auth);
    if (this.protocol === 2)
      void fetchLoadout(auth.accountId).then(({ items, pet }) =>
        this.game.setLoadout(client.sessionId, items, pet),
      );
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
      practice: this.practice,
      results: result.players.map((p) => ({
        is_bot: this.game.bots.has(p.id),
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
