import { useEffect, useState } from 'react';
import Layout from '@/components/Layout';
import { Card, Empty, Field, Loading, Stat } from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime, fromLocalInput, number, toLocalInput } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

type Line = { xp: number; max: number };
type Multiplier = {
  name: string;
  start_at: string;
  end_at: string;
  multiplier: number;
  modes: ('PVP' | 'PVE_BOSS')[];
};
type Config = {
  pvp: {
    completion: number;
    outcome: Record<string, number>;
    lines: Record<string, Line>;
    caps: Record<string, number>;
    eligibility: Record<string, number>;
  };
  boss: {
    completion: number;
    outcome: Record<string, number>;
    damage: number;
    lines: Record<string, Line>;
    caps: Record<string, number>;
    reward_private: boolean;
    daily: { from_count: number; factor: number }[];
  };
  multipliers: Multiplier[];
};
type Rule = {
  id: string;
  version: number;
  status: 'draft' | 'published';
  active: boolean;
  note: string;
  config: Config;
  created_by: string;
  created_at: string;
  published_by: string | null;
  published_at: string | null;
};
type Sample = {
  lines: { key: string; xp: number }[];
  raw: number;
  cap: number;
  base: number;
};
type Preview = Record<string, Sample> & {
  matches_to_10: Record<string, number | null>;
  matches_to_20: Record<string, number | null>;
};
type Rules = {
  active: { id: string; version: number; config: Config };
  rules: Rule[];
  defaults: Config;
  preview: Preview;
  level_curve: {
    version: number;
    cap: number;
    levels: { level: number; required: number }[];
  };
  multipliers: number[];
};
type Stats = {
  days: {
    day: string;
    mode: string;
    awards: number;
    exp: number;
    players: number;
    eligible: number;
    exp_per_player: number;
  }[];
  reasons: Record<string, number>;
  top_today: {
    account_id: string;
    name: string;
    matches: number;
    exp: number;
  }[];
};

type Tab =
  | 'pvp'
  | 'boss'
  | 'multiplier'
  | 'antifarm'
  | 'curve'
  | 'versions'
  | 'stats';
const TABS: [Tab, string][] = [
  ['pvp', '⚔️ PvP EXP'],
  ['boss', '👾 Boss EXP'],
  ['multiplier', '✨ Nhân EXP'],
  ['antifarm', '🛡️ Chống farm'],
  ['curve', '📈 Level Curve'],
  ['versions', '🗂️ Phiên bản'],
  ['stats', '📊 Thống kê'],
];
const PVP_LINES: [string, string][] = [
  ['ko', 'Hạ đối phương (KO)'],
  ['assist', 'Hỗ trợ hạ đối phương'],
  ['hit', 'Bom đánh trúng đối phương'],
  ['rescue', 'Cứu đồng đội (nếu mode có)'],
  ['objective', 'Mục tiêu bản đồ (nếu mode có)'],
];
const BOSS_LINES: [string, string][] = [
  ['interrupt', 'Ngắt chiêu / choáng Boss'],
  ['rescue', 'Cứu đồng đội'],
  ['minion', 'Hạ quái triệu hồi'],
  ['phase', 'Tham gia phase'],
  ['objective', 'Mục tiêu phụ'],
];
const OUTCOME: Record<string, string> = {
  WIN: 'Thắng',
  DRAW: 'Hòa',
  LOSE: 'Thua',
  TIMEOUT: 'Hết giờ',
};
const REASON: Record<string, string> = {
  ABORTED: 'Trận bị hủy',
  PRACTICE: 'Luyện tập với bot',
  PRIVATE_ROOM: 'Phòng riêng',
  NOT_ACTIVE: 'Chưa đủ thời gian',
  AFK: 'AFK',
  NO_CONTRIBUTION: 'Chưa đóng góp đủ',
  NO_ACCOUNT: 'Không có tài khoản',
};
const SAMPLES: [string, string][] = [
  ['pvp_win', 'PvP thắng: 3 KO, 2 hỗ trợ, 3 hit, 1 cứu (spec: 349)'],
  ['pvp_lose', 'PvP thua: 1 KO, 1 hit (spec: 123)'],
  ['boss_win', 'Boss thắng, đội 4, 900/2650 damage (spec: 400)'],
  ['boss_lose', 'Boss thua, đội 4, 200/2650 damage (spec: 146)'],
];

export default function Exp() {
  const { can, toast } = useSession();
  const [tab, setTab] = useState<Tab>('pvp');
  const [draft, setDraft] = useState<Config | null>(null);
  const [editing, setEditing] = useState<string | null>(null);
  const [note, setNote] = useState('');
  const [preview, setPreview] = useState<Preview | null>(null);
  const rules = useLoad(() => api<Rules>('/exp/rules'), []);
  const stats = useLoad(() => api<Stats>('/exp/stats?days=7'), []);
  const editable = can('liveops');

  useEffect(() => {
    if (rules.data && !draft) {
      setDraft(rules.data.active.config);
      setPreview(rules.data.preview);
    }
  }, [rules.data, draft]);

  async function run<T>(action: () => Promise<T>, done: string) {
    try {
      const value = await action();
      toast(done);
      return value;
    } catch (error) {
      toast((error as Error).message, true);
      return null;
    }
  }

  async function check() {
    if (!draft) return;
    const value = await run(
      () =>
        api<Preview>('/exp/rules/preview', {
          method: 'POST',
          body: { config: draft },
        }),
      'Đã tính lại 4 người chơi mẫu',
    );
    if (value) setPreview(value);
  }

  async function save() {
    if (!draft) return;
    const body = { config: draft, note };
    const saved = await run(
      () =>
        editing
          ? api<Rule>(`/exp/rules/${editing}`, { method: 'PUT', body })
          : api<Rule>('/exp/rules', { method: 'POST', body }),
      'Đã lưu bản nháp; cần chủ sở hữu duyệt để phát hành',
    );
    if (saved) {
      setEditing(saved.id);
      rules.reload();
      await check();
    }
  }

  async function publish(rule: Rule) {
    if (
      !confirm(
        `Phát hành rule v${rule.version}? Chỉ áp dụng cho các trận bắt đầu sau lúc này; trận đã chốt giữ rule cũ.`,
      )
    )
      return;
    const done = await run(
      () => api<Rule>(`/exp/rules/${rule.id}/publish`, { method: 'POST' }),
      `Đã phát hành rule v${rule.version}`,
    );
    if (done) {
      if (editing === rule.id) setEditing(null);
      rules.reload();
    }
  }

  async function remove(rule: Rule) {
    const done = await run(
      () => api(`/exp/rules/${rule.id}`, { method: 'DELETE' }),
      `Đã xóa bản nháp v${rule.version}`,
    );
    if (done !== null) {
      if (editing === rule.id) setEditing(null);
      rules.reload();
    }
  }

  function open(rule: Rule | null) {
    if (!rules.data) return;
    setDraft(rule ? rule.config : rules.data.active.config);
    setEditing(rule && rule.status === 'draft' ? rule.id : null);
    setNote(rule && rule.status === 'draft' ? rule.note : '');
    setTab('pvp');
  }

  const num = (
    value: number,
    change: (value: number) => void,
    step = 1,
    max = 10000,
  ) => (
    <input
      className="input"
      type="number"
      min={0}
      max={max}
      step={step}
      value={value}
      disabled={!editable}
      onChange={(e) => change(Math.max(0, Number(e.target.value)))}
    />
  );

  if (!rules.data || !draft)
    return (
      <Layout title="Match EXP">
        <Loading error={rules.error} />
      </Layout>
    );
  const data = rules.data;
  const pvp = draft.pvp;
  const boss = draft.boss;
  const setPvp = (value: Partial<Config['pvp']>) =>
    setDraft({ ...draft, pvp: { ...pvp, ...value } });
  const setBoss = (value: Partial<Config['boss']>) =>
    setDraft({ ...draft, boss: { ...boss, ...value } });
  const lineFields = (
    fields: [string, string][],
    lines: Record<string, Line>,
    change: (lines: Record<string, Line>) => void,
  ) =>
    fields.map(([key, label]) => (
      <div className="form cols" key={key}>
        <Field label={`${label}: EXP mỗi lần`}>
          {num(lines[key]!.xp, (xp) =>
            change({ ...lines, [key]: { ...lines[key]!, xp } }),
          )}
        </Field>
        <Field label="Số lần tính tối đa / trận">
          {num(
            lines[key]!.max,
            (max) => change({ ...lines, [key]: { ...lines[key]!, max } }),
            1,
            100,
          )}
        </Field>
      </div>
    ));
  const outcomeFields = (
    values: Record<string, number>,
    change: (values: Record<string, number>) => void,
    prefix: string,
  ) =>
    Object.keys(values).map((key) => (
      <Field key={key} label={`${prefix} ${OUTCOME[key] ?? key}`}>
        {num(values[key]!, (value) => change({ ...values, [key]: value }))}
      </Field>
    ));

  return (
    <Layout
      title="Match EXP"
      subtitle="Game Balance: EXP sau trận PvP và Đại Chiến Boss, nhân EXP, chống farm, tốc độ lên cấp."
    >
      <div className="notice info">
        Chỉ máy chủ tính và cộng EXP khi trận đã chốt (một lần mỗi người mỗi
        trận). Sửa ở đây tạo <b>bản nháp</b>; chủ sở hữu duyệt và phát hành,
        rule mới chỉ áp dụng cho trận bắt đầu sau lúc phát hành, không cần build
        lại game. Đang áp dụng:{' '}
        <b>
          {data.active.version ? `v${data.active.version}` : 'mặc định (v0)'}
        </b>
        .
      </div>
      <div className="tabs">
        {TABS.map(([key, label]) => (
          <button
            key={key}
            className={tab === key ? 'active' : ''}
            onClick={() => setTab(key)}
          >
            {label}
          </button>
        ))}
      </div>
      {['pvp', 'boss', 'multiplier', 'antifarm'].includes(tab) && (
        <div className="grid two">
          <Card
            title={
              editing
                ? 'Đang sửa bản nháp'
                : 'Bản nháp mới (từ rule đang áp dụng)'
            }
          >
            {tab === 'pvp' && (
              <>
                <div className="form cols">
                  <Field label="Hoàn thành trận hợp lệ">
                    {num(pvp.completion, (completion) =>
                      setPvp({ completion }),
                    )}
                  </Field>
                  {outcomeFields(
                    pvp.outcome,
                    (outcome) => setPvp({ outcome }),
                    'Thưởng',
                  )}
                </div>
                {lineFields(PVP_LINES, pvp.lines, (lines) => setPvp({ lines }))}
                <h3>Giới hạn EXP trận (trước nhân hệ số)</h3>
                <div className="form cols">
                  {outcomeFields(
                    pvp.caps,
                    (caps) => setPvp({ caps }),
                    'Trần khi',
                  )}
                </div>
              </>
            )}
            {tab === 'boss' && (
              <>
                <div className="form cols">
                  <Field label="Hoàn thành trận Boss hợp lệ">
                    {num(boss.completion, (completion) =>
                      setBoss({ completion }),
                    )}
                  </Field>
                  {outcomeFields(
                    boss.outcome,
                    (outcome) => setBoss({ outcome }),
                    'Thưởng',
                  )}
                  <Field
                    label="EXP sát thương tối đa"
                    hint="Đạt đủ khi gây 1/n HP Boss (n = số người lúc bắt đầu)"
                  >
                    {num(boss.damage, (damage) => setBoss({ damage }))}
                  </Field>
                </div>
                {lineFields(BOSS_LINES, boss.lines, (lines) =>
                  setBoss({ lines }),
                )}
                <h3>Giới hạn EXP trận (trước nhân hệ số)</h3>
                <div className="form cols">
                  {outcomeFields(
                    boss.caps,
                    (caps) => setBoss({ caps }),
                    'Trần khi',
                  )}
                </div>
              </>
            )}
            {tab === 'multiplier' && (
              <>
                <p className="spark">
                  Chỉ nhận ×1; ×1,25; ×1,5; ×2. Không cộng dồn: trận dùng hệ số
                  cao nhất đang chạy lúc bắt đầu. Nhân sau khi áp trần.
                </p>
                {draft.multipliers.length === 0 && (
                  <Empty title="Chưa có lịch nhân EXP" />
                )}
                {draft.multipliers.map((m, i) => {
                  const set = (value: Partial<Multiplier>) =>
                    setDraft({
                      ...draft,
                      multipliers: draft.multipliers.map((x, j) =>
                        j === i ? { ...x, ...value } : x,
                      ),
                    });
                  return (
                    <div className="form cols" key={i}>
                      <Field label="Tên">
                        <input
                          className="input"
                          value={m.name}
                          maxLength={60}
                          disabled={!editable}
                          onChange={(e) => set({ name: e.target.value })}
                        />
                      </Field>
                      <Field label="Hệ số">
                        <select
                          className="input"
                          value={m.multiplier}
                          disabled={!editable}
                          onChange={(e) =>
                            set({ multiplier: Number(e.target.value) })
                          }
                        >
                          {data.multipliers.map((v) => (
                            <option key={v} value={v}>
                              ×{v}
                            </option>
                          ))}
                        </select>
                      </Field>
                      <Field label="Bắt đầu (giờ máy bạn)">
                        <input
                          className="input"
                          type="datetime-local"
                          value={toLocalInput(m.start_at)}
                          disabled={!editable}
                          onChange={(e) =>
                            set({ start_at: fromLocalInput(e.target.value) })
                          }
                        />
                      </Field>
                      <Field label="Kết thúc">
                        <input
                          className="input"
                          type="datetime-local"
                          value={toLocalInput(m.end_at)}
                          disabled={!editable}
                          onChange={(e) =>
                            set({ end_at: fromLocalInput(e.target.value) })
                          }
                        />
                      </Field>
                      <Field label="Chế độ">
                        <select
                          className="input"
                          value={m.modes.join(',')}
                          disabled={!editable}
                          onChange={(e) =>
                            set({
                              modes: e.target.value.split(
                                ',',
                              ) as Multiplier['modes'],
                            })
                          }
                        >
                          <option value="PVP,PVE_BOSS">PvP + Boss</option>
                          <option value="PVP">Chỉ PvP</option>
                          <option value="PVE_BOSS">Chỉ Boss</option>
                        </select>
                      </Field>
                      {editable && (
                        <button
                          className="btn ghost small"
                          onClick={() =>
                            setDraft({
                              ...draft,
                              multipliers: draft.multipliers.filter(
                                (_, j) => j !== i,
                              ),
                            })
                          }
                        >
                          Xóa
                        </button>
                      )}
                    </div>
                  );
                })}
                {editable && (
                  <button
                    className="btn ghost small"
                    onClick={() => {
                      const start = new Date();
                      const end = new Date(start.getTime() + 2 * 86400_000);
                      setDraft({
                        ...draft,
                        multipliers: [
                          ...draft.multipliers,
                          {
                            name: 'Double EXP cuối tuần',
                            start_at: start.toISOString(),
                            end_at: end.toISOString(),
                            multiplier: 2,
                            modes: ['PVP', 'PVE_BOSS'],
                          },
                        ],
                      });
                    }}
                  >
                    + Thêm lịch nhân EXP
                  </button>
                )}
              </>
            )}
            {tab === 'antifarm' && (
              <>
                <h3>Điều kiện hoạt động PvP</h3>
                <div className="form cols">
                  <Field
                    label="Giây hoạt động tối thiểu"
                    hint="min(giây, tỷ lệ × thời lượng)"
                  >
                    {num(pvp.eligibility.min_active_seconds!, (v) =>
                      setPvp({
                        eligibility: {
                          ...pvp.eligibility,
                          min_active_seconds: v,
                        },
                      }),
                    )}
                  </Field>
                  <Field label="Tỷ lệ thời lượng trận" hint="0–1">
                    {num(
                      pvp.eligibility.min_active_fraction!,
                      (v) =>
                        setPvp({
                          eligibility: {
                            ...pvp.eligibility,
                            min_active_fraction: Math.min(1, v),
                          },
                        }),
                      0.05,
                      1,
                    )}
                  </Field>
                  <Field label="Bị loại sớm: giây hoạt động tối thiểu">
                    {num(pvp.eligibility.early_active_seconds!, (v) =>
                      setPvp({
                        eligibility: {
                          ...pvp.eligibility,
                          early_active_seconds: v,
                        },
                      }),
                    )}
                  </Field>
                  <Field
                    label="Số nhóm hành vi khác nhau"
                    hint="Di chuyển, bom có tác dụng, hit, vật phẩm"
                  >
                    {num(
                      pvp.eligibility.min_groups!,
                      (v) =>
                        setPvp({
                          eligibility: { ...pvp.eligibility, min_groups: v },
                        }),
                      1,
                      4,
                    )}
                  </Field>
                </div>
                <h3>Giảm EXP Boss theo lượt trong ngày (Asia/Ho_Chi_Minh)</h3>
                <div className="form cols">
                  {boss.daily.map((tier, i) => (
                    <Field
                      key={i}
                      label={`Từ lượt hợp lệ thứ ${tier.from_count}: hệ số`}
                    >
                      {num(
                        tier.factor,
                        (factor) =>
                          setBoss({
                            daily: boss.daily.map((t, j) =>
                              j === i
                                ? { ...t, factor: Math.min(1, factor) }
                                : t,
                            ),
                          }),
                        0.05,
                        1,
                      )}
                    </Field>
                  ))}
                </div>
                <Field label="Phòng Boss riêng">
                  <select
                    className="input"
                    value={boss.reward_private ? 'yes' : 'no'}
                    disabled={!editable}
                    onChange={(e) =>
                      setBoss({ reward_private: e.target.value === 'yes' })
                    }
                  >
                    <option value="no">Không nhận EXP (mặc định)</option>
                    <option value="yes">Nhận EXP</option>
                  </select>
                </Field>
                <p className="spark">
                  PvP công khai không giảm theo lượt. Luyện tập với bot luôn 0
                  EXP. Điều kiện có mặt / đóng góp của Boss lấy theo sự kiện
                  Boss (giống điều kiện nhận rương).
                </p>
              </>
            )}
            <div className="toolbar">
              <input
                className="input grow"
                placeholder="Ghi chú thay đổi (vì sao chỉnh)"
                value={note}
                maxLength={300}
                disabled={!editable}
                onChange={(e) => setNote(e.target.value)}
              />
              <button className="btn ghost small" onClick={() => open(null)}>
                Về rule đang áp dụng
              </button>
              <button
                className="btn ghost small"
                onClick={() => setDraft(data.defaults)}
                disabled={!editable}
              >
                Giá trị đề xuất
              </button>
              <button className="btn ghost small" onClick={check}>
                Xem trước
              </button>
              {editable && (
                <button className="btn small" onClick={save}>
                  {editing ? 'Lưu bản nháp' : 'Tạo bản nháp'}
                </button>
              )}
            </div>
          </Card>
          <Card title="Xem trước: người chơi mẫu (trước nhân hệ số)">
            {!preview ? (
              <Loading />
            ) : (
              <>
                <div className="list">
                  {SAMPLES.map(([key, label]) => (
                    <div key={key}>
                      <div className="grow">
                        <b>{label}</b>
                        <div className="spark">
                          {preview[key]!.lines.map(
                            (l) => `${l.key} +${l.xp}`,
                          ).join(' · ')}
                          {preview[key]!.raw > preview[key]!.cap &&
                            ` · chạm trần ${preview[key]!.cap}`}
                        </div>
                      </div>
                      <b>{number(preview[key]!.base)} EXP</b>
                    </div>
                  ))}
                </div>
                <p className="spark">
                  Từ Lv.1 lên Lv.10: {preview.matches_to_10.pvp_win ?? '–'} trận
                  thắng hoặc {preview.matches_to_10.pvp_lose ?? '–'} trận thua
                  như mẫu; lên Lv.20: {preview.matches_to_20.pvp_win ?? '–'} /{' '}
                  {preview.matches_to_20.pvp_lose ?? '–'}.
                </p>
              </>
            )}
          </Card>
        </div>
      )}
      {tab === 'curve' && (
        <Card
          title={`Level curve v${data.level_curve.version} (cố định trong code)`}
        >
          <p className="spark">
            required_xp(L) = 100 + 40(L−1) + 10(L−1)²; cấp tối đa{' '}
            {data.level_curve.cap}. Đổi curve khi đã có người chơi thật cần
            migration riêng, nên không sửa ở đây.
          </p>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Cấp</th>
                  <th>EXP để lên cấp kế</th>
                  <th>Tổng EXP từ Lv.1</th>
                </tr>
              </thead>
              <tbody>
                {data.level_curve.levels.map((l, i) => (
                  <tr key={l.level}>
                    <td>Lv.{l.level}</td>
                    <td>{number(l.required)}</td>
                    <td>
                      {number(
                        data.level_curve.levels
                          .slice(0, i)
                          .reduce((sum, x) => sum + x.required, 0),
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}
      {tab === 'versions' && (
        <Card title="Phiên bản rule">
          {data.rules.length === 0 ? (
            <Empty title="Chưa có rule nào; đang dùng giá trị đề xuất (v0)" />
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Phiên bản</th>
                    <th>Trạng thái</th>
                    <th>Ghi chú</th>
                    <th>Tạo</th>
                    <th>Phát hành</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {data.rules.map((r) => (
                    <tr key={r.id}>
                      <td>
                        <b>v{r.version}</b>
                      </td>
                      <td>
                        <span className={`badge ${r.active ? 'mint' : ''}`}>
                          {r.active
                            ? 'Đang áp dụng'
                            : r.status === 'draft'
                              ? 'Nháp'
                              : 'Đã phát hành'}
                        </span>
                      </td>
                      <td>{r.note}</td>
                      <td>
                        {r.created_by}, {dateTime(r.created_at)}
                      </td>
                      <td>
                        {r.published_by
                          ? `${r.published_by}, ${dateTime(r.published_at)}`
                          : '–'}
                      </td>
                      <td>
                        <div className="toolbar">
                          <button
                            className="btn ghost small"
                            onClick={() => open(r)}
                          >
                            {r.status === 'draft' ? 'Sửa' : 'Dùng làm nháp'}
                          </button>
                          {r.status === 'draft' && can('admins') && (
                            <button
                              className="btn small success"
                              onClick={() => publish(r)}
                            >
                              Duyệt & phát hành
                            </button>
                          )}
                          {r.status === 'draft' && editable && (
                            <button
                              className="btn ghost small"
                              onClick={() => remove(r)}
                            >
                              Xóa
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <p className="spark">
            Rollback: mở một phiên bản cũ bằng “Dùng làm nháp”, lưu và phát hành
            lại; chỉ trận sau đó dùng nó. Chỉ chủ sở hữu (owner) được phát hành.
          </p>
        </Card>
      )}
      {tab === 'stats' && (
        <>
          {!stats.data ? (
            <Loading error={stats.error} />
          ) : (
            <>
              <div className="grid stats">
                <Stat
                  icon="⭐"
                  tone="sun"
                  label="EXP đã cộng (7 ngày)"
                  value={number(stats.data.days.reduce((s, d) => s + d.exp, 0))}
                />
                <Stat
                  icon="⚔️"
                  tone="sky"
                  label="Lượt chốt EXP"
                  value={number(
                    stats.data.days.reduce((s, d) => s + d.awards, 0),
                  )}
                />
                <Stat
                  icon="✅"
                  tone="mint"
                  label="Hợp lệ"
                  value={number(
                    stats.data.days.reduce((s, d) => s + d.eligible, 0),
                  )}
                />
                <Stat
                  icon="🚫"
                  tone="coral"
                  label="Không nhận EXP"
                  value={number(
                    Object.values(stats.data.reasons).reduce(
                      (s, n) => s + n,
                      0,
                    ),
                  )}
                />
              </div>
              <div className="grid two">
                <Card title="Theo ngày">
                  {stats.data.days.length === 0 ? (
                    <Empty title="Chưa có trận nào được chốt EXP" />
                  ) : (
                    <div className="table-wrap">
                      <table>
                        <thead>
                          <tr>
                            <th>Ngày</th>
                            <th>Chế độ</th>
                            <th>Lượt</th>
                            <th>Người</th>
                            <th>EXP</th>
                            <th>EXP / người</th>
                          </tr>
                        </thead>
                        <tbody>
                          {stats.data.days.map((d) => (
                            <tr key={d.day + d.mode}>
                              <td>{d.day}</td>
                              <td>{d.mode === 'PVP' ? 'PvP' : 'Boss'}</td>
                              <td>{number(d.awards)}</td>
                              <td>{number(d.players)}</td>
                              <td>{number(d.exp)}</td>
                              <td>{number(d.exp_per_player)}</td>
                            </tr>
                          ))}
                        </tbody>
                      </table>
                    </div>
                  )}
                </Card>
                <div>
                  <Card title="Lý do không nhận EXP">
                    {Object.keys(stats.data.reasons).length === 0 ? (
                      <Empty title="Không có" />
                    ) : (
                      <div className="list">
                        {Object.entries(stats.data.reasons).map(
                          ([reason, n]) => (
                            <div key={reason}>
                              <span className="grow">
                                {REASON[reason] ?? reason}
                              </span>
                              <b>{number(n)}</b>
                            </div>
                          ),
                        )}
                      </div>
                    )}
                  </Card>
                  <Card title="Nhiều EXP nhất hôm nay (soát bất thường)">
                    {stats.data.top_today.length === 0 ? (
                      <Empty title="Chưa có" />
                    ) : (
                      <div className="list">
                        {stats.data.top_today.map((p) => (
                          <div key={p.account_id}>
                            <a
                              className="grow"
                              href={`/admin/players/?id=${p.account_id}`}
                            >
                              {p.name}
                            </a>
                            <span className="spark">{p.matches} trận</span>
                            <b>{number(p.exp)} EXP</b>
                          </div>
                        ))}
                      </div>
                    )}
                  </Card>
                </div>
              </div>
            </>
          )}
        </>
      )}
    </Layout>
  );
}
