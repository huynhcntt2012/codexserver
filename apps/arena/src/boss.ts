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
 * the PvP rules (Arena); this adds the boss footprint, its HP and phases, the
 * telegraphed skills and the WIN / LOSE / TIMEOUT / ABORT result.
 * Two skill sets: the Slime King's five `boss_*` skills and the Clockwork Bomb
 * Robot's seven `robot_*` skills (spec "Robot Bom Dây Cót", SK01-SK07), whose
 * bombs blast in a + along the grid. The robot also walks (`walkMs`).
 * Everything is decided here: clients only draw the snapshot.
 */

export const SLIME_SKILLS = [
  'boss_basic_hit',
  'boss_aoe_mark',
  'boss_block_lane',
  'boss_wave_push',
  'boss_weak_point',
] as const;
/** SK01-SK07 of the robot spec, in order. */
export const ROBOT_SKILLS = [
  'robot_bomb_launch',
  'robot_bomb_chain',
  'robot_mini_chaser',
  'robot_recoil_dash',
  'robot_magnet_pull',
  'robot_overheat',
  'robot_reactor',
] as const;
export const BOSS_SKILLS = [...SLIME_SKILLS, ...ROBOT_SKILLS] as const;
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
  /** Footprint side in cells (Slime King 3, robot 2). */
  footprint: number;
  /** Ms per step when the boss walks toward the team between casts; 0 = stays put. */
  walkMs: number;
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
  skills: [...SLIME_SKILLS],
  bombDamage: 50,
  weakMultiplier: 1.5,
  minPlayers: 1,
  maxPlayers: 8,
  durationSeconds: 300,
  items: [...ITEMS],
  mount: true,
  footprint: 3,
  walkMs: 0,
};

/** Robot preset of the spec (event_config_example.json; numbers to playtest). */
export const ROBOT_RULES: Partial<BossRules> = {
  bossId: 'boss_clockwork_bot',
  assetPackId: 'clockwork_bot',
  name: 'Robot Bom Dây Cót',
  baseHp: 6000,
  hpPerExtraPlayer: 0.55,
  phaseThresholds: [0.7, 0.4],
  skills: [...ROBOT_SKILLS],
  bombDamage: 150,
  minPlayers: 1,
  maxPlayers: 6,
  durationSeconds: 360,
  footprint: 2,
  walkMs: 700,
};

/**
 * Telegraph (warning) time, cooldown and first phase per skill, in ms
 * (playtest numbers). Robot telegraph = cast + fuse of the spec table; the
 * mini chaser's is its last warning after the chase.
 */
export const SKILL_TIMING: Record<
  BossSkill,
  { telegraph: number; cooldown: number; phase: number }
> = {
  boss_basic_hit: { telegraph: 600, cooldown: 2500, phase: 1 },
  boss_aoe_mark: { telegraph: 1200, cooldown: 3500, phase: 1 },
  boss_block_lane: { telegraph: 1000, cooldown: 6000, phase: 2 },
  boss_wave_push: { telegraph: 1500, cooldown: 6000, phase: 2 },
  boss_weak_point: { telegraph: 400, cooldown: 9000, phase: 3 },
  robot_bomb_launch: { telegraph: 450 + 1500, cooldown: 6000, phase: 1 },
  robot_bomb_chain: { telegraph: 800 + 1600, cooldown: 12000, phase: 1 },
  robot_mini_chaser: { telegraph: 800, cooldown: 16000, phase: 2 },
  robot_recoil_dash: { telegraph: 900, cooldown: 14000, phase: 2 },
  robot_magnet_pull: { telegraph: 1200 + 1000, cooldown: 20000, phase: 3 },
  robot_overheat: { telegraph: 1600 + 1300, cooldown: 30000, phase: 3 },
  robot_reactor: { telegraph: 2000 + 1500, cooldown: 45000, phase: 3 },
};
/** Bomb Chain: the three bombs go off one after another. */
export const CHAIN_GAP = 400;
/** Overheat: the eight bombs go off one after another. */
export const OVERHEAT_GAP = 150;
/** Mini chaser: cast time, longest chase, ms per cell. */
export const CHASER_CAST = 600;
export const CHASE_MS = 3000;
export const CHASER_STEP_MS = 300;
/** Recoil dash: farthest dash, fuse of the bomb left on the start cells. */
export const DASH_CELLS = 4;
export const DASH_BOMB_MS = 1500;
/** Reactor: second wave after the first, then the robot is tired (weak). */
export const REACTOR_WAVE_GAP = 1000;
export const TIRED_MS = 2500;
/** Blast reach (cells) of the robot's bombs. */
export const ROBOT_RADIUS: Partial<Record<BossSkill, number>> = {
  robot_bomb_launch: 2,
  robot_bomb_chain: 2,
  robot_mini_chaser: 1,
  robot_recoil_dash: 2,
  robot_magnet_pull: 2,
  robot_overheat: 1,
};
/** Gap between two casts per phase; phase 3 casts faster. */
export const CAST_GAP = [1600, 1200, 800];
export const BLOCK_MS = 3000;
export const WEAK_MS = 3000;
export const PUSH_CELLS = 2;
/** Default boss footprint: 3 x 3 cells around the map centre (art can be larger). */
export const FOOTPRINT = 3;

type Dir = keyof typeof directions;
type Cell = [number, number];

export type RaidResult = 'WIN' | 'LOSE' | 'TIMEOUT' | 'ABORT';

export interface Cast {
  id: number;
  skill: BossSkill;
  /** Cells hit when it resolves (empty while the mini chaser runs). */
  tiles: [number, number][];
  castAt: number;
  resolveAt: number;
  /** wave push / recoil dash direction */
  dir?: keyof typeof directions;
  /** Robot bombs lying on the board for this hit (drawn by clients). */
  bombs?: [number, number][];
  /** Mini chaser: its cell, its target and when it starts / stops running. */
  mini?: [number, number];
  target?: string;
  chaseAt?: number;
  chaseUntil?: number;
  /** Recoil dash: footprint top-left after the dash. */
  to?: [number, number];
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
  /** Footprint side in cells (rules.footprint). */
  size = FOOTPRINT;
  facing: Dir = 'down';
  /** Server time of the boss's last walking step / dash (clients animate it). */
  movedAt = 0;
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
  private nextWalkAt = 0;
  private nextChaserStep = 0;
  private lastTarget = '';
  private targetStreak = 0;
  private rng: () => number;

  constructor(map: MapDef, rules: Partial<BossRules> = {}, seed = 1) {
    super(map);
    this.rules = { ...DEFAULT_RULES, ...rules };
    this.size = Math.min(3, Math.max(1, Math.round(this.rules.footprint)));
    this.minPlayers = Math.max(1, this.rules.minPlayers);
    this.roundMs = this.rules.durationSeconds * 1000;
    let state = seed >>> 0 || 1;
    this.rng = () => {
      state = (state * 1664525 + 1013904223) >>> 0;
      return state / 2 ** 32;
    };
    this.placeBoss();
  }

  /**
   * The footprint sits on the map centre, cleared of walls and crates. A
   * walking boss gets a factory floor: inner pillars are kept only on every
   * fourth cell (cover for raiders) so its footprint has lanes to walk and dash.
   */
  private placeBoss(): void {
    const width = this.grid[0]!.length;
    const height = this.grid.length;
    this.bossX = Math.floor((width - this.size) / 2);
    this.bossY = Math.floor((height - this.size) / 2);
    this.facing = 'down';
    this.movedAt = 0;
    if (this.rules.walkMs > 0)
      for (let y = 1; y < height - 1; y++)
        for (let x = 1; x < width - 1; x++)
          if (this.grid[y]![x] === Tile.Wall && (x % 4 !== 2 || y % 4 !== 2))
            this.grid[y]![x] = Tile.Floor;
    for (let y = this.bossY; y < this.bossY + this.size; y++)
      for (let x = this.bossX; x < this.bossX + this.size; x++)
        this.grid[y]![x] = Tile.Floor;
  }

  isBoss(x: number, y: number): boolean {
    return (
      x >= this.bossX &&
      x < this.bossX + this.size &&
      y >= this.bossY &&
      y < this.bossY + this.size
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
    this.nextWalkAt = this.now + 1500;
    this.lastTarget = '';
    this.targetStreak = 0;
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
    if (this.phase === 'playing') this.runChasers();
    for (const cast of [...this.casts])
      if (cast.resolveAt <= this.now) {
        this.casts = this.casts.filter((c) => c !== cast);
        this.resolve(cast);
      }
    if (this.phase === 'playing' && this.now >= this.nextCastAt) this.cast();
    if (this.phase === 'playing') this.walk();
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
    return this.rules.skills.filter(
      (s) =>
        SKILL_TIMING[s].phase <= this.bossPhase &&
        (this.readyAt.get(s) ?? 0) <= this.now,
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
      const casts = this.plan(skill);
      if (casts) {
        this.casts.push(...casts);
        this.castCount++;
        this.readyAt.set(skill, this.now + SKILL_TIMING[skill].cooldown);
        this.nextCastAt =
          Math.max(...casts.map((c) => c.resolveAt)) + this.gap();
        return;
      }
    }
    this.nextCastAt = this.now + 500;
  }

  private gap(): number {
    return CAST_GAP[Math.min(2, this.bossPhase - 1)]!;
  }

  private floor(x: number, y: number): boolean {
    return this.grid[y]?.[x] === Tile.Floor && !this.isBoss(x, y);
  }

  /** Floor cells around the footprint (basic hit). */
  ring(): [number, number][] {
    const out: [number, number][] = [];
    for (let y = this.bossY - 1; y <= this.bossY + this.size; y++)
      for (let x = this.bossX - 1; x <= this.bossX + this.size; x++)
        if (!this.isBoss(x, y) && this.floor(x, y)) out.push([x, y]);
    return out;
  }

  /** The telegraphs of `skill`, or null when they would leave someone no way out. */
  plan(skill: BossSkill): Cast[] | null {
    if (skill.startsWith('robot_')) return this.planRobot(skill);
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
        Math.floor(this.rng() * this.size);
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
            ? y >= this.bossY && y < this.bossY + this.size
            : x >= this.bossX && x < this.bossX + this.size;
          if (inBand && this.floor(x, y)) tiles.push([x, y]);
        }
    } else {
      for (let y = this.bossY; y < this.bossY + this.size; y++)
        for (let x = this.bossX; x < this.bossX + this.size; x++)
          tiles.push([x, y]);
    }
    if (!tiles.length) return null;
    const hurts = skill === 'boss_basic_hit' || skill === 'boss_aoe_mark';
    if (hurts && !alive.every((p) => this.canEscape(p, tiles, telegraph)))
      return null;
    if (skill === 'boss_block_lane' && !this.leavesRoom(tiles, alive))
      return null;
    return [
      {
        id: this.nextCast++,
        skill,
        tiles,
        castAt: this.now,
        resolveAt: this.now + telegraph,
        ...(dir ? { dir } : {}),
      },
    ];
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
    if (cast.skill.startsWith('robot_')) return this.resolveRobot(cast, cells);
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

  // ------------------------------------------------------------ robot (SK01-SK07)

  /** Cells a robot bomb on (x, y) hits: a + of `radius`, stopped by walls, crates and the boss. */
  blast(x: number, y: number, radius: number): Cell[] {
    const out: Cell[] = [[x, y]];
    for (const [dx, dy] of Object.values(directions))
      for (let d = 1; d <= radius; d++) {
        const nx = x + dx * d,
          ny = y + dy * d;
        if (!this.floor(nx, ny)) break;
        out.push([nx, ny]);
      }
    return out;
  }

  /** A free floor cell a bomb may land on (no boss, no bomb on it). */
  private landing(x: number, y: number): boolean {
    return (
      this.floor(x, y) &&
      ![...this.bombs.values()].some((b) => b.x === x && b.y === y)
    );
  }

  private centre(): [number, number] {
    const half = (this.size - 1) / 2;
    return [this.bossX + half, this.bossY + half];
  }

  /** Nearest raider, but not the same one more than twice in a row. */
  private pickTarget(): Player | null {
    const [cx, cy] = this.centre();
    const alive = [...this.players.values()]
      .filter((p) => p.alive)
      .sort(
        (a, b) =>
          Math.abs(a.x - cx) +
          Math.abs(a.y - cy) -
          (Math.abs(b.x - cx) + Math.abs(b.y - cy)),
      );
    let target = alive[0];
    if (!target) return null;
    if (target.id === this.lastTarget && this.targetStreak >= 2 && alive[1])
      target = alive[1];
    this.targetStreak =
      target.id === this.lastTarget ? this.targetStreak + 1 : 1;
    this.lastTarget = target.id;
    return target;
  }

  /** The way from the boss to (x, y) along the longer axis. */
  private dirTo(x: number, y: number): Dir {
    const [cx, cy] = this.centre();
    const dx = x - cx,
      dy = y - cy;
    if (Math.abs(dx) > Math.abs(dy)) return dx < 0 ? 'left' : 'right';
    return dy < 0 ? 'up' : 'down';
  }

  /**
   * The cell `distance` cells out of the footprint side facing `dir`, on lane
   * `lane` (0 .. size - 1, left-to-right / top-to-bottom).
   */
  private edge(dir: Dir, lane: number, distance: number): Cell {
    const [dx, dy] = directions[dir];
    if (dx)
      return [
        dx > 0 ? this.bossX + this.size - 1 + distance : this.bossX - distance,
        this.bossY + lane,
      ];
    return [
      this.bossX + lane,
      dy > 0 ? this.bossY + this.size - 1 + distance : this.bossY - distance,
    ];
  }

  /** The lane of the footprint nearest to (x, y) for a throw toward `dir`. */
  private laneTo(dir: Dir, x: number, y: number): number {
    const along =
      dir === 'left' || dir === 'right' ? y - this.bossY : x - this.bossX;
    return Math.min(this.size - 1, Math.max(0, along));
  }

  /** First valid landing cell, trying the distances in order (deterministic fallback). */
  private throwTo(dir: Dir, lane: number, distances: number[]): Cell | null {
    const lanes = [
      lane,
      ...[...Array(this.size).keys()].filter((l) => l !== lane),
    ];
    for (const l of lanes)
      for (const d of distances) {
        const [x, y] = this.edge(dir, l, d);
        if (this.landing(x, y)) return [x, y];
      }
    return null;
  }

  private bombCast(
    skill: BossSkill,
    bombs: Cell[],
    tiles: Cell[],
    resolveAt: number,
  ): Cast {
    return {
      id: this.nextCast++,
      skill,
      tiles,
      castAt: this.now,
      resolveAt,
      bombs,
    };
  }

  /** Every raider still standing reaches a cell outside all `casts` before the first goes off. */
  private fair(casts: Cast[]): boolean {
    const tiles = new Map<string, Cell>();
    for (const c of casts) for (const t of c.tiles) tiles.set(key(...t), t);
    const ms = Math.min(...casts.map((c) => c.resolveAt)) - this.now;
    return [...this.players.values()]
      .filter((p) => p.alive)
      .every((p) => this.canEscape(p, [...tiles.values()], ms));
  }

  private planRobot(skill: BossSkill): Cast[] | null {
    const target = this.pickTarget();
    if (!target) return null;
    const timing = SKILL_TIMING[skill];
    const radius = ROBOT_RADIUS[skill] ?? 1;
    const front = this.dirTo(target.x, target.y);
    this.facing = front;
    const at = this.now + timing.telegraph;
    let casts: Cast[] = [];
    if (skill === 'robot_bomb_launch') {
      // SK01: one bomb 1-2 cells in front, + of 2.
      const cell = this.throwTo(
        front,
        this.laneTo(front, target.x, target.y),
        [2, 1],
      );
      if (cell)
        casts = [this.bombCast(skill, [cell], this.blast(...cell, radius), at)];
    } else if (skill === 'robot_bomb_chain') {
      // SK02: front, left, right; they go off 0.4 s apart.
      const [left, right] = (
        front === 'up' || front === 'down' ? ['left', 'right'] : ['up', 'down']
      ) as [Dir, Dir];
      const lanes = [this.laneTo(front, target.x, target.y), 0, this.size - 1];
      [front, left, right].forEach((dir, i) => {
        const cell = this.throwTo(dir, lanes[i]!, [2, 1, 3]);
        if (cell)
          casts.push(
            this.bombCast(
              skill,
              [cell],
              this.blast(...cell, radius),
              at + casts.length * CHAIN_GAP,
            ),
          );
      });
    } else if (skill === 'robot_mini_chaser') {
      // SK03: a mini bomb hops out and runs after the target; tiles come when it stops.
      const cell = this.throwTo(front, this.laneTo(front, target.x, target.y), [
        1,
      ]);
      if (!cell || !this.isWalkable(...cell)) return null;
      const chaseAt = this.now + CHASER_CAST;
      return [
        {
          id: this.nextCast++,
          skill,
          tiles: [],
          castAt: this.now,
          resolveAt: chaseAt + CHASE_MS + timing.telegraph,
          mini: cell,
          target: target.id,
          chaseAt,
          chaseUntil: chaseAt + CHASE_MS,
        },
      ];
    } else if (skill === 'robot_recoil_dash') {
      return this.planDash(front, at);
    } else if (skill === 'robot_magnet_pull') {
      // SK05: pulls its bombs onto its back, then a + reaching 2 cells out of each side.
      const seen = new Map<string, Cell>();
      for (const dir of Object.keys(directions) as Dir[])
        for (let lane = 0; lane < this.size; lane++) {
          const [sx, sy] = this.edge(dir, lane, 0);
          for (const t of this.blast(sx, sy, radius).slice(1))
            if (!this.isBoss(...t)) seen.set(key(...t), t);
        }
      const tiles = [...seen.values()].filter(([x, y]) => {
        // Only cells straight out of a side (the + of the footprint).
        const inCols = x >= this.bossX && x < this.bossX + this.size;
        const inRows = y >= this.bossY && y < this.bossY + this.size;
        return inCols || inRows;
      });
      if (tiles.length) casts = [this.bombCast(skill, [], tiles, at)];
    } else if (skill === 'robot_overheat') {
      // SK06: eight bombs around the robot, one after another.
      const mid = Math.floor((this.size - 1) / 2);
      const far = this.size + 1;
      const spots: [number, number, number, number][] = [
        // start cell relative to bossX/bossY, then the outward step
        [mid, -2, 0, -1],
        [far, -2, 1, -1],
        [far, mid, 1, 0],
        [far, far, 1, 1],
        [mid, far, 0, 1],
        [-2, far, -1, 1],
        [-2, mid, -1, 0],
        [-2, -2, -1, -1],
      ];
      for (const [ox, oy, sx, sy] of spots)
        for (const extra of [0, 1, -1]) {
          const x = this.bossX + ox + sx * extra,
            y = this.bossY + oy + sy * extra;
          if (this.landing(x, y)) {
            casts.push(
              this.bombCast(
                skill,
                [[x, y]],
                this.blast(x, y, radius),
                at + casts.length * OVERHEAT_GAP,
              ),
            );
            break;
          }
        }
    } else if (skill === 'robot_reactor') {
      return this.planReactor(at);
    }
    if (!casts.length || !this.fair(casts)) return null;
    return casts;
  }

  /** Cells the footprint newly covers when it slides `distance` cells toward `dir`. */
  private swept(dir: Dir, distance: number): Cell[] {
    const [dx, dy] = directions[dir];
    const out = new Map<string, Cell>();
    for (let d = 1; d <= distance; d++)
      for (let i = 0; i < this.size; i++)
        for (let j = 0; j < this.size; j++) {
          const x = this.bossX + i + dx * d,
            y = this.bossY + j + dy * d;
          if (!this.isBoss(x, y)) out.set(key(x, y), [x, y]);
        }
    return [...out.values()];
  }

  /** How far (0 .. max) the footprint can slide toward `dir`: floor without bombs. */
  private reach(dir: Dir, max: number): number {
    for (let d = 1; d <= max; d++)
      for (let lane = 0; lane < this.size; lane++) {
        const [x, y] = this.edge(dir, lane, d);
        if (!this.landing(x, y)) return d - 1;
      }
    return max;
  }

  /** SK04: the robot dashes up to 4 cells along a lane, warned 0.9 s ahead. */
  private planDash(front: Dir, at: number): Cast[] | null {
    const order = [
      front,
      ...(Object.keys(directions) as Dir[]).filter((d) => d !== front),
    ];
    for (const dir of order) {
      const distance = this.reach(dir, DASH_CELLS);
      if (distance < 2) continue;
      const tiles = this.swept(dir, distance);
      const [dx, dy] = directions[dir];
      const cast: Cast = {
        id: this.nextCast++,
        skill: 'robot_recoil_dash',
        tiles,
        castAt: this.now,
        resolveAt: at,
        dir,
        to: [this.bossX + dx * distance, this.bossY + dy * distance],
      };
      if (this.fair([cast])) {
        this.facing = dir;
        return [cast];
      }
      this.nextCast--;
    }
    return null;
  }

  /** SK07: bombs on every third row, then every third column; never the whole board. */
  private planReactor(at: number): Cast[] | null {
    const height = this.grid.length;
    const width = this.grid[0]!.length;
    const offsets: [number, number][] = [];
    for (let r = 0; r < 3; r++)
      for (let c = 0; c < 3; c++) offsets.push([r, c]);
    offsets.sort(() => this.rng() - 0.5);
    for (const [r, c] of offsets) {
      const rows: Cell[] = [];
      const cols: Cell[] = [];
      for (let y = 0; y < height; y++)
        for (let x = 0; x < width; x++) {
          if (!this.floor(x, y)) continue;
          if ((y + r) % 3 === 0) rows.push([x, y]);
          if ((x + c) % 3 === 0) cols.push([x, y]);
        }
      if (!rows.length || !cols.length) continue;
      const spread = (cells: Cell[]) =>
        cells.filter(([x, y]) => (x + y) % 2 === 0 && this.landing(x, y));
      const waves = [
        this.bombCast('robot_reactor', spread(rows), rows, at),
        this.bombCast(
          'robot_reactor',
          spread(cols),
          cols,
          at + REACTOR_WAVE_GAP,
        ),
      ];
      if (this.fair(waves)) return waves;
      this.nextCast -= 2;
    }
    return null;
  }

  /** Mini chasers move one cell per CHASER_STEP_MS, then stop and warn. */
  private runChasers(): void {
    for (const cast of this.casts) {
      if (cast.skill !== 'robot_mini_chaser' || cast.tiles.length || !cast.mini)
        continue;
      if (this.now < (cast.chaseAt ?? 0)) continue;
      let target = this.players.get(cast.target ?? '');
      if (!target?.alive) {
        // The target is out or gone: chase the nearest raider still standing.
        const [mx, my] = cast.mini;
        target = [...this.players.values()]
          .filter((p) => p.alive)
          .sort(
            (a, b) =>
              Math.abs(a.x - mx) +
              Math.abs(a.y - my) -
              (Math.abs(b.x - mx) + Math.abs(b.y - my)),
          )[0];
        cast.target = target?.id;
      }
      const close =
        !target ||
        Math.abs(target.x - cast.mini[0]) + Math.abs(target.y - cast.mini[1]) <=
          1;
      if (close || this.now >= (cast.chaseUntil ?? 0)) {
        this.arm(cast);
        continue;
      }
      if (this.now < this.nextChaserStep) continue;
      this.nextChaserStep = this.now + CHASER_STEP_MS;
      const next = this.stepToward(cast.mini, [target!.x, target!.y]);
      if (next) cast.mini = next;
    }
    // A chaser that could not stop fairly fizzles out.
    this.casts = this.casts.filter(
      (c) => c.skill !== 'robot_mini_chaser' || c.mini !== undefined,
    );
  }

  /** The chaser stops: a + of 1 warned 0.8 s (only its cell, or nothing, if that is unfair). */
  private arm(cast: Cast): void {
    const [x, y] = cast.mini!;
    cast.resolveAt = this.now + SKILL_TIMING.robot_mini_chaser.telegraph;
    cast.bombs = [[x, y]];
    for (const tiles of [this.blast(x, y, 1), [[x, y]] as Cell[]]) {
      cast.tiles = tiles;
      if (this.fair([cast])) return;
    }
    delete cast.mini;
  }

  /** First step of a shortest walk on the grid (no walls, crates, bombs or boss). */
  private stepToward(from: Cell, to: Cell): Cell | null {
    const goal = key(...to);
    const back = new Map<string, string>([[key(...from), '']]);
    const todo: Cell[] = [from];
    while (todo.length) {
      const [x, y] = todo.shift()!;
      const k = key(x, y);
      if (k === goal) {
        let cur = k;
        while (back.get(cur) !== key(...from)) cur = back.get(cur)!;
        return cur.split(',').map(Number) as Cell;
      }
      for (const [dx, dy] of Object.values(directions)) {
        const nx = x + dx,
          ny = y + dy;
        const nk = key(nx, ny);
        if (!back.has(nk) && (nk === goal || this.isWalkable(nx, ny))) {
          back.set(nk, k);
          todo.push([nx, ny]);
        }
      }
    }
    return null;
  }

  private resolveRobot(cast: Cast, cells: Set<string>): void {
    if (cast.skill === 'robot_recoil_dash' && cast.to) return this.dash(cast);
    for (const p of this.players.values())
      if (p.alive && cells.has(key(p.x, p.y))) this.hurt(p);
    for (const [x, y] of cast.tiles) this.ignite(x, y, 'boss');
    // The reactor's last wave leaves the robot tired: weak point for 2.5 s.
    if (
      cast.skill === 'robot_reactor' &&
      !this.casts.some((c) => c.skill === 'robot_reactor')
    )
      this.weakUntil = this.now + TIRED_MS;
  }

  /** SK04 lands: hits the lane it sweeps, moves, and leaves a bomb on its start cells. */
  private dash(cast: Cast): void {
    const dir = cast.dir ?? this.facing;
    const [dx, dy] = directions[dir];
    const planned =
      Math.abs(cast.to![0] - this.bossX) + Math.abs(cast.to![1] - this.bossY);
    // Bombs placed during the warning shorten the dash.
    const distance = this.reach(dir, planned);
    if (!distance) return;
    const hit = new Set(this.swept(dir, distance).map((c) => key(...c)));
    for (const p of this.players.values())
      if (p.alive && hit.has(key(p.x, p.y))) this.hurt(p);
    const [oldX, oldY] = [this.bossX, this.bossY];
    this.bossX += dx * distance;
    this.bossY += dy * distance;
    this.facing = dir;
    this.movedAt = this.now;
    this.evict();
    // The bomb stays on the back cell of where the robot stood.
    const mid = Math.floor((this.size - 1) / 2);
    const bomb: Cell = dx
      ? [dx > 0 ? oldX : oldX + this.size - 1, oldY + mid]
      : [oldX + mid, dy > 0 ? oldY : oldY + this.size - 1];
    if (!this.landing(...bomb)) return;
    const at = this.now + DASH_BOMB_MS;
    for (const radius of [ROBOT_RADIUS.robot_recoil_dash ?? 2, 1, 0]) {
      const follow = this.bombCast(
        'robot_recoil_dash',
        [bomb],
        this.blast(...bomb, radius),
        at,
      );
      if (this.fair([follow])) {
        this.casts.push(follow);
        this.nextCastAt = Math.max(this.nextCastAt, at + this.gap());
        return;
      }
      this.nextCast--;
    }
  }

  /** Shielded raiders the robot ran over are put on the nearest free cell. */
  private evict(): void {
    for (const p of this.players.values()) {
      if (!p.alive || !this.isBoss(p.x, p.y)) continue;
      const seen = new Set([key(p.x, p.y)]);
      const todo: Cell[] = [[p.x, p.y]];
      while (todo.length) {
        const [x, y] = todo.shift()!;
        const taken = [...this.players.values()].some(
          (o) => o !== p && o.alive && o.x === x && o.y === y,
        );
        if (!this.isBoss(x, y) && this.isWalkable(x, y) && !taken) {
          [p.x, p.y] = [x, y];
          break;
        }
        for (const [ddx, ddy] of Object.values(directions)) {
          const nx = x + ddx,
            ny = y + ddy;
          if (!seen.has(key(nx, ny)) && this.grid[ny]?.[nx] !== undefined) {
            seen.add(key(nx, ny));
            todo.push([nx, ny]);
          }
        }
      }
    }
  }

  /** The footprint fits with its top-left on (x, y): floor, no bomb, no raider. */
  private fits(x: number, y: number): boolean {
    for (let j = 0; j < this.size; j++)
      for (let i = 0; i < this.size; i++) {
        const cx = x + i,
          cy = y + j;
        if (this.isBoss(cx, cy)) continue;
        if (
          !this.landing(cx, cy) ||
          [...this.players.values()].some(
            (p) => p.alive && p.x === cx && p.y === cy,
          )
        )
          return false;
      }
    return true;
  }

  /** Cells between the footprint at (x, y) and `p` (0 = touching or under it). */
  private gapTo(x: number, y: number, p: Player): number {
    const gx = Math.max(x - p.x, p.x - (x + this.size - 1), 0);
    const gy = Math.max(y - p.y, p.y - (y + this.size - 1), 0);
    return gx + gy;
  }

  /**
   * Between casts a walking boss (walkMs > 0) takes one step of a shortest
   * footprint path toward the nearest raider, until it is 2 cells from them.
   */
  private walk(): void {
    if (!this.rules.walkMs || this.casts.length || this.now < this.nextWalkAt)
      return;
    this.nextWalkAt = this.now + this.rules.walkMs;
    const [cx, cy] = this.centre();
    const target = [...this.players.values()]
      .filter((p) => p.alive)
      .sort(
        (a, b) =>
          Math.abs(a.x - cx) +
          Math.abs(a.y - cy) -
          (Math.abs(b.x - cx) + Math.abs(b.y - cy)),
      )[0];
    if (!target || this.gapTo(this.bossX, this.bossY, target) <= 2) return;
    const start = key(this.bossX, this.bossY);
    const first = new Map<string, Dir | null>([[start, null]]);
    const todo: Cell[] = [[this.bossX, this.bossY]];
    // Prefer the step along the longer axis toward the target.
    const order = [
      this.dirTo(target.x, target.y),
      ...(Object.keys(directions) as Dir[]),
    ];
    // Crates may wall the target off: then head for the closest reachable spot.
    let best: Dir | null = null;
    let bestGap = this.gapTo(this.bossX, this.bossY, target);
    while (todo.length) {
      const [x, y] = todo.shift()!;
      const via = first.get(key(x, y))!;
      const gap = this.gapTo(x, y, target);
      if (via && gap < bestGap) {
        best = via;
        bestGap = gap;
        if (gap <= 2) break;
      }
      for (const dir of order) {
        const [dx, dy] = directions[dir];
        const nx = x + dx,
          ny = y + dy;
        if (first.has(key(nx, ny)) || !this.fits(nx, ny)) continue;
        first.set(key(nx, ny), via ?? dir);
        todo.push([nx, ny]);
      }
    }
    if (!best) return;
    const [dx, dy] = directions[best];
    this.bossX += dx;
    this.bossY += dy;
    this.facing = best;
    this.movedAt = this.now;
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
        size: this.size,
        facing: this.facing,
        movedAt: this.movedAt,
        walkMs: this.rules.walkMs,
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
          ...(c.bombs ? { bombs: c.bombs } : {}),
          ...(c.mini ? { mini: c.mini } : {}),
          ...(c.to ? { to: c.to } : {}),
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
