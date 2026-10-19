import {
  Arena,
  ITEMS,
  MOVE_MS,
  Tile,
  directions,
  key,
  type Bomb,
  type ItemId,
  type Player,
} from './game.js';
import type { MapDef } from './maps.js';

/**
 * Boss raid (docs/BOSS.md, spec "BUPBUP Boss Event"): 1-8 players against one
 * server-driven boss on a normal map. Bombs, blasts, items and the mount are
 * the PvP rules (Arena); this adds the boss footprint, its HP and phases, five
 * telegraphed skills and the WIN / LOSE / TIMEOUT / ABORT result.
 * Everything is decided here: clients only draw the snapshot.
 */

export const BOSS_SKILLS = [
  'boss_basic_hit',
  'boss_aoe_mark',
  'boss_block_lane',
  'boss_wave_push',
  'boss_weak_point',
] as const;
export type BossSkill = (typeof BOSS_SKILLS)[number];

/** Raid rules from the event config (API); defaults are the spec's sample numbers. */
export interface BossRules {
  eventId: string;
  bossId: string;
  assetPackId: string;
  name: string;
  mapId: string;
  baseHp: number;
  hpPerExtraPlayer: number;
  phaseThresholds: number[];
  skills: BossSkill[];
  bombDamage: number;
  weakMultiplier: number;
  minPlayers: number;
  maxPlayers: number;
  durationSeconds: number;
  /** Quick slot items usable in the raid (whitelist) and whether pets may be ridden. */
  items: ItemId[];
  mount: boolean;
}

export const DEFAULT_RULES: BossRules = {
  eventId: '',
  bossId: 'boss_001',
  assetPackId: 'boss_001_placeholder',
  name: 'Boss Sự Kiện',
  mapId: 'harbor',
  baseHp: 1000,
  hpPerExtraPlayer: 0.55,
  phaseThresholds: [0.7, 0.35],
  skills: [...BOSS_SKILLS],
  bombDamage: 50,
  weakMultiplier: 1.5,
  minPlayers: 1,
  maxPlayers: 8,
  durationSeconds: 300,
  items: [...ITEMS],
  mount: true,
};

/** Telegraph (warning) time and cooldown per skill, in ms (playtest numbers). */
export const SKILL_TIMING: Record<
  BossSkill,
  { telegraph: number; cooldown: number }
> = {
  boss_basic_hit: { telegraph: 600, cooldown: 2500 },
  boss_aoe_mark: { telegraph: 1200, cooldown: 3500 },
  boss_block_lane: { telegraph: 1000, cooldown: 6000 },
  boss_wave_push: { telegraph: 1500, cooldown: 6000 },
  boss_weak_point: { telegraph: 400, cooldown: 9000 },
};
/** Gap between two casts per phase; phase 3 casts faster. */
export const CAST_GAP = [1600, 1200, 800];
export const BLOCK_MS = 3000;
export const WEAK_MS = 3000;
export const PUSH_CELLS = 2;
/** The boss footprint: 3 x 3 cells around the map centre (art can be larger). */
export const FOOTPRINT = 3;

export type RaidResult = 'WIN' | 'LOSE' | 'TIMEOUT' | 'ABORT';

export interface Cast {
  id: number;
  skill: BossSkill;
  tiles: [number, number][];
  castAt: number;
  resolveAt: number;
  /** wave push direction */
  dir?: keyof typeof directions;
}

export interface RaidStats {
  name: string;
  damage: number;
  support: number;
  actions: number;
  joinedAt: number;
  leftAt: number | null;
}

export interface RaidSummary {
  round: number;
  result: RaidResult;
  durationMs: number;
  hpMax: number;
  hpLeft: number;
  players: {
    id: string;
    name: string;
    damage: number;
    support: number;
    actions: number;
    activeMs: number;
    alive: boolean;
  }[];
}

/** hp(n) = round(base * (1 + k * (n - 1))), fixed when the raid starts. */
export function bossHp(rules: BossRules, players: number): number {
  return Math.round(
    rules.baseHp * (1 + rules.hpPerExtraPlayer * Math.max(0, players - 1)),
  );
}

export class BossArena extends Arena {
  rules: BossRules;
  /** False while the event is paused, ended or outside a session: no new raid. */
  open = true;
  /** Private room (invite only): economy rewards only if the event allows it. */
  privateRaid = false;
  /** "<process>.<room>": with the round, the raid id the API stores results under. */
  matchPrefix = '';
  /** Top-left cell of the footprint. */
  bossX = 0;
  bossY = 0;
  hp = 0;
  hpMax = 0;
  bossPhase = 1;
  weakUntil = 0;
  casts: Cast[] = [];
  /** Temporary walls from Block Lane: cell key -> expiry. */
  blocks = new Map<string, number>();
  raid = new Map<string, RaidStats>();
  raidResult: RaidResult | null = null;
  /** Ordered boss events (phase changes) so clients can apply them once. */
  seq = 0;
  onRaidEnd: ((summary: RaidSummary) => void) | null = null;
  private nextCastAt = 0;
  private readyAt = new Map<BossSkill, number>();
  private castCount = 0;
  private nextCast = 1;
  private hitBombs = new Set<number>();
  private rng: () => number;

  constructor(map: MapDef, rules: Partial<BossRules> = {}, seed = 1) {
    super(map);
    this.rules = { ...DEFAULT_RULES, ...rules };
    this.minPlayers = Math.max(1, this.rules.minPlayers);
    this.roundMs = this.rules.durationSeconds * 1000;
    let state = seed >>> 0 || 1;
    this.rng = () => {
      state = (state * 1664525 + 1013904223) >>> 0;
      return state / 2 ** 32;
    };
    this.placeBoss();
  }

  /** The footprint sits on the map centre, cleared of walls and crates. */
  private placeBoss(): void {
    const width = this.grid[0]!.length;
    const height = this.grid.length;
    this.bossX = Math.floor((width - FOOTPRINT) / 2);
    this.bossY = Math.floor((height - FOOTPRINT) / 2);
    for (let y = this.bossY; y < this.bossY + FOOTPRINT; y++)
      for (let x = this.bossX; x < this.bossX + FOOTPRINT; x++)
        this.grid[y]![x] = Tile.Floor;
  }

  isBoss(x: number, y: number): boolean {
    return (
      x >= this.bossX &&
      x < this.bossX + FOOTPRINT &&
      y >= this.bossY &&
      y < this.bossY + FOOTPRINT
    );
  }

  override isWalkable(x: number, y: number): boolean {
    return !this.isBoss(x, y) && super.isWalkable(x, y);
  }

  override addPlayer(id: string, name: string, hero?: unknown): boolean {
    if (this.players.size >= this.rules.maxPlayers) return false;
    if (!super.addPlayer(id, name, hero)) return false;
    return true;
  }

  override removePlayer(id: string): void {
    const stats = this.raid.get(id);
    if (stats && stats.leftAt === null) stats.leftAt = this.now;
    super.removePlayer(id);
  }

  override input(id: string, value: unknown): boolean {
    if (value === 'mount' && !this.rules.mount) return false;
    if (
      typeof value === 'string' &&
      value.startsWith('use_') &&
      !(this.rules.items as string[]).includes(value.slice(4))
    )
      return false;
    const accepted = super.input(id, value);
    const stats = this.raid.get(id);
    if (accepted && stats && this.phase === 'playing' && value !== 'ready')
      stats.actions++;
    return accepted;
  }

  protected override canStart(): boolean {
    return this.open;
  }

  protected override onStart(): void {
    this.hpMax = bossHp(this.rules, this.players.size);
    this.hp = this.hpMax;
    this.bossPhase = 1;
    this.weakUntil = 0;
    this.casts = [];
    this.blocks.clear();
    this.readyAt.clear();
    this.castCount = 0;
    this.hitBombs.clear();
    this.raidResult = null;
    this.nextCastAt = this.now + 1500;
    this.raid = new Map(
      [...this.players.values()].map((p) => [
        p.id,
        {
          name: p.name,
          damage: 0,
          support: 0,
          actions: 0,
          joinedAt: this.now,
          leftAt: null,
        },
      ]),
    );
  }

  protected override reset(): void {
    super.reset();
    this.placeBoss();
    this.casts = [];
    this.blocks.clear();
    this.hp = 0;
    this.hpMax = 0;
    this.bossPhase = 1;
    this.raidResult = null;
  }

  /** Blasts stop at the boss and hurt it once per bomb (chains: once per bomb id). */
  protected override onFlame(x: number, y: number, bomb: Bomb): boolean {
    if (!this.isBoss(x, y) || this.phase !== 'playing') return false;
    if (!this.hitBombs.has(bomb.id)) {
      this.hitBombs.add(bomb.id);
      const weak = this.weakUntil > this.now;
      const damage = Math.round(
        this.rules.bombDamage * (weak ? this.rules.weakMultiplier : 1),
      );
      const dealt = Math.min(this.hp, damage);
      this.hp -= dealt;
      const stats = this.raid.get(bomb.owner);
      if (stats) stats.damage += dealt;
      this.updatePhase();
    }
    return true;
  }

  protected override onItemAccepted(id: string): void {
    const stats = this.raid.get(id);
    if (stats) stats.support++;
  }

  private updatePhase(): void {
    const share = this.hpMax ? this.hp / this.hpMax : 0;
    let phase = 1;
    for (const threshold of this.rules.phaseThresholds)
      if (share <= threshold) phase++;
    // One step per threshold, never back.
    while (this.bossPhase < phase) {
      this.bossPhase++;
      this.seq++;
    }
  }

  protected override step(): void {
    for (const [cell, until] of this.blocks)
      if (until <= this.now) {
        this.blocks.delete(cell);
        const [x, y] = cell.split(',').map(Number) as [number, number];
        if (this.grid[y]![x] === Tile.Wall) this.grid[y]![x] = Tile.Floor;
      }
    for (const cast of [...this.casts])
      if (cast.resolveAt <= this.now) {
        this.casts = this.casts.filter((c) => c !== cast);
        this.resolve(cast);
      }
    if (this.phase === 'playing' && this.now >= this.nextCastAt) this.cast();
  }

  protected override resolveWinner(): void {
    // Everyone left (or the room closes): nobody wins, nothing is rewarded.
    if (!this.players.size) return this.end('ABORT');
    if (this.hpMax && this.hp <= 0) return this.end('WIN');
    if (![...this.players.values()].some((p) => p.alive)) this.end('LOSE');
  }

  protected override timeUp(): void {
    this.end('TIMEOUT');
  }

  private end(result: RaidResult): void {
    if (this.phase !== 'playing') return;
    this.raidResult = result;
    this.casts = [];
    this.finish(null);
    this.onRaidEnd?.(this.summary());
  }

  summary(): RaidSummary {
    const end = this.now;
    return {
      round: this.round,
      result: this.raidResult ?? 'ABORT',
      durationMs: end - this.startedAt,
      hpMax: this.hpMax,
      hpLeft: Math.max(0, this.hp),
      players: [...this.raid].map(([id, s]) => ({
        id,
        name: s.name,
        damage: s.damage,
        support: s.support,
        actions: s.actions,
        activeMs: (s.leftAt ?? end) - s.joinedAt,
        alive: !!this.players.get(id)?.alive && s.leftAt === null,
      })),
    };
  }

  // ------------------------------------------------------------ skills

  /** Skills the boss may use in its current phase (and the event allows). */
  pool(): BossSkill[] {
    const byPhase: BossSkill[][] = [
      ['boss_basic_hit', 'boss_aoe_mark'],
      ['boss_basic_hit', 'boss_aoe_mark', 'boss_block_lane', 'boss_wave_push'],
      [
        'boss_aoe_mark',
        'boss_block_lane',
        'boss_wave_push',
        'boss_basic_hit',
        'boss_weak_point',
      ],
    ];
    const allowed = new Set(this.rules.skills);
    return byPhase[Math.min(2, this.bossPhase - 1)]!.filter(
      (s) => allowed.has(s) && (this.readyAt.get(s) ?? 0) <= this.now,
    );
  }

  private cast(): void {
    // One telegraph at a time keeps a way out on the board.
    if (this.casts.length) return;
    let skills = this.pool();
    // Phase 3 opens the weak point every third cast (when allowed).
    if (
      this.bossPhase === 3 &&
      skills.includes('boss_weak_point') &&
      this.castCount % 3 === 2
    )
      skills = ['boss_weak_point'];
    else {
      const rest = skills.filter((s) => s !== 'boss_weak_point');
      skills = rest.length ? rest : skills;
    }
    while (skills.length) {
      const skill = skills.splice(
        Math.floor(this.rng() * skills.length),
        1,
      )[0]!;
      const cast = this.plan(skill);
      if (cast) {
        this.casts.push(cast);
        this.castCount++;
        this.readyAt.set(skill, this.now + SKILL_TIMING[skill].cooldown);
        this.nextCastAt =
          cast.resolveAt + CAST_GAP[Math.min(2, this.bossPhase - 1)]!;
        return;
      }
    }
    this.nextCastAt = this.now + 500;
  }

  private floor(x: number, y: number): boolean {
    return this.grid[y]?.[x] === Tile.Floor && !this.isBoss(x, y);
  }

  /** Floor cells around the footprint (basic hit). */
  ring(): [number, number][] {
    const out: [number, number][] = [];
    for (let y = this.bossY - 1; y <= this.bossY + FOOTPRINT; y++)
      for (let x = this.bossX - 1; x <= this.bossX + FOOTPRINT; x++)
        if (!this.isBoss(x, y) && this.floor(x, y)) out.push([x, y]);
    return out;
  }

  /** A telegraph for `skill`, or null when it would leave someone no way out. */
  plan(skill: BossSkill): Cast | null {
    const telegraph = SKILL_TIMING[skill].telegraph;
    const alive = [...this.players.values()].filter((p) => p.alive);
    let tiles: [number, number][] = [];
    let dir: Cast['dir'];
    if (skill === 'boss_basic_hit') tiles = this.ring();
    else if (skill === 'boss_aoe_mark') {
      const targets = [...alive]
        .sort(() => this.rng() - 0.5)
        .slice(0, this.bossPhase);
      const radius = this.bossPhase === 3 ? 2 : 1;
      const seen = new Set<string>();
      for (const t of targets)
        for (let dy = -radius; dy <= radius; dy++)
          for (let dx = -radius; dx <= radius; dx++) {
            const x = t.x + dx,
              y = t.y + dy;
            if (this.floor(x, y) && !seen.has(key(x, y))) {
              seen.add(key(x, y));
              tiles.push([x, y]);
            }
          }
    } else if (skill === 'boss_block_lane') {
      // Up to 4 free cells of one row or column through the boss.
      const horizontal = this.rng() < 0.5;
      const line =
        (horizontal ? this.bossY : this.bossX) +
        Math.floor(this.rng() * FOOTPRINT);
      const cells: [number, number][] = [];
      const length = horizontal ? this.grid[0]!.length : this.grid.length;
      for (let i = 0; i < length; i++) {
        const [x, y] = horizontal ? [i, line] : [line, i];
        if (
          this.floor(x, y) &&
          !alive.some((p) => p.x === x && p.y === y) &&
          ![...this.bombs.values()].some((b) => b.x === x && b.y === y)
        )
          cells.push([x, y]);
      }
      tiles = cells.sort(() => this.rng() - 0.5).slice(0, 4);
    } else if (skill === 'boss_wave_push') {
      const names = Object.keys(directions) as (keyof typeof directions)[];
      dir = names[Math.floor(this.rng() * names.length)]!;
      const horizontal = dir === 'left' || dir === 'right';
      for (let y = 0; y < this.grid.length; y++)
        for (let x = 0; x < this.grid[0]!.length; x++) {
          const inBand = horizontal
            ? y >= this.bossY && y < this.bossY + FOOTPRINT
            : x >= this.bossX && x < this.bossX + FOOTPRINT;
          if (inBand && this.floor(x, y)) tiles.push([x, y]);
        }
    } else {
      for (let y = this.bossY; y < this.bossY + FOOTPRINT; y++)
        for (let x = this.bossX; x < this.bossX + FOOTPRINT; x++)
          tiles.push([x, y]);
    }
    if (!tiles.length) return null;
    const hurts = skill === 'boss_basic_hit' || skill === 'boss_aoe_mark';
    if (hurts && !alive.every((p) => this.canEscape(p, tiles, telegraph)))
      return null;
    if (skill === 'boss_block_lane' && !this.leavesRoom(tiles, alive))
      return null;
    return {
      id: this.nextCast++,
      skill,
      tiles,
      castAt: this.now,
      resolveAt: this.now + telegraph,
      ...(dir ? { dir } : {}),
    };
  }

  /**
   * Safe-tile guarantee: a walkable cell outside `danger` is reachable before the
   * hit, at the player's walking speed.
   */
  canEscape(p: Player, danger: [number, number][], ms: number): boolean {
    const bad = new Set(danger.map(([x, y]) => key(x, y)));
    const steps = Math.floor(ms / Math.max(MOVE_MS, this.moveMs(p)));
    let frontier: [number, number][] = [[p.x, p.y]];
    const seen = new Set([key(p.x, p.y)]);
    for (let d = 0; d <= steps; d++) {
      const next: [number, number][] = [];
      for (const [x, y] of frontier) {
        if (!bad.has(key(x, y))) return true;
        for (const [dx, dy] of Object.values(directions)) {
          const nx = x + dx,
            ny = y + dy;
          if (!seen.has(key(nx, ny)) && this.isWalkable(nx, ny)) {
            seen.add(key(nx, ny));
            next.push([nx, ny]);
          }
        }
      }
      frontier = next;
    }
    return false;
  }

  /** Block Lane never boxes a player in: each keeps at least 4 reachable cells. */
  private leavesRoom(walls: [number, number][], alive: Player[]): boolean {
    const blocked = new Set(walls.map(([x, y]) => key(x, y)));
    return alive.every((p) => {
      const seen = new Set([key(p.x, p.y)]);
      const todo: [number, number][] = [[p.x, p.y]];
      while (todo.length && seen.size < 4) {
        const [x, y] = todo.pop()!;
        for (const [dx, dy] of Object.values(directions)) {
          const nx = x + dx,
            ny = y + dy;
          const k = key(nx, ny);
          if (!seen.has(k) && !blocked.has(k) && this.isWalkable(nx, ny)) {
            seen.add(k);
            todo.push([nx, ny]);
          }
        }
      }
      return seen.size >= 4;
    });
  }

  private resolve(cast: Cast): void {
    const cells = new Set(cast.tiles.map(([x, y]) => key(x, y)));
    switch (cast.skill) {
      case 'boss_basic_hit':
      case 'boss_aoe_mark':
        for (const p of this.players.values())
          if (p.alive && cells.has(key(p.x, p.y))) this.hurt(p);
        break;
      case 'boss_block_lane':
        for (const [x, y] of cast.tiles) {
          const free =
            this.grid[y]![x] === Tile.Floor &&
            ![...this.players.values()].some(
              (p) => p.alive && p.x === x && p.y === y,
            ) &&
            ![...this.bombs.values()].some((b) => b.x === x && b.y === y);
          if (free) {
            this.grid[y]![x] = Tile.Wall;
            this.blocks.set(key(x, y), this.now + BLOCK_MS);
          }
        }
        break;
      case 'boss_wave_push': {
        const [dx, dy] = directions[cast.dir ?? 'right'];
        const movers: { x: number; y: number }[] = [
          ...[...this.players.values()].filter((p) => p.alive),
          ...this.bombs.values(),
        ].filter((m) => cells.has(key(m.x, m.y)));
        // Farthest along the push first, so a row slides without overlapping.
        movers.sort((a, b) => (b.x - a.x) * dx + (b.y - a.y) * dy);
        for (const m of movers)
          for (let i = 0; i < PUSH_CELLS; i++) {
            const nx = m.x + dx,
              ny = m.y + dy;
            const taken = [...this.players.values()].some(
              (p) => p.alive && p.x === nx && p.y === ny,
            );
            if (!this.isWalkable(nx, ny) || taken) break;
            m.x = nx;
            m.y = ny;
          }
        break;
      }
      case 'boss_weak_point':
        this.weakUntil = this.now + WEAK_MS;
        break;
    }
  }

  /** A boss hit: a shield or the mount absorbs it, otherwise the player is out. */
  private hurt(p: Player): void {
    if (this.guarded(p)) return;
    p.alive = false;
    const stats = this.stats.get(p.id);
    if (stats) stats.diedAt = this.now - this.startedAt;
  }

  override snapshot() {
    return {
      ...super.snapshot(),
      mode: 'boss',
      boss: {
        id: this.rules.bossId,
        assetPack: this.rules.assetPackId,
        name: this.rules.name,
        x: this.bossX,
        y: this.bossY,
        size: FOOTPRINT,
        hp: Math.max(0, this.hp),
        maxHp: this.hpMax || bossHp(this.rules, Math.max(1, this.players.size)),
        phase: this.bossPhase,
        thresholds: this.rules.phaseThresholds,
        weak: this.weakUntil > this.now,
        seq: this.seq,
        casts: this.casts.map((c) => ({
          id: c.id,
          skill: c.skill,
          tiles: c.tiles,
          castAt: c.castAt,
          resolveAt: c.resolveAt,
          ...(c.dir ? { dir: c.dir } : {}),
        })),
      },
      raid: {
        eventId: this.rules.eventId,
        matchId: this.matchPrefix ? `${this.matchPrefix}.${this.round}` : '',
        private: this.privateRaid,
        items: this.rules.items,
        mount: this.rules.mount,
        open: this.open,
        result: this.raidResult,
        minPlayers: this.rules.minPlayers,
        maxPlayers: this.rules.maxPlayers,
        damage: Object.fromEntries(
          [...this.raid].map(([id, s]) => [id, s.damage]),
        ),
      },
    };
  }
}
