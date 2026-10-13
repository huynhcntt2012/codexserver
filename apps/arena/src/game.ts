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
  grid = createMap();
  players = new Map<string, Player>();
  bombs = new Map<number, Bomb>();
  flames = new Map<string, Flame>();
  phase: Phase = 'waiting';
  now = 0;
  deadline = 0;
  winner: string | null = null;
  round = 1;
  private nextBomb = 1;
  private inputs = new Map<string, Action>();

  addPlayer(id: string, name: string): boolean {
    if (
      this.phase !== 'waiting' ||
      this.players.size >= 8 ||
      this.players.has(id)
    )
      return false;
    const slot = SPAWNS.findIndex(
      (_, i) => ![...this.players.values()].some((p) => p.slot === i),
    );
    const [x, y] = SPAWNS[slot]!;
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
    // One pending action per player/tick; packets cannot accelerate the clock.
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
    }
    if (this.phase === 'finished' && this.now >= this.deadline) this.reset();
    if (this.phase !== 'playing') {
      this.inputs.clear();
      return;
    }
    for (const [k, flame] of this.flames)
      if (flame.expiresAt <= this.now) this.flames.delete(k);
    // Flames and all due bombs resolve before movement and before winner selection.
    for (const bomb of [...this.bombs.values()]) {
      if (bomb.explodeAt <= this.now) this.explode(bomb.id);
    }
    this.killInFlames();
    for (const [id, action] of this.inputs) {
      const p = this.players.get(id);
      if (!p?.alive) continue;
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
    this.inputs.clear();
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
    this.ignite(bomb.x, bomb.y);
    for (const [dx, dy] of Object.values(directions)) {
      for (let distance = 1; distance <= 2; distance++) {
        const x = bomb.x + dx * distance,
          y = bomb.y + dy * distance;
        const tile = this.grid[y]?.[x];
        if (tile === undefined || tile === Tile.Wall) break;
        this.ignite(x, y);
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

  private ignite(x: number, y: number): void {
    this.flames.set(key(x, y), { x, y, expiresAt: this.now + FLAME_MS });
  }
  private killInFlames(): void {
    for (const p of this.players.values())
      if (this.flames.has(key(p.x, p.y))) p.alive = false;
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
  }
  private reset(): void {
    this.grid = createMap();
    this.bombs.clear();
    this.flames.clear();
    this.winner = null;
    this.phase = 'waiting';
    this.round++;
    for (const p of this.players.values()) {
      [p.x, p.y] = SPAWNS[p.slot]!;
      p.alive = true;
      p.ready = false;
      p.nextMove = 0;
    }
  }
  snapshot() {
    return {
      version: 1,
      width: WIDTH,
      height: HEIGHT,
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
      })),
      bombs: [...this.bombs.values()],
      flames: [...this.flames.values()],
    };
  }
}
