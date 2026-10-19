import { useState } from 'react';
import { Card, Field, Modal, Stat } from '@/components/ui';
import { newReward, Reward, REWARD } from '@/components/QuestEditor';
import { api } from '@/lib/api';
import { dateTime } from '@/lib/format';

// Boss raid block of an event (docs/BOSS.md, apps/api/app/liveops.py BossRules).

export const SKILLS: Record<string, string> = {
  boss_basic_hit: 'Đánh thường (ô quanh Boss, báo 0,6 s)',
  boss_aoe_mark: 'Đánh dấu vùng (3×3 / 5×5, báo 1,2 s)',
  boss_block_lane: 'Chặn ô (vật cản 3 s, báo 1 s)',
  boss_wave_push: 'Sóng đẩy (đẩy người/bom 2 ô, báo 1,5 s)',
  boss_weak_point: 'Lộ điểm yếu (×1,5 sát thương 3 s, phase 3)',
};

export const ITEMS: Record<string, string> = {
  throw_bomb: 'Bom ném xa',
  dart: 'Phi tiêu',
  blue_shield: 'Khiên xanh',
  speed_shoes: 'Giày tốc độ',
  freeze_bomb: 'Bom đóng băng',
  push_glove: 'Găng đẩy',
};

const DAYS = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

export type BossSession = {
  days_of_week: number[];
  local_start: string;
  local_end: string;
};

export type BossConfig = {
  boss_id: string;
  asset_pack_id: string;
  display_name: string;
  map_id: string;
  difficulty: 'EASY' | 'NORMAL' | 'HARD';
  base_hp: number;
  hp_per_extra_player: number;
  phase_thresholds: number[];
  skills: string[];
  bomb_damage: number;
  weak_multiplier: number;
  min_players: number;
  max_players: number;
  duration_seconds: number;
  items: string[];
  mount: boolean;
  reward_private_room: boolean;
  sessions: BossSession[];
  eligibility: {
    min_active_seconds: number;
    min_active_fraction: number;
    min_damage_fraction: number;
    support_actions: number;
    min_actions: number;
  };
  full_reward_limit_per_day: number;
  win_rewards: Reward[];
  lose_rewards: Reward[];
};

/** Spec sample numbers (to be balanced after playtests). */
export function defaultBoss(): BossConfig {
  return {
    boss_id: 'boss_001',
    asset_pack_id: 'boss_001_placeholder',
    display_name: 'Boss Sự Kiện',
    map_id: 'harbor',
    difficulty: 'NORMAL',
    base_hp: 1000,
    hp_per_extra_player: 0.55,
    phase_thresholds: [0.7, 0.35],
    skills: Object.keys(SKILLS),
    bomb_damage: 50,
    weak_multiplier: 1.5,
    min_players: 1,
    max_players: 8,
    duration_seconds: 300,
    items: Object.keys(ITEMS),
    mount: true,
    reward_private_room: false,
    sessions: [],
    eligibility: {
      min_active_seconds: 45,
      min_active_fraction: 0.5,
      min_damage_fraction: 0.01,
      support_actions: 3,
      min_actions: 10,
    },
    full_reward_limit_per_day: 3,
    win_rewards: [
      { type: 'gold', amount: 150, item_id: null },
      { type: 'token', amount: 30, item_id: null },
    ],
    lose_rewards: [{ type: 'gold', amount: 20, item_id: null }],
  };
}

export function fullBoss(boss: Partial<BossConfig> | null | undefined) {
  if (!boss) return null;
  const d = defaultBoss();
  return {
    ...d,
    ...boss,
    eligibility: { ...d.eligibility, ...(boss.eligibility ?? {}) },
    sessions: boss.sessions ?? [],
    win_rewards: (boss.win_rewards ?? d.win_rewards).map((r) => ({
      ...newReward(),
      ...r,
      item_id: r.item_id ?? null,
    })),
    lose_rewards: (boss.lose_rewards ?? d.lose_rewards).map((r) => ({
      ...newReward(),
      ...r,
      item_id: r.item_id ?? null,
    })),
  };
}

function hp(boss: BossConfig, n: number) {
  return Math.round(boss.base_hp * (1 + boss.hp_per_extra_player * (n - 1)));
}

function Rewards({
  value,
  items,
  token,
  onChange,
}: {
  value: Reward[];
  items: { id: string; name: string }[];
  token: string;
  onChange: (next: Reward[]) => void;
}) {
  const set = (i: number, patch: Partial<Reward>) =>
    onChange(value.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  return (
    <div className="stack">
      {value.map((r, i) => (
        <div className="toolbar" key={i}>
          <select
            className="input"
            aria-label="Loại thưởng"
            value={r.type}
            onChange={(e) =>
              set(i, {
                type: e.target.value as Reward['type'],
                item_id:
                  e.target.value === 'item' ? (items[0]?.id ?? null) : null,
              })
            }
          >
            {Object.entries(REWARD).map(([key, label]) => (
              <option key={key} value={key}>
                {key === 'token' ? token : label}
              </option>
            ))}
          </select>
          {r.type === 'item' && (
            <select
              className="input grow"
              aria-label="Vật phẩm"
              value={r.item_id ?? ''}
              onChange={(e) => set(i, { item_id: e.target.value })}
            >
              {items.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name} ({item.id})
                </option>
              ))}
            </select>
          )}
          <input
            className="input small"
            type="number"
            min={1}
            aria-label="Số lượng"
            value={r.amount}
            onChange={(e) => set(i, { amount: Number(e.target.value) })}
          />
          <button
            className="btn small ghost"
            onClick={() => onChange(value.filter((_, j) => j !== i))}
          >
            Xóa
          </button>
        </div>
      ))}
      {value.length < 5 && (
        <button
          className="btn small secondary"
          onClick={() => onChange([...value, newReward()])}
        >
          + Thưởng
        </button>
      )}
    </div>
  );
}

/** Step "Boss" of the event builder: rules the arena enforces + raid rewards. */
export default function BossEditor({
  boss,
  token,
  mapIds,
  items,
  onChange,
}: {
  boss: BossConfig | null;
  token: string;
  mapIds: string[];
  items: { id: string; name: string }[];
  onChange: (next: BossConfig | null) => void;
}) {
  if (!boss)
    return (
      <div className="stack">
        <p className="spark">
          Sự kiện này chưa có Boss. Thêm Boss để mở chế độ Đại Chiến Boss (PvE
          1-8 người): app hiện nút SĂN BOSS khi sự kiện đang chạy.
        </p>
        <button className="btn" onClick={() => onChange(defaultBoss())}>
          + Thêm Boss (thông số mẫu)
        </button>
      </div>
    );
  const set = (patch: Partial<BossConfig>) => onChange({ ...boss, ...patch });
  const num = (key: keyof BossConfig) => (e: { target: { value: string } }) =>
    set({ [key]: Number(e.target.value) } as Partial<BossConfig>);
  const eligibility = (patch: Partial<BossConfig['eligibility']>) =>
    set({ eligibility: { ...boss.eligibility, ...patch } });
  const toggle = (list: string[], value: string) =>
    list.includes(value) ? list.filter((v) => v !== value) : [...list, value];
  return (
    <div className="stack">
      <Card title="Boss & bản đồ">
        <div className="form cols">
          <Field label="Tên hiển thị" hint="Tên chính thức chờ duyệt art">
            <input
              className="input"
              value={boss.display_name}
              onChange={(e) => set({ display_name: e.target.value })}
            />
          </Field>
          <Field label="Boss ID">
            <input
              className="input"
              value={boss.boss_id}
              onChange={(e) => set({ boss_id: e.target.value })}
            />
          </Field>
          <Field
            label="Asset pack ID"
            hint="Đổi art chỉ cần đổi pack, không đổi luật"
          >
            <input
              className="input"
              value={boss.asset_pack_id}
              onChange={(e) => set({ asset_pack_id: e.target.value })}
            />
          </Field>
          <Field label="Bản đồ">
            <input
              className="input"
              list="boss-map-ids"
              value={boss.map_id}
              onChange={(e) => set({ map_id: e.target.value })}
            />
            <datalist id="boss-map-ids">
              {mapIds.map((id) => (
                <option key={id} value={id} />
              ))}
            </datalist>
          </Field>
          <Field label="Độ khó (nhãn)">
            <select
              className="input"
              value={boss.difficulty}
              onChange={(e) =>
                set({ difficulty: e.target.value as BossConfig['difficulty'] })
              }
            >
              <option value="EASY">Dễ</option>
              <option value="NORMAL">Thường</option>
              <option value="HARD">Khó</option>
            </select>
          </Field>
          <Field label="Thời gian trận (giây)">
            <input
              className="input"
              type="number"
              min={30}
              max={1800}
              value={boss.duration_seconds}
              onChange={num('duration_seconds')}
            />
          </Field>
          <Field label="Số người tối thiểu">
            <input
              className="input"
              type="number"
              min={1}
              max={8}
              value={boss.min_players}
              onChange={num('min_players')}
            />
          </Field>
          <Field label="Số người tối đa (≤ 8)">
            <input
              className="input"
              type="number"
              min={1}
              max={8}
              value={boss.max_players}
              onChange={num('max_players')}
            />
          </Field>
        </div>
      </Card>

      <Card title="HP, sát thương & phase">
        <div className="form cols">
          <Field label="HP cơ sở (1 người)">
            <input
              className="input"
              type="number"
              min={50}
              value={boss.base_hp}
              onChange={num('base_hp')}
            />
          </Field>
          <Field
            label="Hệ số HP mỗi người thêm"
            hint={`1 người ${hp(boss, 1)} HP · 8 người ${hp(boss, 8)} HP`}
          >
            <input
              className="input"
              type="number"
              step={0.05}
              min={0}
              value={boss.hp_per_extra_player}
              onChange={num('hp_per_extra_player')}
            />
          </Field>
          <Field label="Sát thương mỗi quả bom trúng Boss">
            <input
              className="input"
              type="number"
              min={1}
              value={boss.bomb_damage}
              onChange={num('bomb_damage')}
            />
          </Field>
          <Field label="Hệ số khi lộ điểm yếu">
            <input
              className="input"
              type="number"
              step={0.1}
              min={1}
              value={boss.weak_multiplier}
              onChange={num('weak_multiplier')}
            />
          </Field>
          <Field
            label="Ngưỡng phase (HP còn lại, giảm dần)"
            hint="Ví dụ 0.70, 0.35 → 3 phase"
            full
          >
            <input
              className="input"
              value={boss.phase_thresholds.join(', ')}
              onChange={(e) =>
                set({
                  phase_thresholds: e.target.value
                    .split(',')
                    .map((v) => Number(v.trim()))
                    .filter((v) => !Number.isNaN(v) && v > 0),
                })
              }
            />
          </Field>
        </div>
      </Card>

      <Card title="Kỹ năng Boss (ô cảnh báo do server quyết định)">
        <div className="stack">
          {Object.entries(SKILLS).map(([key, label]) => (
            <label className="check" key={key}>
              <input
                type="checkbox"
                checked={boss.skills.includes(key)}
                onChange={() => set({ skills: toggle(boss.skills, key) })}
              />
              {label}
            </label>
          ))}
        </div>
      </Card>

      <Card title="Vật phẩm cho phép trong trận">
        <div className="toolbar">
          {Object.entries(ITEMS).map(([key, label]) => (
            <label className="check" key={key}>
              <input
                type="checkbox"
                checked={boss.items.includes(key)}
                onChange={() => set({ items: toggle(boss.items, key) })}
              />
              {label}
            </label>
          ))}
          <label className="check">
            <input
              type="checkbox"
              checked={boss.mount}
              onChange={(e) => set({ mount: e.target.checked })}
            />
            Thú cưỡi (Q)
          </label>
        </div>
      </Card>

      <Card title="Phiên chơi (giờ Việt Nam)">
        <p className="spark">
          Để trống = chơi suốt thời gian sự kiện. Ngoài phiên không mở trận mới;
          trận đang chơi được đánh tiếp.
        </p>
        {boss.sessions.map((s, i) => (
          <div className="toolbar" key={i}>
            {DAYS.map((label, d) => (
              <label className="check" key={label}>
                <input
                  type="checkbox"
                  checked={s.days_of_week.includes(d + 1)}
                  onChange={() =>
                    set({
                      sessions: boss.sessions.map((x, j) =>
                        j === i
                          ? {
                              ...x,
                              days_of_week: x.days_of_week.includes(d + 1)
                                ? x.days_of_week.filter((v) => v !== d + 1)
                                : [...x.days_of_week, d + 1].sort(),
                            }
                          : x,
                      ),
                    })
                  }
                />
                {label}
              </label>
            ))}
            <input
              className="input small"
              aria-label="Bắt đầu"
              value={s.local_start}
              onChange={(e) =>
                set({
                  sessions: boss.sessions.map((x, j) =>
                    j === i ? { ...x, local_start: e.target.value } : x,
                  ),
                })
              }
            />
            <input
              className="input small"
              aria-label="Kết thúc"
              value={s.local_end}
              onChange={(e) =>
                set({
                  sessions: boss.sessions.map((x, j) =>
                    j === i ? { ...x, local_end: e.target.value } : x,
                  ),
                })
              }
            />
            <button
              className="btn small ghost"
              onClick={() =>
                set({ sessions: boss.sessions.filter((_, j) => j !== i) })
              }
            >
              Xóa
            </button>
          </div>
        ))}
        <button
          className="btn small secondary"
          onClick={() =>
            set({
              sessions: [
                ...boss.sessions,
                {
                  days_of_week: [1, 2, 3, 4, 5, 6, 7],
                  local_start: '19:00',
                  local_end: '22:00',
                },
              ],
            })
          }
        >
          + Phiên 19:00-22:00
        </button>
      </Card>

      <Card title="Điều kiện nhận thưởng (chống AFK / cày)">
        <div className="form cols">
          <Field
            label="Có mặt tối thiểu (giây)"
            hint="Lấy số nhỏ hơn với tỉ lệ"
          >
            <input
              className="input"
              type="number"
              min={0}
              value={boss.eligibility.min_active_seconds}
              onChange={(e) =>
                eligibility({ min_active_seconds: Number(e.target.value) })
              }
            />
          </Field>
          <Field label="hoặc tỉ lệ thời lượng trận">
            <input
              className="input"
              type="number"
              step={0.05}
              min={0}
              max={1}
              value={boss.eligibility.min_active_fraction}
              onChange={(e) =>
                eligibility({ min_active_fraction: Number(e.target.value) })
              }
            />
          </Field>
          <Field label="Sát thương tối thiểu (tỉ lệ HP Boss)">
            <input
              className="input"
              type="number"
              step={0.005}
              min={0}
              max={1}
              value={boss.eligibility.min_damage_fraction}
              onChange={(e) =>
                eligibility({ min_damage_fraction: Number(e.target.value) })
              }
            />
          </Field>
          <Field label="…hoặc số hành động hỗ trợ">
            <input
              className="input"
              type="number"
              min={0}
              value={boss.eligibility.support_actions}
              onChange={(e) =>
                eligibility({ support_actions: Number(e.target.value) })
              }
            />
          </Field>
          <Field label="Thao tác tối thiểu (dưới = AFK)">
            <input
              className="input"
              type="number"
              min={0}
              value={boss.eligibility.min_actions}
              onChange={(e) =>
                eligibility({ min_actions: Number(e.target.value) })
              }
            />
          </Field>
          <Field label="Lượt thưởng đầy đủ / ngày / người">
            <input
              className="input"
              type="number"
              min={0}
              value={boss.full_reward_limit_per_day}
              onChange={num('full_reward_limit_per_day')}
            />
          </Field>
          <label className="check">
            <input
              type="checkbox"
              checked={boss.reward_private_room}
              onChange={(e) => set({ reward_private_room: e.target.checked })}
            />
            Phòng riêng cũng nhận thưởng (mặc định tắt)
          </label>
        </div>
      </Card>

      <Card title="Thưởng mỗi trận">
        <div className="form cols">
          <Field label="Thắng (đủ điều kiện)" full>
            <Rewards
              value={boss.win_rewards}
              items={items}
              token={token}
              onChange={(win_rewards) => set({ win_rewards })}
            />
          </Field>
          <Field label="Thua / hết giờ (an ủi, không có rương)" full>
            <Rewards
              value={boss.lose_rewards}
              items={items}
              token={token}
              onChange={(lose_rewards) => set({ lose_rewards })}
            />
          </Field>
        </div>
      </Card>
      <button className="btn small ghost" onClick={() => onChange(null)}>
        Bỏ Boss khỏi sự kiện
      </button>
    </div>
  );
}

type BossAnalytics = {
  raids: number;
  by_result: Record<string, number>;
  win_rate: number;
  ttk_median_s: number;
  ttk_p95_s: number;
  participants: number;
  avg_team: number;
  private_raids: number;
  grants: Record<string, number>;
  payout_claimed: Record<string, number>;
  rejected: Record<string, number>;
};

type Raid = {
  match_id: string;
  result: string;
  hp_max: number;
  hp_left: number;
  duration_ms: number;
  private: boolean;
  created_at: string;
  players: {
    account_id: string;
    name: string;
    damage: number;
    support: number;
    active_ms: number;
    reward: string;
    reason: string;
  }[];
};

const REASON: Record<string, string> = {
  ABORTED: 'Trận hủy',
  PRIVATE_ROOM: 'Phòng riêng',
  NOT_ACTIVE: 'Chưa đủ thời gian',
  AFK: 'AFK',
  NO_CONTRIBUTION: 'Chưa đóng góp',
  DAILY_LIMIT: 'Hết lượt ngày',
  NO_ACCOUNT: 'Không có tài khoản',
};

/** Boss LiveOps board inside the event statistics. */
export function BossStats({
  eventId,
  canSettle,
  toast,
}: {
  eventId: string;
  canSettle: boolean;
  toast: (message: string, error?: boolean) => void;
}) {
  const [data, setData] = useState<{
    stats: BossAnalytics;
    raids: Raid[];
  } | null>(null);
  const [shown, setShown] = useState<Raid | null>(null);
  async function load() {
    try {
      const [stats, raids] = await Promise.all([
        api<BossAnalytics>(`/boss/events/${eventId}/analytics`),
        api<{ raids: Raid[] }>(`/boss/events/${eventId}/raids`),
      ]);
      setData({ stats, raids: raids.raids });
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }
  async function settle() {
    try {
      const done = await api<{ expired: number }>(
        `/boss/events/${eventId}/settle`,
        { method: 'POST' },
      );
      toast(`Đã kết toán: ${done.expired} phần thưởng hết hạn`);
      void load();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }
  if (!data)
    return (
      <button className="btn secondary" onClick={load}>
        Xem số liệu Boss
      </button>
    );
  const s = data.stats;
  return (
    <div className="stack">
      <div className="grid stats">
        <Stat icon="⚔️" tone="coral" value={s.raids} label="Trận Boss" />
        <Stat
          icon="🏆"
          tone="sun"
          value={`${Math.round(s.win_rate * 100)}%`}
          label="Tỉ lệ thắng"
        />
        <Stat
          icon="⏱️"
          tone="sky"
          value={`${s.ttk_median_s}s / ${s.ttk_p95_s}s`}
          label="TTK trung vị / p95"
        />
        <Stat
          icon="👥"
          tone="mint"
          value={`${s.participants} · ${s.avg_team}`}
          label="Người tham gia · đội TB"
        />
      </div>
      <p className="spark">
        Kết quả:{' '}
        {Object.entries(s.by_result)
          .map(([k, v]) => `${k} ${v}`)
          .join(' · ')}{' '}
        · Phòng riêng {s.private_raids} · Phần thưởng: chờ nhận{' '}
        {s.grants.ELIGIBLE ?? 0}, đã nhận {s.grants.CLAIMED ?? 0}, hết hạn{' '}
        {s.grants.EXPIRED ?? 0}
      </p>
      <p className="spark">
        Đã phát (đã nhận):{' '}
        {Object.entries(s.payout_claimed)
          .map(([k, v]) => `${k} ${v}`)
          .join(', ') || 'chưa có'}{' '}
        · Bị từ chối:{' '}
        {Object.entries(s.rejected)
          .map(([k, v]) => `${REASON[k] ?? k} ${v}`)
          .join(', ') || 'không'}
      </p>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>Trận</th>
              <th>Kết quả</th>
              <th>HP</th>
              <th>Thời lượng</th>
              <th>Người</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {data.raids.map((r) => (
              <tr key={r.match_id}>
                <td className="spark">
                  {dateTime(r.created_at)}
                  {r.private ? ' · riêng' : ''}
                </td>
                <td>{r.result}</td>
                <td>
                  {r.hp_left}/{r.hp_max}
                </td>
                <td>{Math.round(r.duration_ms / 1000)}s</td>
                <td>{r.players.length}</td>
                <td>
                  <button
                    className="btn small ghost"
                    onClick={() => setShown(r)}
                  >
                    Chi tiết
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {canSettle && (
        <button className="btn warn" onClick={settle}>
          Kết toán (sau hạn nhận thưởng)
        </button>
      )}
      {shown && (
        <Modal title={`Trận ${shown.match_id}`} onClose={() => setShown(null)}>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Người chơi</th>
                  <th>Sát thương</th>
                  <th>Hỗ trợ</th>
                  <th>Có mặt</th>
                  <th>Thưởng</th>
                </tr>
              </thead>
              <tbody>
                {shown.players.map((p) => (
                  <tr key={p.account_id}>
                    <td>{p.name}</td>
                    <td>{p.damage}</td>
                    <td>{p.support}</td>
                    <td>{Math.round(p.active_ms / 1000)}s</td>
                    <td>
                      {p.reward === 'none'
                        ? (REASON[p.reason] ?? p.reason)
                        : p.reward === 'full'
                          ? 'Đầy đủ'
                          : 'An ủi'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Modal>
      )}
    </div>
  );
}
