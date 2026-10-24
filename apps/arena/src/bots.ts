import { Tile, MOVE_MS, FUSE_MS, type Action, type Arena } from './game.js';

/**
 * Server-side bots for practice rooms. A bot only ever calls Arena.input() with
 * the same intents a player sends, so it obeys every rule (move rate, one bomb,
 * collisions). Decisions read the authoritative state: grid, bombs, flames.
 */
const RANGE = 2;
const STEPS: readonly [Action, number, number][] = [
  ['up', 0, -1],
  ['down', 0, 1],
  ['left', -1, 0],
  ['right', 1, 0],
];
const key = (x: number, y: number) => `${x},${y}`;

/** Cells a bomb at (x, y) will flood, stopping at walls and after crates. */
export function blast(arena: Arena, x: number, y: number): string[] {
  const cells = [key(x, y)];
  for (const [, dx, dy] of STEPS) {
    for (let d = 1; d <= RANGE; d++) {
      const tile = arena.grid[y + dy * d]?.[x + dx * d];
      if (tile === undefined || tile === Tile.Wall) break;
      cells.push(key(x + dx * d, y + dy * d));
      if (tile === Tile.Crate) break;
    }
  }
  return cells;
}

/** Cells that are on fire now or will be when a known bomb goes off. */
export function danger(arena: Arena, extra?: [number, number]): Set<string> {
  const out = new Set<string>();
  for (const flame of arena.flames.values()) out.add(key(flame.x, flame.y));
  const bombs = [...arena.bombs.values()].map((b) => [b.x, b.y] as const);
  if (extra) bombs.push(extra);
  for (const [x, y] of bombs)
    for (const cell of blast(arena, x, y)) out.add(cell);
  return out;
}

function open(arena: Arena, x: number, y: number, self: string): boolean {
  return (
    arena.isWalkable(x, y) &&
    ![...arena.players.values()].some(
      (p) => p.id !== self && p.alive && p.x === x && p.y === y,
    )
  );
}

/** Breadth-first search; returns the first step towards the nearest goal cell. */
function route(
  arena: Arena,
  self: string,
  from: [number, number],
  goal: (x: number, y: number) => boolean,
  avoid: Set<string>,
  limit = 12,
): Action | null {
  const seen = new Set([key(...from)]);
  const queue: [number, number, Action | null, number][] = [[...from, null, 0]];
  while (queue.length) {
    const [x, y, first, depth] = queue.shift()!;
    if (first && goal(x, y)) return first;
    if (depth >= limit) continue;
    for (const [action, dx, dy] of STEPS) {
      const nx = x + dx,
        ny = y + dy;
      if (seen.has(key(nx, ny)) || !open(arena, nx, ny, self)) continue;
      // A cell already burning is never entered; future blasts only if escaping.
      if (avoid.has(key(nx, ny)) && arena.flames.has(key(nx, ny))) continue;
      seen.add(key(nx, ny));
      queue.push([nx, ny, first ?? action, depth + 1]);
    }
  }
  return null;
}

export class BotBrain {
  private next = 0;
  constructor(
    readonly id: string,
    private random: () => number,
  ) {}

  /** One decision at most every move step (plus a little human-like delay). */
  think(arena: Arena): Action | null {
    const me = arena.players.get(this.id);
    if (!me?.alive || arena.phase !== 'playing' || arena.now < this.next)
      return null;
    this.next = arena.now + MOVE_MS + Math.floor(this.random() * 120);
    const here: [number, number] = [me.x, me.y];
    const hot = danger(arena);
    if (hot.has(key(...here)))
      return route(arena, this.id, here, (x, y) => !hot.has(key(x, y)), hot, 8);
    const ownBomb = [...arena.bombs.values()].some((b) => b.owner === this.id);
    if (
      !ownBomb &&
      this.worthBombing(arena, here) &&
      this.canEscape(arena, here)
    )
      return 'bomb';
    // Walk to a cell next to a crate or within reach of a rival, never into danger.
    const target = (x: number, y: number) =>
      !hot.has(key(x, y)) &&
      (STEPS.some(
        ([, dx, dy]) => arena.grid[y + dy]?.[x + dx] === Tile.Crate,
      ) ||
        [...arena.players.values()].some(
          (p) =>
            p.id !== this.id &&
            p.alive &&
            ((p.x === x && Math.abs(p.y - y) <= RANGE) ||
              (p.y === y && Math.abs(p.x - x) <= RANGE)),
        ));
    const step = route(arena, this.id, here, target, hot);
    if (step && !hot.has(this.after(here, step))) return step;
    // Nothing to do: wander to a random safe neighbour now and then.
    const safe = STEPS.filter(
      ([, dx, dy]) =>
        open(arena, me.x + dx, me.y + dy, this.id) &&
        !hot.has(key(me.x + dx, me.y + dy)),
    );
    return safe.length && this.random() < 0.5
      ? safe[Math.floor(this.random() * safe.length)]![0]
      : null;
  }

  private after([x, y]: [number, number], step: Action): string {
    const [, dx, dy] = STEPS.find(([a]) => a === step)!;
    return key(x + dx, y + dy);
  }

  private worthBombing(arena: Arena, [x, y]: [number, number]): boolean {
    const cells = new Set(blast(arena, x, y));
    const crate = STEPS.some(
      ([, dx, dy]) => arena.grid[y + dy]?.[x + dx] === Tile.Crate,
    );
    const rival = [...arena.players.values()].some(
      (p) => p.id !== this.id && p.alive && cells.has(key(p.x, p.y)),
    );
    return rival || (crate && this.random() < 0.8);
  }

  /** After planting here, a safe cell must be reachable before the fuse ends. */
  private canEscape(arena: Arena, here: [number, number]): boolean {
    const hot = danger(arena, here);
    const steps = Math.floor(FUSE_MS / MOVE_MS) - 3;
    const seen = new Set([key(...here)]);
    const queue: [number, number, number][] = [[...here, 0]];
    while (queue.length) {
      const [x, y, depth] = queue.shift()!;
      if (depth > 0 && !hot.has(key(x, y))) return true;
      if (depth >= steps) continue;
      for (const [, dx, dy] of STEPS) {
        const nx = x + dx,
          ny = y + dy;
        if (seen.has(key(nx, ny)) || !open(arena, nx, ny, this.id)) continue;
        seen.add(key(nx, ny));
        queue.push([nx, ny, depth + 1]);
      }
    }
    return false;
  }
}
