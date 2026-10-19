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
/** Quick slot items 1-6 (protocol v2 only); ids match the API catalog. */
export const ITEMS = [
  'throw_bomb',
  'dart',
  'blue_shield',
  'speed_shoes',
  'freeze_bomb',
  'push_glove',
] as const;
export type ItemId = (typeof ITEMS)[number];
/** Design numbers from the HUD spec (balance after playtests). */
export const ITEM_RULES: Record<ItemId, { cooldown: number; range: number }> = {
  throw_bomb: { cooldown: 5000, range: 3 },
  dart: { cooldown: 800, range: 5 },
  blue_shield: { cooldown: 8000, range: 0 },
  speed_shoes: { cooldown: 6000, range: 0 },
  freeze_bomb: { cooldown: 6000, range: 2 },
  push_glove: { cooldown: 5000, range: 8 },
};
export const SHIELD_MS = 8000;
export const SPEED_MS = 5000;
export const SLOW_MS = 3000;
export const HIT_GRACE_MS = 600;
/** Per-player item state for v2 rooms: stock carried in, effects and cooldowns. */
export interface Gear {
  items: Record<ItemId, number>;
  cooldowns: Partial<Record<ItemId, number>>;
  facing: 'up' | 'down' | 'left' | 'right';
  pet: string | null;
  mounted: boolean;
  petUsed: boolean;
  shieldUntil: number;
  speedUntil: number;
  slowUntil: number;
  graceUntil: number;
}
export interface ItemEffect {
  kind: ItemId | 'mount' | 'guard';
  by: string;
  from: [number, number];
  to: [number, number];
  at: number;
}
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
  /** Thrown with an item: does not use up the player's one normal bomb. */
  thrown?: boolean;
}
export interface Flame {
  x: number;
  y: number;
  expiresAt: number;
}
export const directions = {
  up: [0, -1],
  down: [0, 1],
  left: [-1, 0],
  right: [1, 0],
} as const;
export const key = (x: number, y: number) => `${x},${y}`;

function newGear(): Gear {
  return {
    items: Object.fromEntries(ITEMS.map((i) => [i, 0])) as Record<
      ItemId,
      number
    >,
    cooldowns: {},
    facing: 'down',
    pet: null,
    mounted: false,
    petUsed: false,
    shieldUntil: 0,
    speedUntil: 0,
    slowUntil: 0,
    graceUntil: 0,
  };
}

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
  /** Server-driven bots (practice rooms); shown with `bot: true` in v2 snapshots. */
  bots = new Set<string>();
  /** v2 only: items, effects and facing per player. */
  gear = new Map<string, Gear>();
  /** Recent item events for client effects (kept ~1 s). */
  effects: ItemEffect[] = [];
  /** Called after the server accepts an item use (the room reports consumption). */
  onItemUsed: ((playerId: string, item: ItemId) => void) | null = null;
  private uses = new Map<string, ItemId | 'mount'>();
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
  /** Players needed before an all-ready lobby counts down (boss raids allow 1). */
  protected minPlayers = 2;
  protected roundMs = ROUND_MS;
  private nextBomb = 1;
  private inputs = new Map<string, Action>();

  get spawns(): readonly (readonly [number, number])[] {
    return this.map?.spawns ?? SPAWNS;
  }

  protected build(): Tile[][] {
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
    if (this.map) this.gear.set(id, newGear());
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
    this.gear.delete(id);
    this.uses.delete(id);
    this.heroes.delete(id);
    this.bots.delete(id);
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
        this.players.size >= this.minPlayers &&
        this.canStart() &&
        [...this.players.values()].every((player) => player.ready)
      ) {
        this.phase = 'countdown';
        this.deadline = this.now + 3000;
      }
      return true;
    }
    if (this.phase !== 'playing' || !p.alive) return false;
    // v2: items by id ("use_dart") and the mount ("mount"), one pending use each.
    const gear = this.gear.get(id);
    if (gear && (value === 'mount' || value.startsWith('use_'))) {
      const item = value === 'mount' ? 'mount' : value.slice(4);
      if (item !== 'mount' && !(ITEMS as readonly string[]).includes(item))
        return false;
      this.uses.set(id, item as ItemId | 'mount');
      return true;
    }
    if (!['up', 'down', 'left', 'right', 'bomb'].includes(value)) return false;
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
      this.deadline = this.now + this.roundMs;
      this.startedAt = this.now;
      // Players with a pet start the round riding it.
      for (const gear of this.gear.values()) gear.mounted = !!gear.pet;
      this.stats = new Map(
        [...this.players.keys()].map((id) => [
          id,
          { bombs: 0, kills: 0, diedAt: null },
        ]),
      );
      this.onStart();
    }
    if (this.phase === 'finished' && this.now >= this.deadline) this.reset();
    if (this.phase !== 'playing') {
      this.inputs.clear();
      this.uses.clear();
      return;
    }
    this.effects = this.effects.filter((e) => this.now - e.at < 1000);
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
    for (const [id, item] of this.uses) {
      this.uses.delete(id);
      const p = this.players.get(id);
      if (p?.alive) this.useItem(p, item);
    }
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
        p.nextMove = this.now + this.moveMs(p);
        const gear = this.gear.get(p.id);
        if (gear) gear.facing = action as Gear['facing'];
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
    this.step();
    this.killInFlames();
    if (this.phase === 'playing') this.resolveWinner();
    if (this.phase === 'playing' && this.now >= this.deadline) this.timeUp();
  }

  // Hooks for other modes (boss.ts); the PvP rules leave them empty.
  /** Whether an all-ready lobby may start a round now. */
  protected canStart(): boolean {
    return true;
  }
  /** Called once when a round starts playing. */
  protected onStart(): void {}
  /** Called every playing tick after movement, before knockouts are resolved. */
  protected step(): void {}
  /** The round clock ran out: a draw in PvP. */
  protected timeUp(): void {
    this.finish(null);
  }
  /** A blast reached (x, y); true stops the ray there, like a wall. */
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  protected onFlame(_x: number, _y: number, _bomb: Bomb): boolean {
    return false;
  }
  /** The server accepted an item use (support actions in boss raids). */
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  protected onItemAccepted(_id: string, _item: ItemId): void {}

  isWalkable(x: number, y: number): boolean {
    return (
      this.grid[y]?.[x] === Tile.Floor &&
      ![...this.bombs.values()].some((b) => b.x === x && b.y === y)
    );
  }

  private placeBomb(p: Player): void {
    if (
      !this.isWalkable(p.x, p.y) ||
      [...this.bombs.values()].some((b) => b.owner === p.id && !b.thrown)
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

  protected explode(id: number): void {
    const bomb = this.bombs.get(id);
    if (!bomb) return;
    this.bombs.delete(id); // Remove before chaining to prevent cycles.
    this.ignite(bomb.x, bomb.y, bomb.owner);
    this.onFlame(bomb.x, bomb.y, bomb);
    for (const [dx, dy] of Object.values(directions)) {
      for (let distance = 1; distance <= 2; distance++) {
        const x = bomb.x + dx * distance,
          y = bomb.y + dy * distance;
        const tile = this.grid[y]?.[x];
        if (tile === undefined || tile === Tile.Wall) break;
        this.ignite(x, y, bomb.owner);
        if (this.onFlame(x, y, bomb)) break;
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
  protected killInFlames(): void {
    for (const p of this.players.values()) {
      if (!p.alive || !this.flames.has(key(p.x, p.y))) continue;
      if (this.guarded(p)) continue;
      p.alive = false;
      const stats = this.stats.get(p.id);
      if (stats) stats.diedAt = this.now - this.startedAt;
      // Knockouts are credited to the bomb owner; self-knockouts do not count.
      const owner = this.flameOwners.get(key(p.x, p.y));
      const credit = owner && owner !== p.id ? this.stats.get(owner) : null;
      if (credit) credit.kills++;
    }
  }
  protected resolveWinner(): void {
    const alive = [...this.players.values()].filter((p) => p.alive);
    if (alive.length <= 1) this.finish(alive[0]?.id ?? null);
  }
  protected finish(winner: string | null): void {
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
  protected reset(): void {
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
      const gear = this.gear.get(p.id);
      if (gear)
        Object.assign(gear, { ...newGear(), items: gear.items, pet: gear.pet });
    }
    this.effects = [];
    this.uses.clear();
  }

  /** Items the player brings in (from the API stock) and their pet, if any. */
  setLoadout(
    id: string,
    items: Partial<Record<ItemId, number>>,
    pet: string | null,
  ): void {
    const gear = this.gear.get(id);
    if (!gear) return;
    for (const item of ITEMS)
      gear.items[item] = Math.max(
        0,
        Math.min(99, Math.floor(items[item] ?? 0)),
      );
    gear.pet = pet;
  }

  /** 150 ms a step; speed boots x1.35, mount x1.25, frozen x0.6. */
  moveMs(p: Player): number {
    const gear = this.gear.get(p.id);
    if (!gear) return MOVE_MS;
    let speed = 1;
    if (gear.speedUntil > this.now) speed *= 1.35;
    if (gear.mounted) speed *= 1.25;
    if (gear.slowUntil > this.now) speed *= 0.6;
    return Math.round(MOVE_MS / speed);
  }

  /** A shield or the mount absorbs one hit, then a short grace period. */
  protected guarded(p: Player): boolean {
    const gear = this.gear.get(p.id);
    if (!gear) return false;
    if (gear.graceUntil > this.now) return true;
    if (gear.shieldUntil > this.now) gear.shieldUntil = 0;
    else if (gear.mounted) {
      gear.mounted = false;
      gear.petUsed = true;
    } else return false;
    gear.graceUntil = this.now + HIT_GRACE_MS;
    this.effects.push({
      kind: 'guard',
      by: p.id,
      from: [p.x, p.y],
      to: [p.x, p.y],
      at: this.now,
    });
    return true;
  }

  private ahead(p: Player, steps: number): [number, number] {
    const [dx, dy] = directions[this.gear.get(p.id)!.facing];
    return [p.x + dx * steps, p.y + dy * steps];
  }

  /** Applies one item; nothing is consumed when the use has no valid target. */
  private useItem(p: Player, item: ItemId | 'mount'): void {
    const gear = this.gear.get(p.id)!;
    if (item === 'mount') {
      if (!gear.pet || (gear.petUsed && !gear.mounted)) return;
      gear.mounted = !gear.mounted;
      this.effects.push({
        kind: 'mount',
        by: p.id,
        from: [p.x, p.y],
        to: [p.x, p.y],
        at: this.now,
      });
      return;
    }
    if (gear.items[item] <= 0 || (gear.cooldowns[item] ?? 0) > this.now) return;
    const [dx, dy] = directions[gear.facing];
    let to: [number, number] = [p.x, p.y];
    let ok = false;
    switch (item) {
      case 'throw_bomb': {
        // Flies over crates and bombs, never past a wall; lands on the farthest free cell.
        for (let d = 1; d <= ITEM_RULES.throw_bomb.range; d++) {
          const x = p.x + dx * d,
            y = p.y + dy * d;
          const tile = this.grid[y]?.[x];
          if (tile === undefined || tile === Tile.Wall) break;
          if (
            this.isWalkable(x, y) &&
            ![...this.players.values()].some(
              (o) => o.alive && o.x === x && o.y === y,
            )
          )
            to = [x, y];
        }
        if (to[0] === p.x && to[1] === p.y) break;
        const id = this.nextBomb++;
        this.bombs.set(id, {
          id,
          owner: p.id,
          x: to[0],
          y: to[1],
          explodeAt: this.now + FUSE_MS,
          thrown: true,
        });
        ok = true;
        break;
      }
      case 'dart': {
        // Straight flight; the first bomb on its path explodes now, walls and crates stop it.
        for (let d = 1; d <= ITEM_RULES.dart.range; d++) {
          const x = p.x + dx * d,
            y = p.y + dy * d;
          const tile = this.grid[y]?.[x];
          to = [x, y];
          if (tile === undefined || tile !== Tile.Floor) break;
          const bomb = [...this.bombs.values()].find(
            (b) => b.x === x && b.y === y,
          );
          if (bomb) {
            this.explode(bomb.id); // detonates now; flames hit in this same tick
            break;
          }
        }
        ok = true;
        break;
      }
      case 'blue_shield':
        gear.shieldUntil = this.now + SHIELD_MS;
        ok = true;
        break;
      case 'speed_shoes':
        gear.speedUntil = this.now + SPEED_MS;
        ok = true;
        break;
      case 'freeze_bomb': {
        to = [p.x, p.y];
        for (let d = 1; d <= ITEM_RULES.freeze_bomb.range; d++) {
          const [x, y] = this.ahead(p, d);
          if (this.grid[y]?.[x] !== Tile.Floor) break;
          to = [x, y];
        }
        for (const other of this.players.values())
          if (
            other.id !== p.id &&
            other.alive &&
            Math.abs(other.x - to[0]) <= 1 &&
            Math.abs(other.y - to[1]) <= 1
          ) {
            const g = this.gear.get(other.id);
            if (g) g.slowUntil = this.now + SLOW_MS;
          }
        ok = true;
        break;
      }
      case 'push_glove': {
        const [bx, by] = this.ahead(p, 1);
        const bomb = [...this.bombs.values()].find(
          (b) => b.x === bx && b.y === by,
        );
        if (!bomb) break;
        let [x, y] = [bx, by];
        for (let d = 0; d < ITEM_RULES.push_glove.range; d++) {
          const nx = x + dx,
            ny = y + dy;
          if (
            !this.isWalkable(nx, ny) ||
            [...this.players.values()].some(
              (o) => o.alive && o.x === nx && o.y === ny,
            )
          )
            break;
          [x, y] = [nx, ny];
        }
        if (x === bx && y === by) break;
        bomb.x = x;
        bomb.y = y;
        to = [x, y];
        ok = true;
        break;
      }
    }
    if (!ok) return;
    gear.items[item] -= 1;
    gear.cooldowns[item] = this.now + ITEM_RULES[item].cooldown;
    this.effects.push({
      kind: item,
      by: p.id,
      from: [p.x, p.y],
      to,
      at: this.now,
    });
    this.onItemAccepted(p.id, item);
    this.onItemUsed?.(p.id, item);
  }

  private gearView(id: string) {
    const gear = this.gear.get(id);
    if (!gear) return {};
    const cooldowns: Record<string, number> = {};
    for (const item of ITEMS) {
      const left = (gear.cooldowns[item] ?? 0) - this.now;
      if (left > 0) cooldowns[item] = left;
    }
    return {
      facing: gear.facing,
      items: gear.items,
      cooldowns,
      pet: gear.pet,
      mounted: gear.mounted,
      petUsed: gear.petUsed,
      shield: gear.shieldUntil > this.now,
      fast: gear.speedUntil > this.now,
      slow: gear.slowUntil > this.now,
    };
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
        ...(this.bots.has(p.id) ? { bot: true } : {}),
        ...(this.map ? this.gearView(p.id) : {}),
      })),
      ...(this.map ? { effects: this.effects } : {}),
      bombs: [...this.bombs.values()],
      flames: [...this.flames.values()],
    };
  }
}
