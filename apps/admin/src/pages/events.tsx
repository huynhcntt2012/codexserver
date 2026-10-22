import { useState } from 'react';
import Layout from '@/components/Layout';
import QuestEditor, {
  newObjective,
  newReward,
  Objective,
  Reward,
  summary,
  useCatalog,
} from '@/components/QuestEditor';
import BossEditor, {
  BossConfig,
  BossStats,
  fullBoss,
} from '@/components/BossEditor';
import { Card, Empty, Field, Loading, Modal, Phase } from '@/components/ui';
import { api } from '@/lib/api';
import {
  dateTime,
  EVENT_KIND,
  fromLocalInput,
  toLocalInput,
} from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

type Chapter = {
  key: string;
  title: string;
  map_id: string | null;
  unlock_offset_days: number;
  requires_previous: boolean;
  npc: string;
  npc_line: string;
};

type EventQuest = {
  key: string;
  title: string;
  description: string;
  chapter: string | null;
  reset: 'once' | 'daily' | 'weekly';
  objectives: Objective[];
  rewards: Reward[];
};

type ShopEntry = {
  sku: string;
  item_id: string;
  cost: number;
  stock: number | null;
  per_player: number;
};

type Config = {
  token_name: string;
  banner: string;
  intro: string;
  npc: string;
  chapters: Chapter[];
  quests: EventQuest[];
  shop: ShopEntry[];
  boss: BossConfig | null;
};

type GameEvent = {
  id: string;
  name: string;
  kind: string;
  description: string;
  status: string;
  phase: string;
  start_at: string;
  end_at: string;
  claim_end_at: string | null;
  reward_items: string[];
  config: Partial<Config>;
  version: number;
  created_by: string;
  updated_at: string;
};

type Draft = {
  id?: string;
  name: string;
  kind: string;
  description: string;
  start_at: string;
  end_at: string;
  claim_end_at: string;
  config: Config;
};

type Check = {
  ok: boolean;
  errors: string[];
  warnings: string[];
  max_tokens: number;
};

type Analytics = {
  participants: number;
  quests: {
    key: string;
    title: string;
    chapter: string | null;
    started: number;
    completed: number;
    claimed: number;
  }[];
  tokens_granted: number;
  tokens_spent: number;
  orders: number;
  buyers: number;
  by_sku: Record<string, number>;
  versions: { version: number; created_by: string; created_at: string }[];
};

const STEPS = [
  '1. Thông tin',
  '2. Lịch',
  '3. Chương',
  '4. Nhiệm vụ',
  '5. Event Shop',
  '6. Boss',
  '7. Kiểm tra & lưu',
];
const CHECK_STEP = STEPS.length - 1;

const EMPTY: Config = {
  token_name: 'Vé Sao',
  banner: '',
  intro: '',
  npc: '',
  chapters: [],
  quests: [],
  shop: [],
  boss: null,
};

/** Fills optional fields the API may omit (old events, templates). */
function fullConfig(config: Partial<Config> | undefined): Config {
  const c = { ...EMPTY, ...(config ?? {}) };
  return {
    ...c,
    chapters: (c.chapters ?? []).map((ch: Partial<Chapter>) => ({
      key: ch.key ?? '',
      title: ch.title ?? '',
      npc: ch.npc ?? '',
      npc_line: ch.npc_line ?? '',
      map_id: ch.map_id ?? null,
      requires_previous: ch.requires_previous ?? true,
      unlock_offset_days: ch.unlock_offset_days ?? 0,
    })),
    quests: (c.quests ?? []).map((q: Partial<EventQuest>) => ({
      key: q.key ?? '',
      title: q.title ?? '',
      description: q.description ?? '',
      chapter: q.chapter ?? null,
      reset: q.reset ?? 'once',
      objectives: (q.objectives ?? []).map((o: Partial<Objective>) => ({
        type: o.type ?? 'MATCH_COMPLETED',
        target: o.target ?? 1,
        map_ids: o.map_ids ?? [],
        modes: o.modes ?? ['online'],
      })),
      rewards: (q.rewards ?? []).map((r: Partial<Reward>) => ({
        type: r.type ?? 'gold',
        amount: r.amount ?? 1,
        item_id: r.item_id ?? null,
      })),
    })),
    boss: fullBoss(c.boss),
    shop: (c.shop ?? []).map((s: Partial<ShopEntry>) => ({
      sku: s.sku ?? '',
      item_id: s.item_id ?? '',
      cost: s.cost ?? 1,
      stock: s.stock ?? null,
      per_player: s.per_player ?? 1,
    })),
  };
}

function toDraft(
  event: Partial<GameEvent> & { start_at: string; end_at: string },
): Draft {
  return {
    id: event.id,
    name: event.name ?? '',
    kind: event.kind ?? 'challenge',
    description: event.description ?? '',
    start_at: toLocalInput(event.start_at),
    end_at: toLocalInput(event.end_at),
    claim_end_at: event.claim_end_at ? toLocalInput(event.claim_end_at) : '',
    config: fullConfig(event.config),
  };
}

function blank(): Draft {
  const start = new Date();
  start.setMinutes(0, 0, 0);
  start.setHours(start.getHours() + 1);
  const end = new Date(start.getTime() + 7 * 86400000);
  return toDraft({
    start_at: start.toISOString(),
    end_at: end.toISOString(),
    kind: 'challenge',
  });
}

function body(draft: Draft) {
  return {
    name: draft.name,
    kind: draft.kind,
    description: draft.description,
    start_at: fromLocalInput(draft.start_at),
    end_at: fromLocalInput(draft.end_at),
    claim_end_at: draft.claim_end_at
      ? fromLocalInput(draft.claim_end_at)
      : null,
    reward_items: [],
    config: draft.config,
  };
}

export default function Events() {
  const { can, toast } = useSession();
  const list = useLoad(() => api<{ events: GameEvent[] }>('/events'));
  const { mapIds, items } = useCatalog();
  const [draft, setDraft] = useState<Draft | null>(null);
  const [step, setStep] = useState(0);
  const [check, setCheck] = useState<Check | null>(null);
  const [stats, setStats] = useState<{
    event: GameEvent;
    data: Analytics;
  } | null>(null);

  const config = draft?.config ?? EMPTY;
  const setConfig = (patch: Partial<Config>) =>
    draft && setDraft({ ...draft, config: { ...draft.config, ...patch } });

  function open(next: Draft) {
    setDraft(next);
    setStep(0);
    setCheck(null);
  }

  async function fromTemplate(
    kind: 'story' | 'boss' | 'robot' | 'cactus' | 'ram' = 'story',
  ) {
    try {
      const template = await api<GameEvent>(`/events/template?kind=${kind}`);
      open(toDraft(template));
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function validate(): Promise<boolean> {
    if (!draft) return false;
    try {
      const result = await api<Check>('/events/validate', {
        method: 'POST',
        body: body(draft),
      });
      setCheck(result);
      return result.ok;
    } catch (reason) {
      setCheck({
        ok: false,
        errors: [(reason as Error).message],
        warnings: [],
        max_tokens: 0,
      });
      return false;
    }
  }

  async function save(publish: boolean) {
    if (!draft || !(await validate())) {
      setStep(CHECK_STEP);
      return;
    }
    try {
      const saved = draft.id
        ? await api<GameEvent>(`/events/${draft.id}`, {
            method: 'PUT',
            body: body(draft),
          })
        : await api<GameEvent>('/events', {
            method: 'POST',
            body: body(draft),
          });
      if (publish && saved.status === 'draft')
        await api(`/events/${saved.id}/publish`, { method: 'POST' });
      toast(publish ? 'Đã lưu và phát hành sự kiện' : 'Đã lưu bản nháp');
      setDraft(null);
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function act(event: GameEvent, action: 'publish' | 'pause' | 'resume') {
    try {
      await api(`/events/${event.id}/${action}`, { method: 'POST' });
      toast(
        {
          publish: 'Đã phát hành',
          pause: 'Đã tạm dừng: người chơi không thấy sự kiện',
          resume: 'Đã tiếp tục (phiên bản mới)',
        }[action],
      );
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function analytics(event: GameEvent) {
    try {
      setStats({
        event,
        data: await api<Analytics>(`/events/${event.id}/analytics`),
      });
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  const chapters = config.chapters;
  const setChapter = (i: number, patch: Partial<Chapter>) =>
    setConfig({
      chapters: chapters.map((c, j) => (j === i ? { ...c, ...patch } : c)),
    });
  const setQuest = (i: number, patch: Partial<EventQuest>) =>
    setConfig({
      quests: config.quests.map((q, j) => (j === i ? { ...q, ...patch } : q)),
    });
  const setShop = (i: number, patch: Partial<ShopEntry>) =>
    setConfig({
      shop: config.shop.map((s, j) => (j === i ? { ...s, ...patch } : s)),
    });

  return (
    <Layout
      title="Sự kiện LiveOps"
      subtitle="Tạo sự kiện có chương, nhiệm vụ, Vé sự kiện và Event Shop; lưu nháp, phát hành, tạm dừng."
      actions={
        can('liveops') && (
          <div className="toolbar">
            <button className="btn secondary" onClick={() => fromTemplate()}>
              Tạo từ mẫu “Giải Cứu Bầu Trời Bong Bóng”
            </button>
            <button
              className="btn secondary"
              onClick={() => fromTemplate('boss')}
            >
              Tạo từ mẫu “Đại Chiến Boss”
            </button>
            <button
              className="btn secondary"
              onClick={() => fromTemplate('robot')}
            >
              Tạo từ mẫu “Robot Bom Dây Cót”
            </button>
            <button
              className="btn secondary"
              onClick={() => fromTemplate('cactus')}
            >
              Tạo từ mẫu “Vua Xương Rồng”
            </button>
            <button
              className="btn secondary"
              onClick={() => fromTemplate('ram')}
            >
              Tạo từ mẫu “Cừu Sấm Sét”
            </button>
            <button className="btn warn" onClick={() => open(blank())}>
              + Sự kiện mới
            </button>
          </div>
        )
      }
    >
      <Card
        title={list.data ? `${list.data.events.length} sự kiện` : 'Sự kiện'}
      >
        {!list.data ? (
          <Loading error={list.error} />
        ) : list.data.events.length === 0 ? (
          <Empty title="Chưa có sự kiện">Bấm “Tạo từ mẫu” để thử nhanh.</Empty>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Sự kiện</th>
                  <th>Loại</th>
                  <th>Trạng thái</th>
                  <th>Lịch</th>
                  <th>Nội dung</th>
                  <th>Phiên bản</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {list.data.events.map((event) => {
                  const c = fullConfig(event.config);
                  return (
                    <tr key={event.id}>
                      <td>
                        <b>{event.name}</b>
                        <div className="spark">{event.description}</div>
                      </td>
                      <td>{EVENT_KIND[event.kind] ?? event.kind}</td>
                      <td>
                        <Phase value={event.phase} />
                      </td>
                      <td className="spark">
                        {dateTime(event.start_at)} → {dateTime(event.end_at)}
                        {event.claim_end_at && (
                          <>
                            <br />
                            Nhận thưởng tới {dateTime(event.claim_end_at)}
                          </>
                        )}
                      </td>
                      <td className="spark">
                        {c.chapters.length} chương · {c.quests.length} nhiệm vụ
                        · {c.shop.length} món shop
                        {c.boss && (
                          <>
                            <br />
                            ⚔️ {c.boss.display_name} · {c.boss.map_id} · 1-
                            {c.boss.max_players} người
                          </>
                        )}
                      </td>
                      <td>v{event.version}</td>
                      <td>
                        <div className="toolbar">
                          {can('liveops') && event.phase !== 'running' && (
                            <button
                              className="btn small secondary"
                              onClick={() => open(toDraft(event))}
                            >
                              Sửa
                            </button>
                          )}
                          {can('liveops') && event.status === 'draft' && (
                            <button
                              className="btn small"
                              onClick={() => act(event, 'publish')}
                            >
                              Phát hành
                            </button>
                          )}
                          {can('liveops') && event.status === 'published' && (
                            <button
                              className="btn small ghost"
                              onClick={() => act(event, 'pause')}
                            >
                              Tạm dừng
                            </button>
                          )}
                          {can('liveops') && event.status === 'paused' && (
                            <button
                              className="btn small"
                              onClick={() => act(event, 'resume')}
                            >
                              Tiếp tục
                            </button>
                          )}
                          {event.status !== 'draft' && (
                            <button
                              className="btn small ghost"
                              onClick={() => analytics(event)}
                            >
                              Thống kê
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      {draft && (
        <Modal
          title={draft.id ? 'Sửa sự kiện' : 'Sự kiện mới'}
          onClose={() => setDraft(null)}
          wide
        >
          <div className="tabs">
            {STEPS.map((label, i) => (
              <button
                key={label}
                className={i === step ? 'active' : ''}
                onClick={() => setStep(i)}
              >
                {label}
              </button>
            ))}
          </div>

          {step === 0 && (
            <div className="form cols">
              <Field label="Tên sự kiện">
                <input
                  className="input"
                  value={draft.name}
                  onChange={(e) => setDraft({ ...draft, name: e.target.value })}
                />
              </Field>
              <Field label="Loại">
                <select
                  className="input"
                  value={draft.kind}
                  onChange={(e) => setDraft({ ...draft, kind: e.target.value })}
                >
                  {Object.entries(EVENT_KIND).map(([key, label]) => (
                    <option key={key} value={key}>
                      {label}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Mô tả ngắn" full>
                <input
                  className="input"
                  value={draft.description}
                  onChange={(e) =>
                    setDraft({ ...draft, description: e.target.value })
                  }
                />
              </Field>
              <Field label="Banner (dòng giới thiệu trên app)" full>
                <input
                  className="input"
                  value={config.banner}
                  onChange={(e) => setConfig({ banner: e.target.value })}
                />
              </Field>
              <Field label="Cốt truyện" full>
                <textarea
                  className="input"
                  rows={3}
                  value={config.intro}
                  onChange={(e) => setConfig({ intro: e.target.value })}
                />
              </Field>
              <Field label="Nhân vật dẫn truyện (NPC)">
                <input
                  className="input"
                  value={config.npc}
                  onChange={(e) => setConfig({ npc: e.target.value })}
                />
              </Field>
              <Field
                label="Tên vé sự kiện"
                hint="Chỉ dùng trong sự kiện này, không đổi ra xu/KC"
              >
                <input
                  className="input"
                  value={config.token_name}
                  onChange={(e) => setConfig({ token_name: e.target.value })}
                />
              </Field>
            </div>
          )}

          {step === 1 && (
            <div className="form cols">
              <Field label="Bắt đầu">
                <input
                  className="input"
                  type="datetime-local"
                  value={draft.start_at}
                  onChange={(e) =>
                    setDraft({ ...draft, start_at: e.target.value })
                  }
                />
              </Field>
              <Field
                label="Kết thúc"
                hint="Sau thời điểm này không tính tiến độ mới"
              >
                <input
                  className="input"
                  type="datetime-local"
                  value={draft.end_at}
                  onChange={(e) =>
                    setDraft({ ...draft, end_at: e.target.value })
                  }
                />
              </Field>
              <Field
                label="Hạn nhận thưởng"
                hint="Để trống = bằng thời điểm kết thúc"
              >
                <input
                  className="input"
                  type="datetime-local"
                  value={draft.claim_end_at}
                  onChange={(e) =>
                    setDraft({ ...draft, claim_end_at: e.target.value })
                  }
                />
              </Field>
              <Field label="Múi giờ">
                <input
                  className="input"
                  value="Asia/Ho_Chi_Minh (UTC+7)"
                  disabled
                />
              </Field>
            </div>
          )}

          {step === 2 && (
            <div className="stack">
              <p className="spark">
                Chương mở theo ngày sự kiện (0 = ngày đầu). Người vào muộn vẫn
                chơi các chương đã mở.
              </p>
              {chapters.map((c, i) => (
                <Card key={i} title={`Chương ${i + 1}`}>
                  <div className="form cols">
                    <Field label="Mã">
                      <input
                        className="input"
                        value={c.key}
                        onChange={(e) => setChapter(i, { key: e.target.value })}
                      />
                    </Field>
                    <Field label="Tên chương">
                      <input
                        className="input"
                        value={c.title}
                        onChange={(e) =>
                          setChapter(i, { title: e.target.value })
                        }
                      />
                    </Field>
                    <Field label="Bản đồ chính (không bắt buộc)">
                      <input
                        className="input"
                        list="map-ids"
                        value={c.map_id ?? ''}
                        onChange={(e) =>
                          setChapter(i, { map_id: e.target.value || null })
                        }
                      />
                    </Field>
                    <Field label="Mở sau (ngày)">
                      <input
                        className="input"
                        type="number"
                        min={0}
                        value={c.unlock_offset_days}
                        onChange={(e) =>
                          setChapter(i, {
                            unlock_offset_days: Number(e.target.value),
                          })
                        }
                      />
                    </Field>
                    <Field label="NPC">
                      <input
                        className="input"
                        value={c.npc}
                        onChange={(e) => setChapter(i, { npc: e.target.value })}
                      />
                    </Field>
                    <label className="check">
                      <input
                        type="checkbox"
                        checked={c.requires_previous}
                        onChange={(e) =>
                          setChapter(i, { requires_previous: e.target.checked })
                        }
                      />
                      Cần xong chương trước
                    </label>
                    <Field label="Lời thoại" full>
                      <input
                        className="input"
                        value={c.npc_line}
                        onChange={(e) =>
                          setChapter(i, { npc_line: e.target.value })
                        }
                      />
                    </Field>
                  </div>
                  <button
                    className="btn small ghost"
                    onClick={() =>
                      setConfig({
                        chapters: chapters.filter((_, j) => j !== i),
                      })
                    }
                  >
                    Xóa chương
                  </button>
                </Card>
              ))}
              <button
                className="btn secondary"
                onClick={() =>
                  setConfig({
                    chapters: [
                      ...chapters,
                      {
                        key: `CH${String(chapters.length + 1).padStart(2, '0')}`,
                        title: '',
                        map_id: null,
                        unlock_offset_days: chapters.length,
                        requires_previous: true,
                        npc: '',
                        npc_line: '',
                      },
                    ],
                  })
                }
              >
                + Chương
              </button>
            </div>
          )}

          {step === 3 && (
            <div className="stack">
              {config.quests.map((q, i) => (
                <Card key={i} title={`${q.key || 'Nhiệm vụ'} · ${q.title}`}>
                  <div className="form cols">
                    <Field label="Mã">
                      <input
                        className="input"
                        value={q.key}
                        onChange={(e) => setQuest(i, { key: e.target.value })}
                      />
                    </Field>
                    <Field label="Tên">
                      <input
                        className="input"
                        value={q.title}
                        onChange={(e) => setQuest(i, { title: e.target.value })}
                      />
                    </Field>
                    <Field label="Thuộc chương">
                      <select
                        className="input"
                        value={q.chapter ?? ''}
                        onChange={(e) =>
                          setQuest(i, {
                            chapter: e.target.value || null,
                            reset: e.target.value ? 'once' : q.reset,
                          })
                        }
                      >
                        <option value="">Không (nhiệm vụ sự kiện)</option>
                        {chapters.map((c) => (
                          <option key={c.key} value={c.key}>
                            {c.key} · {c.title}
                          </option>
                        ))}
                      </select>
                    </Field>
                    <Field label="Nhận thưởng">
                      <select
                        className="input"
                        value={q.reset}
                        disabled={!!q.chapter}
                        onChange={(e) =>
                          setQuest(i, {
                            reset: e.target.value as EventQuest['reset'],
                          })
                        }
                      >
                        <option value="once">Một lần cả sự kiện</option>
                        <option value="daily">Mỗi ngày</option>
                        <option value="weekly">Mỗi tuần (thứ Hai)</option>
                      </select>
                    </Field>
                  </div>
                  <QuestEditor
                    objectives={q.objectives}
                    rewards={q.rewards}
                    allowToken
                    mapIds={mapIds}
                    items={items}
                    onChange={(objectives, rewards) =>
                      setQuest(i, { objectives, rewards })
                    }
                  />
                  <button
                    className="btn small ghost"
                    onClick={() =>
                      setConfig({
                        quests: config.quests.filter((_, j) => j !== i),
                      })
                    }
                  >
                    Xóa nhiệm vụ
                  </button>
                </Card>
              ))}
              <button
                className="btn secondary"
                onClick={() =>
                  setConfig({
                    quests: [
                      ...config.quests,
                      {
                        key: `Q${config.quests.length + 1}`,
                        title: '',
                        description: '',
                        chapter: null,
                        reset: 'once',
                        objectives: [newObjective()],
                        rewards: [
                          { ...newReward(), type: 'token', amount: 20 },
                        ],
                      },
                    ],
                  })
                }
              >
                + Nhiệm vụ
              </button>
            </div>
          )}

          {step === 4 && (
            <div className="stack">
              <p className="spark">
                Người chơi đổi {config.token_name} lấy vật phẩm. Vật phẩm vĩnh
                viễn chỉ đổi 1 lần/người.
              </p>
              {config.shop.map((s, i) => (
                <div className="toolbar" key={i}>
                  <input
                    className="input small"
                    aria-label="SKU"
                    value={s.sku}
                    onChange={(e) => setShop(i, { sku: e.target.value })}
                  />
                  <select
                    className="input grow"
                    aria-label="Vật phẩm"
                    value={s.item_id}
                    onChange={(e) => setShop(i, { item_id: e.target.value })}
                  >
                    {items.map((item) => (
                      <option key={item.id} value={item.id}>
                        {item.name} ({item.id})
                      </option>
                    ))}
                  </select>
                  <label className="check">
                    Giá
                    <input
                      className="input small"
                      type="number"
                      min={1}
                      value={s.cost}
                      onChange={(e) =>
                        setShop(i, { cost: Number(e.target.value) })
                      }
                    />
                  </label>
                  <label className="check">
                    Tối đa/người
                    <input
                      className="input small"
                      type="number"
                      min={1}
                      value={s.per_player}
                      onChange={(e) =>
                        setShop(i, { per_player: Number(e.target.value) })
                      }
                    />
                  </label>
                  <label className="check">
                    Tồn kho
                    <input
                      className="input small"
                      type="number"
                      min={1}
                      placeholder="∞"
                      value={s.stock ?? ''}
                      onChange={(e) =>
                        setShop(i, {
                          stock: e.target.value ? Number(e.target.value) : null,
                        })
                      }
                    />
                  </label>
                  <button
                    className="btn small ghost"
                    onClick={() =>
                      setConfig({ shop: config.shop.filter((_, j) => j !== i) })
                    }
                  >
                    Xóa
                  </button>
                </div>
              ))}
              <button
                className="btn secondary"
                onClick={() =>
                  setConfig({
                    shop: [
                      ...config.shop,
                      {
                        sku: `sku${config.shop.length + 1}`,
                        item_id: items[0]?.id ?? '',
                        cost: 100,
                        stock: null,
                        per_player: 1,
                      },
                    ],
                  })
                }
              >
                + Món đổi quà
              </button>
            </div>
          )}

          {step === 5 && (
            <BossEditor
              boss={config.boss}
              token={config.token_name}
              mapIds={mapIds}
              items={items}
              onChange={(boss) => setConfig({ boss })}
            />
          )}

          {step === CHECK_STEP && (
            <div className="stack">
              <p>
                <b>{draft.name || '(chưa đặt tên)'}</b> · {chapters.length}{' '}
                chương · {config.quests.length} nhiệm vụ · {config.shop.length}{' '}
                món shop
              </p>
              <ul className="spark">
                {config.quests.map((q) => (
                  <li key={q.key}>
                    [
                    {q.chapter ??
                      {
                        daily: 'mỗi ngày',
                        weekly: 'mỗi tuần',
                        once: 'sự kiện',
                      }[q.reset]}
                    ] {q.title}:{' '}
                    {summary(q.objectives, q.rewards, config.token_name)}
                  </li>
                ))}
              </ul>
              <button className="btn secondary" onClick={validate}>
                Kiểm tra cấu hình
              </button>
              {check && (
                <div
                  className={`notice${check.ok ? ' info' : ''}`}
                  role="status"
                >
                  <div>
                    {check.ok
                      ? `✅ Hợp lệ. Người chơi tích cực kiếm tối đa ${check.max_tokens} ${config.token_name}.`
                      : '❌ Chưa hợp lệ:'}
                    <ul>
                      {check.errors.map((e) => (
                        <li key={e}>{e}</li>
                      ))}
                      {check.warnings.map((w) => (
                        <li key={w}>⚠️ {w}</li>
                      ))}
                    </ul>
                  </div>
                </div>
              )}
            </div>
          )}
          <datalist id="map-ids">
            {mapIds.map((id) => (
              <option key={id} value={id} />
            ))}
          </datalist>
          <div className="modal-actions">
            {step > 0 && (
              <button className="btn ghost" onClick={() => setStep(step - 1)}>
                Quay lại
              </button>
            )}
            {step < STEPS.length - 1 && (
              <button
                className="btn secondary"
                onClick={() => setStep(step + 1)}
              >
                Tiếp
              </button>
            )}
            <button className="btn secondary" onClick={() => save(false)}>
              Lưu nháp
            </button>
            {!draft.id && (
              <button className="btn" onClick={() => save(true)}>
                Lưu & phát hành
              </button>
            )}
          </div>
        </Modal>
      )}

      {stats && (
        <Modal
          title={`Thống kê · ${stats.event.name}`}
          onClose={() => setStats(null)}
          wide
        >
          <p>
            {stats.data.participants} người tham gia · đã phát{' '}
            {stats.data.tokens_granted} vé · đã tiêu {stats.data.tokens_spent}{' '}
            vé · {stats.data.orders} lượt đổi ({stats.data.buyers} người)
          </p>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Nhiệm vụ</th>
                  <th>Bắt đầu</th>
                  <th>Hoàn thành</th>
                  <th>Đã nhận</th>
                </tr>
              </thead>
              <tbody>
                {stats.data.quests.map((q) => (
                  <tr key={q.key}>
                    <td>
                      {q.chapter ? `${q.chapter} · ` : ''}
                      {q.title}
                    </td>
                    <td>{q.started}</td>
                    <td>{q.completed}</td>
                    <td>{q.claimed}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="spark">
            Shop:{' '}
            {Object.entries(stats.data.by_sku)
              .map(([sku, n]) => `${sku} ×${n}`)
              .join(', ') || 'chưa có'}{' '}
            · Phiên bản:{' '}
            {stats.data.versions
              .map((v) => `v${v.version} (${v.created_by})`)
              .join(', ')}
          </p>
          {stats.event.config.boss && (
            <BossStats
              eventId={stats.event.id}
              canSettle={can('liveops')}
              toast={toast}
            />
          )}
        </Modal>
      )}
    </Layout>
  );
}
