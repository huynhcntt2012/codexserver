import { api } from '@/lib/api';
import { useLoad } from '@/lib/session';

// Shared editor for one quest's objectives and rewards (missions and events).

export type Objective = {
  type: string;
  target: number;
  map_ids: string[];
  modes: ('online' | 'practice')[];
};

export type Reward = {
  type: 'gold' | 'gem' | 'token' | 'item';
  amount: number;
  item_id: string | null;
};

export const RULES: Record<string, string> = {
  MATCH_COMPLETED: 'Hoàn thành trận',
  MATCH_WON: 'Thắng trận',
  BOMB_PLACED: 'Đặt bom nước',
  MAPS_DISTINCT: 'Chơi bản đồ khác nhau',
  LOGIN_DAY: 'Điểm danh ngày',
  WITH_FRIEND: 'Chơi cùng bạn bè',
};

export const REWARD: Record<Reward['type'], string> = {
  gold: 'Xu',
  gem: 'Kim cương',
  token: 'Vé sự kiện',
  item: 'Vật phẩm',
};

export function newObjective(): Objective {
  return { type: 'MATCH_COMPLETED', target: 1, map_ids: [], modes: ['online'] };
}

export function newReward(): Reward {
  return { type: 'gold', amount: 100, item_id: null };
}

/** Map ids (built-in + admin maps) and item ids for the pickers. */
export function useCatalog() {
  const maps = useLoad(() =>
    api<{ maps: { id: string; name: string }[]; builtin: string[] }>('/maps'),
  );
  const items = useLoad(() =>
    api<{ items: { id: string; name: string; status: string }[] }>('/items'),
  );
  const mapIds = [
    ...(maps.data?.builtin ?? []),
    ...(maps.data?.maps ?? []).map((m) => m.id),
  ];
  return { mapIds, items: items.data?.items ?? [] };
}

export function summary(
  objectives: Objective[],
  rewards: Reward[],
  token = 'Vé',
) {
  const goal = objectives
    .map(
      (o) =>
        `${RULES[o.type] ?? o.type} ×${o.target}` +
        (o.map_ids.length ? ` (${o.map_ids.join(', ')})` : '') +
        (o.modes.includes('practice') ? ' · tính Luyện tập' : ''),
    )
    .join(' + ');
  const prize = rewards
    .map((r) =>
      r.type === 'item'
        ? `${r.item_id} ×${r.amount}`
        : `${r.amount} ${r.type === 'token' ? token : REWARD[r.type]}`,
    )
    .join(', ');
  return `${goal} → ${prize}`;
}

export default function QuestEditor({
  objectives,
  rewards,
  onChange,
  allowToken,
  mapIds,
  items,
}: {
  objectives: Objective[];
  rewards: Reward[];
  onChange: (objectives: Objective[], rewards: Reward[]) => void;
  allowToken: boolean;
  mapIds: string[];
  items: { id: string; name: string }[];
}) {
  const setObjective = (i: number, patch: Partial<Objective>) =>
    onChange(
      objectives.map((o, j) => (j === i ? { ...o, ...patch } : o)),
      rewards,
    );
  const setReward = (i: number, patch: Partial<Reward>) =>
    onChange(
      objectives,
      rewards.map((r, j) => (j === i ? { ...r, ...patch } : r)),
    );
  return (
    <div className="quest-editor">
      <b>Điều kiện (tất cả phải đạt)</b>
      {objectives.map((o, i) => (
        <div className="toolbar" key={`o${i}`}>
          <select
            className="input"
            aria-label="Loại điều kiện"
            value={o.type}
            onChange={(e) => setObjective(i, { type: e.target.value })}
          >
            {Object.entries(RULES).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </select>
          <input
            className="input small"
            type="number"
            min={1}
            aria-label="Mục tiêu"
            value={o.target}
            onChange={(e) =>
              setObjective(i, { target: Number(e.target.value) })
            }
          />
          <input
            className="input grow"
            list="map-ids"
            aria-label="Bản đồ"
            placeholder="Mọi bản đồ (hoặc id, cách nhau bởi dấu phẩy)"
            value={o.map_ids.join(', ')}
            onChange={(e) =>
              setObjective(i, {
                map_ids: e.target.value
                  .split(',')
                  .map((v) => v.trim())
                  .filter(Boolean),
              })
            }
          />
          {(['online', 'practice'] as const).map((mode) => (
            <label key={mode} className="check">
              <input
                type="checkbox"
                checked={o.modes.includes(mode)}
                onChange={(e) => {
                  const modes = e.target.checked
                    ? [...o.modes, mode]
                    : o.modes.filter((m) => m !== mode);
                  if (modes.length) setObjective(i, { modes });
                }}
              />
              {mode === 'online' ? 'Online' : 'Luyện tập'}
            </label>
          ))}
          {objectives.length > 1 && (
            <button
              className="btn small ghost"
              onClick={() =>
                onChange(
                  objectives.filter((_, j) => j !== i),
                  rewards,
                )
              }
            >
              Xóa
            </button>
          )}
        </div>
      ))}
      {objectives.length < 4 && (
        <button
          className="btn small secondary"
          onClick={() => onChange([...objectives, newObjective()], rewards)}
        >
          + Điều kiện
        </button>
      )}
      <b>Phần thưởng</b>
      {rewards.map((r, i) => (
        <div className="toolbar" key={`r${i}`}>
          <select
            className="input"
            aria-label="Loại thưởng"
            value={r.type}
            onChange={(e) =>
              setReward(i, {
                type: e.target.value as Reward['type'],
                item_id:
                  e.target.value === 'item' ? (items[0]?.id ?? null) : null,
              })
            }
          >
            {(Object.keys(REWARD) as Reward['type'][])
              .filter((t) => allowToken || t !== 'token')
              .map((t) => (
                <option key={t} value={t}>
                  {REWARD[t]}
                </option>
              ))}
          </select>
          {r.type === 'item' && (
            <select
              className="input grow"
              aria-label="Vật phẩm"
              value={r.item_id ?? ''}
              onChange={(e) => setReward(i, { item_id: e.target.value })}
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
            onChange={(e) => setReward(i, { amount: Number(e.target.value) })}
          />
          {rewards.length > 1 && (
            <button
              className="btn small ghost"
              onClick={() =>
                onChange(
                  objectives,
                  rewards.filter((_, j) => j !== i),
                )
              }
            >
              Xóa
            </button>
          )}
        </div>
      ))}
      {rewards.length < 5 && (
        <button
          className="btn small secondary"
          onClick={() => onChange(objectives, [...rewards, newReward()])}
        >
          + Phần thưởng
        </button>
      )}
      <datalist id="map-ids">
        {mapIds.map((id) => (
          <option key={id} value={id} />
        ))}
      </datalist>
    </div>
  );
}
