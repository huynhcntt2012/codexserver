import { type Client, ServerError } from '@colyseus/core';
import {
  BOSS_SKILLS,
  BossArena,
  DEFAULT_RULES,
  type BossRules,
  type BossSkill,
  type RaidSummary,
} from './boss.js';
import { ITEMS, type Arena, type ItemId } from './game.js';
import { ArenaRoomV2 } from './room.js';
import { fetchBossEvent, processId, report } from './ingest.js';
import type { MapDef } from './maps.js';

/** Seconds a dropped raider keeps their seat (spec: reconnect window). */
export const RECONNECT_SECONDS = 30;
/** How often the room re-reads the event (paused / ended / out of session). */
export const REFRESH_MS = 15_000;

const number = (value: unknown, min: number, max: number, fallback: number) =>
  typeof value === 'number' && Number.isFinite(value)
    ? Math.min(max, Math.max(min, value))
    : fallback;

/** API rules (snake_case, already validated by the API) -> simulation rules. */
export function parseRules(
  eventId: string,
  raw: Record<string, unknown>,
): BossRules {
  const d = DEFAULT_RULES;
  const thresholds = Array.isArray(raw.phase_thresholds)
    ? raw.phase_thresholds
        .filter((t): t is number => typeof t === 'number' && t > 0 && t < 1)
        .sort((a, b) => b - a)
        .slice(0, 4)
    : d.phaseThresholds;
  const skills = Array.isArray(raw.skills)
    ? raw.skills.filter((s): s is BossSkill =>
        (BOSS_SKILLS as readonly string[]).includes(s as string),
      )
    : d.skills;
  const max = Math.round(number(raw.max_players, 1, 8, d.maxPlayers));
  return {
    eventId,
    bossId: typeof raw.boss_id === 'string' ? raw.boss_id : d.bossId,
    assetPackId:
      typeof raw.asset_pack_id === 'string' ? raw.asset_pack_id : d.assetPackId,
    name: typeof raw.display_name === 'string' ? raw.display_name : d.name,
    mapId: typeof raw.map_id === 'string' ? raw.map_id : d.mapId,
    baseHp: Math.round(number(raw.base_hp, 50, 1_000_000, d.baseHp)),
    hpPerExtraPlayer: number(raw.hp_per_extra_player, 0, 5, d.hpPerExtraPlayer),
    phaseThresholds: thresholds,
    skills: skills.length ? skills : d.skills,
    bombDamage: Math.round(number(raw.bomb_damage, 1, 10_000, d.bombDamage)),
    weakMultiplier: number(raw.weak_multiplier, 1, 5, d.weakMultiplier),
    minPlayers: Math.min(
      max,
      Math.round(number(raw.min_players, 1, 8, d.minPlayers)),
    ),
    maxPlayers: max,
    durationSeconds: Math.round(
      number(raw.duration_seconds, 30, 1800, d.durationSeconds),
    ),
    items: Array.isArray(raw.items)
      ? raw.items.filter((i): i is ItemId =>
          (ITEMS as readonly string[]).includes(i as string),
        )
      : d.items,
    mount: typeof raw.mount === 'boolean' ? raw.mount : d.mount,
    footprint: Math.round(number(raw.footprint, 2, 3, d.footprint)),
    walkMs: Math.round(number(raw.walk_ms, 0, 5000, d.walkMs)),
    rescueMs: Math.round(number(raw.rescue_ms, 0, 10_000, d.rescueMs)),
    hpFormula: raw.hp_formula === 'team' ? 'team' : 'per_extra',
  };
}

/**
 * A boss raid room (`boss`): joinOrCreate/boss { event } for public team-up,
 * create/boss { event, private: true } for a private room (no economy rewards
 * unless the event allows it). Rules come from the API, never from the client.
 */
export class BossRoom extends ArenaRoomV2 {
  declare game: BossArena;
  rules: BossRules = DEFAULT_RULES;
  privateRaid = false;
  private seed = 1;

  override async onCreate(options?: {
    map?: unknown;
    practice?: unknown;
    event?: unknown;
    private?: unknown;
  }): Promise<void> {
    const eventId = typeof options?.event === 'string' ? options.event : '';
    if (!/^[A-Za-z0-9_-]{1,40}$/.test(eventId))
      throw new ServerError(400, 'Unknown boss event');
    const info = await fetchBossEvent(eventId);
    if (!info) throw new ServerError(404, 'Boss event not available');
    if (!info.open) throw new ServerError(403, 'Boss event is not open');
    this.rules = parseRules(eventId, info.rules);
    this.seed = (Date.now() ^ (Math.random() * 2 ** 31)) >>> 0;
    await super.onCreate({ map: this.rules.mapId });
    this.maxClients = this.rules.maxPlayers;
    this.game.open = info.open;
    this.game.matchPrefix = `${processId}.${this.roomId}`;
    if (options?.private === true) {
      this.privateRaid = true;
      this.game.privateRaid = true;
      void this.setPrivate(true);
    }
    void this.setMetadata({
      event: eventId,
      number: this.number,
      map: this.rules.mapId,
    });
    this.game.onRaidEnd = (summary) => this.reportRaid(summary);
    // Paused / ended events start no new raid; a running raid is played out.
    this.clock.setInterval(() => {
      void fetchBossEvent(eventId).then((fresh) => {
        if (fresh) this.game.open = fresh.open;
      });
    }, REFRESH_MS);
  }

  protected override makeGame(map: MapDef): Arena {
    return new BossArena(map, this.rules, this.seed);
  }

  /** Boss rounds are not PvP matches: they are reported as boss_raid instead. */
  protected override reportRound(): void {}

  /** A dropped raider keeps the seat for a while during a raid. */
  async onDrop(client: Client) {
    if (this.game.phase !== 'playing') return;
    try {
      await this.allowReconnection(client, RECONNECT_SECONDS);
      client.sendBytes(1, this.snapshotBytes());
    } catch {
      // Not back in time: onLeave removes the player.
    }
  }

  private reportRaid(summary: RaidSummary) {
    const raiders = summary.players.flatMap((p) => {
      const account = this.accounts.get(p.id);
      return account
        ? [
            {
              account_id: account.accountId,
              name: p.name,
              damage: p.damage,
              support: p.support,
              actions: p.actions,
              active_ms: p.activeMs,
              alive: p.alive,
              rescues: p.rescues,
              phases: p.phases,
            },
          ]
        : [];
    });
    report({
      type: 'boss_raid',
      room_id: this.roomId,
      event_id: this.rules.eventId,
      match_id: `${this.game.matchPrefix}.${summary.round}`,
      result: summary.result,
      boss_id: this.rules.bossId,
      boss_hp_max: summary.hpMax,
      boss_hp_left: summary.hpLeft,
      duration_ms: summary.durationMs,
      map_id: this.rules.mapId,
      private: this.privateRaid,
      raiders,
      team_size: summary.players.length,
    });
  }

  override onDispose() {
    // A room closing mid-raid (shutdown) ends it as ABORT: no reward, no quota.
    if (this.game.phase === 'playing') {
      this.game.raidResult = 'ABORT';
      this.reportRaid({ ...this.game.summary(), result: 'ABORT' });
    }
    super.onDispose();
  }
}
