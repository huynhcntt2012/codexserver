import { HEROES, type MapDef } from './maps.js';

export const WIDTH = 15;
export const HEIGHT = 13;
export const TICK_MS = 50;
export const MOVE_MS = 150;
export const FUSE_MS = 2000;
export const FLAME_MS = 500;
export const ROUND_MS = 180_000;
export const SPAWNS = [
  [1, 1],
  [13, 11],
  [13, 1],
  [1, 11],
  [7, 1],
  [7, 11],
  [1, 7],
  [13, 7],
] as const;
export enum Tile {
  Floor,
  Wall,
  Crate,
}
export type Phase = 'waiting' | 'countdown' | 'playing' | 'finished';
export type Action = 'up' | 'down' | 'left' | 'right' | 'bomb' | 'ready';
export interface Player {
  id: string;
  name: string;
  slot: number;
  x: number;
  y: number;
  alive: boolean;
  ready: boolean;
  nextMove: number;
}
/** Per-round counters kept outside the snapshot, so protocol v1 is unchanged. */
export interface RoundStats {
  bombs: number;
  kills: number;
  diedAt: number | null;
}
export interface RoundResult {
  round: number;
  durationMs: number;
  winner: string | null;
  players: {
    id: string;
    name: string;
    placement: number;
    bombs: number;
    kills: number;
    survivedMs: number;
    winner: boolean;
  }[];
}
export interface Bomb {
  id: number;
  owner: string;
  x: number;
  y: number;
  explodeAt: number;
}
export interface Flame {
  x: number;
  y: number;
  expiresAt: number;
}
const directions = {
  up: [0, -1],
  down: [0, 1],
  left: [-1, 0],
  right: [1, 0],
} as const;
const key = (x: number, y: number) => `${x},${y}`;

/** v2 grid from a shared layout; crates within two steps of a spawn are cleared. */
export function createLayoutMap(map: MapDef): Tile[][] {
  return map.layout.map((line, y) =>
    [...line].map((cell, x) => {
      if (cell === '#') return Tile.Wall;
      if (
        cell === 'C' &&
        !map.spawns.some(([sx, sy]) => Math.abs(x - sx) + Math.abs(y - sy) <= 2)
      )
        return Tile.Crate;
      return Tile.Floor;
    }),
  );
}

/** Original deterministic layout. Every spawn has an escape corridor. */
export function createMap(): Tile[][] {
  return Array.from({ length: HEIGHT }, (_, y) =>
    Array.from({ length: WIDTH }, (_, x) => {
      if (
        x === 0 ||
        y === 0 ||
        x === WIDTH - 1 ||
        y === HEIGHT - 1 ||
        (x % 2 === 0 && y % 2 === 0)
      )
        return Tile.Wall;
      if (SPAWNS.some(([sx, sy]) => Math.abs(x - sx) + Math.abs(y - sy) <= 2))
        return Tile.Floor;
      return (x * 7 + y * 11) % 5 === 0 ? Tile.Floor : Tile.Crate;
    }),
  );
}

/** Pure authoritative simulation: time advances only through server ticks. */
export class Arena {
  /** Protocol v1 keeps the original map; v2 rooms pass a shared layout. */
  constructor(readonly map: MapDef | null = null) {
    this.grid = this.build();
  }
  grid: Tile[][];
  /** v2 only: cosmetic hero id per player, validated against HEROES. */
  heroes = new Map<string, string>();
  players = new Map<string, Player>();
  bombs = new Map<number, Bomb>();
  flames = new Map<string, Flame>();
  phase: Phase = 'waiting';
  now = 0;
  deadline = 0;
  winner: string | null = null;
  round = 1;
  stats = new Map<string, RoundStats>();
  startedAt = 0;
  /** Called after a round becomes finished; must not block the tick. */
  onRoundEnd: ((result: RoundResult) => void) | null = null;
  private flameOwners = new Map<string, string>();
  private nextBomb = 1;
  private inputs = new Map<string, Action>();

  get spawns(): readonly (readonly [number, number])[] {
    return this.map?.spawns ?? SPAWNS;
  }

  private build(): Tile[][] {
    return this.map ? createLayoutMap(this.map) : createMap();
  }

  addPlayer(id: string, name: string, hero?: unknown): boolean {
    if (
      this.phase !== 'waiting' ||
      this.players.size >= 8 ||
      this.players.has(id)
    )
      return false;
    const slot = this.spawns.findIndex(
      (_, i) => ![...this.players.values()].some((p) => p.slot === i),
    );
    const [x, y] = this.spawns[slot]!;
    this.heroes.set(
      id,
      HEROES.includes(hero as (typeof HEROES)[number])
        ? (hero as string)
        : HEROES[slot % HEROES.length]!,
    );
    this.players.set(id, {
      id,
      name: name.slice(0, 24),
      slot,
      x,
      y,
      alive: true,
      ready: false,
      nextMove: 0,
    });
    return true;
  }

  removePlayer(id: string): void {
    this.players.delete(id);
    this.heroes.delete(id);
    this.inputs.delete(id);
    if (this.phase === 'countdown') {
      this.phase = 'waiting';
      for (const p of this.players.values()) p.ready = false;
    }
    if (this.phase === 'playing') this.resolveWinner();
  }

  input(id: string, value: unknown): boolean {
    const p = this.players.get(id);
    if (!p || typeof value !== 'string') return false;
    if (value === 'ready' && this.phase === 'waiting') {
      p.ready = true;
      if (
        this.players.size >= 2 &&
        [...this.players.values()].every((player) => player.ready)
      ) {
        this.phase = 'countdown';
        this.deadline = this.now + 3000;
      }
      return true;
    }
    if (
      this.phase !== 'playing' ||
      !p.alive ||
      !['up', 'down', 'left', 'right', 'bomb'].includes(value)
    )
      return false;
    // One pending action per player; an early move waits for the next legal step.
    // New directions replace the buffered direction; packets cannot accelerate time.
    // A bomb has priority over held movement, so a key press is not lost.
    if (this.inputs.get(id) !== 'bomb') this.inputs.set(id, value as Action);
    return true;
  }

  tick(delta = TICK_MS): void {
    if (!Number.isFinite(delta) || delta <= 0)
      throw new Error('Invalid tick duration');
    this.now += delta;
    if (this.phase === 'countdown' && this.now >= this.deadline) {
      this.phase = 'playing';
      this.deadline = this.now + ROUND_MS;
      this.startedAt = this.now;
      this.stats = new Map(
        [...this.players.keys()].map((id) => [
          id,
          { bombs: 0, kills: 0, diedAt: null },
        ]),
      );
    }
    if (this.phase === 'finished' && this.now >= this.deadline) this.reset();
    if (this.phase !== 'playing') {
      this.inputs.clear();
      return;
    }
    for (const [k, flame] of this.flames)
      if (flame.expiresAt <= this.now) {
        this.flames.delete(k);
        this.flameOwners.delete(k);
      }
    // Flames and all due bombs resolve before movement and before winner selection.
    for (const bomb of [...this.bombs.values()]) {
      if (bomb.explodeAt <= this.now) this.explode(bomb.id);
    }
    this.killInFlames();
    for (const [id, action] of this.inputs) {
      const p = this.players.get(id);
      if (!p?.alive) {
        this.inputs.delete(id);
        continue;
      }
      if (action !== 'bomb' && this.now < p.nextMove) continue;
      this.inputs.delete(id);
      if (action === 'bomb') this.placeBomb(p);
      else if (action in directions && this.now >= p.nextMove) {
        const [dx, dy] = directions[action as keyof typeof directions];
        const x = p.x + dx,
          y = p.y + dy;
        p.nextMove = this.now + MOVE_MS;
        if (
          this.isWalkable(x, y) &&
          ![...this.players.values()].some(
            (other) =>
              other.id !== p.id &&
              other.alive &&
              other.x === x &&
              other.y === y,
          )
        ) {
          p.x = x;
          p.y = y;
        }
      }
    }
    this.killInFlames();
    this.resolveWinner();
    if (this.phase === 'playing' && this.now >= this.deadline)
      this.finish(null);
  }

  isWalkable(x: number, y: number): boolean {
    return (
      this.grid[y]?.[x] === Tile.Floor &&
      ![...this.bombs.values()].some((b) => b.x === x && b.y === y)
    );
  }

  private placeBomb(p: Player): void {
    if (
      !this.isWalkable(p.x, p.y) ||
      [...this.bombs.values()].some((b) => b.owner === p.id)
    )
      return;
    const id = this.nextBomb++;
    const stats = this.stats.get(p.id);
    if (stats) stats.bombs++;
    this.bombs.set(id, {
      id,
      owner: p.id,
      x: p.x,
      y: p.y,
      explodeAt: this.now + FUSE_MS,
    });
  }

  private explode(id: number): void {
    const bomb = this.bombs.get(id);
    if (!bomb) return;
    this.bombs.delete(id); // Remove before chaining to prevent cycles.
    this.ignite(bomb.x, bomb.y, bomb.owner);
    for (const [dx, dy] of Object.values(directions)) {
      for (let distance = 1; distance <= 2; distance++) {
        const x = bomb.x + dx * distance,
          y = bomb.y + dy * distance;
        const tile = this.grid[y]?.[x];
        if (tile === undefined || tile === Tile.Wall) break;
        this.ignite(x, y, bomb.owner);
        if (tile === Tile.Crate) {
          this.grid[y]![x] = Tile.Floor;
          break;
        }
        const chained = [...this.bombs.values()].find(
          (b) => b.x === x && b.y === y,
        );
        if (chained) {
          this.explode(chained.id);
          break;
        }
      }
    }
  }

  private ignite(x: number, y: number, owner: string): void {
    this.flames.set(key(x, y), { x, y, expiresAt: this.now + FLAME_MS });
    this.flameOwners.set(key(x, y), owner);
  }
  private killInFlames(): void {
    for (const p of this.players.values()) {
      if (!p.alive || !this.flames.has(key(p.x, p.y))) continue;
      p.alive = false;
      const stats = this.stats.get(p.id);
      if (stats) stats.diedAt = this.now - this.startedAt;
      // Knockouts are credited to the bomb owner; self-knockouts do not count.
      const owner = this.flameOwners.get(key(p.x, p.y));
      const credit = owner && owner !== p.id ? this.stats.get(owner) : null;
      if (credit) credit.kills++;
    }
  }
  private resolveWinner(): void {
    const alive = [...this.players.values()].filter((p) => p.alive);
    if (alive.length <= 1) this.finish(alive[0]?.id ?? null);
  }
  private finish(winner: string | null): void {
    this.phase = 'finished';
    this.winner = winner;
    this.deadline = this.now + 8000;
    this.inputs.clear();
    this.onRoundEnd?.(this.result());
  }
  /** Survivors first (winner on top), then later knockouts before earlier ones. */
  result(): RoundResult {
    const durationMs = this.now - this.startedAt;
    const ranked = [...this.players.values()]
      .map((p) => {
        const stats = this.stats.get(p.id) ?? {
          bombs: 0,
          kills: 0,
          diedAt: null,
        };
        return { p, stats, survived: stats.diedAt ?? durationMs };
      })
      .sort(
        (a, b) =>
          Number(b.p.id === this.winner) - Number(a.p.id === this.winner) ||
          b.survived - a.survived,
      );
    return {
      round: this.round,
      durationMs,
      winner: this.winner,
      players: ranked.map(({ p, stats, survived }, i) => ({
        id: p.id,
        name: p.name,
        placement: i + 1,
        bombs: stats.bombs,
        kills: stats.kills,
        survivedMs: survived,
        winner: p.id === this.winner,
      })),
    };
  }
  private reset(): void {
    this.grid = this.build();
    this.bombs.clear();
    this.flames.clear();
    this.flameOwners.clear();
    this.stats.clear();
    this.winner = null;
    this.phase = 'waiting';
    this.round++;
    for (const p of this.players.values()) {
      [p.x, p.y] = this.spawns[p.slot]!;
      p.alive = true;
      p.ready = false;
      p.nextMove = 0;
    }
  }
  snapshot() {
    return {
      version: 1,
      width: this.map?.width ?? WIDTH,
      height: this.map?.height ?? HEIGHT,
      phase: this.phase,
      now: this.now,
      deadline: this.deadline,
      winner: this.winner,
      round: this.round,
      grid: this.grid,
      players: [...this.players.values()].map((p) => ({
        id: p.id,
        name: p.name,
        slot: p.slot,
        x: p.x,
        y: p.y,
        alive: p.alive,
        ready: p.ready,
        ...(this.map ? { hero: this.heroes.get(p.id) } : {}),
      })),
      bombs: [...this.bombs.values()],
      flames: [...this.flames.values()],
    };
  }
}
