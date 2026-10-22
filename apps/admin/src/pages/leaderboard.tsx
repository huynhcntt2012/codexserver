import { useEffect, useState } from 'react';
import Layout from '@/components/Layout';
import { Card, Empty, Field, Loading, useReason } from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime, iconUrl, number } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

type Board = 'exp' | 'skin' | 'gold';
type Hidden = { reason: string; by: string; at: string };
type Row = {
  account_id: string;
  name: string;
  hero: string;
  value: number;
  rank: number | null;
  hidden: Hidden | null;
};
type Settings = {
  exp: Record<string, number>;
  skin: Record<string, number>;
  size: number;
  defaults: {
    exp: Record<string, number>;
    skin: Record<string, number>;
    size: number;
  };
  skin_categories: string[];
  hidden_count: number;
  updated_by: string | null;
  updated_at: string | null;
};

const BOARDS: [Board, string, string][] = [
  ['exp', '⭐', 'Kinh nghiệm'],
  ['skin', '👕', 'Điểm skin'],
  ['gold', '🪙', 'Tiền'],
];
const UNIT: Record<Board, string> = { exp: 'EXP', skin: 'điểm', gold: 'vàng' };
const EXP_FIELDS: [string, string][] = [
  ['match', 'Mỗi trận online đã xác minh'],
  ['win', 'Thắng trận (hạng 1)'],
  ['kill', 'Mỗi lần hạ đối thủ'],
  ['boss_raid', 'Mỗi trận Đại Chiến Boss'],
  ['boss_win', 'Thắng Boss'],
];
const SKIN_FIELDS: [string, string][] = [
  ['common', 'Thường'],
  ['rare', 'Hiếm'],
  ['epic', 'Epic'],
  ['legendary', 'Huyền thoại'],
];

function Medal({ rank }: { rank: number | null }) {
  if (rank === null) return <span className="badge">Ẩn</span>;
  const medal = ['🥇', '🥈', '🥉'][rank - 1];
  return <b>{medal ?? rank}</b>;
}

export default function Leaderboard() {
  const { can, toast } = useSession();
  const [board, setBoard] = useState<Board>('exp');
  const [q, setQ] = useState('');
  const [draft, setDraft] = useState<Settings | null>(null);
  const [reasonModal, askReason] = useReason();
  const list = useLoad(
    () =>
      api<{ board: Board; total: number; rows: Row[] }>(
        `/leaderboards?board=${board}&limit=100&q=${encodeURIComponent(q.trim())}`,
      ),
    [board, q],
  );
  const config = useLoad(() => api<Settings>('/leaderboards/settings'), []);
  const hidden = useLoad(
    () =>
      api<{ players: ({ account_id: string; name: string } & Hidden)[] }>(
        '/leaderboards/hidden',
      ),
    [],
  );
  useEffect(() => {
    if (config.data) setDraft(config.data);
  }, [config.data]);

  function reloadAll() {
    list.reload();
    hidden.reload();
    config.reload();
  }

  async function hide(row: Row) {
    const reason = await askReason(
      `Ẩn ${row.name} khỏi mọi bảng xếp hạng`,
      'Ẩn khỏi bảng',
    );
    if (!reason) return;
    try {
      await api(`/leaderboards/hidden/${row.account_id}`, {
        method: 'POST',
        body: { reason },
      });
      toast(`Đã ẩn ${row.name} khỏi bảng xếp hạng`);
      reloadAll();
    } catch (error) {
      toast((error as Error).message, true);
    }
  }

  async function show(accountId: string, name: string) {
    try {
      await api(`/leaderboards/hidden/${accountId}`, { method: 'DELETE' });
      toast(`${name} đã trở lại bảng xếp hạng`);
      reloadAll();
    } catch (error) {
      toast((error as Error).message, true);
    }
  }

  async function saveSettings() {
    if (!draft) return;
    try {
      await api('/leaderboards/settings', {
        method: 'PUT',
        body: { exp: draft.exp, skin: draft.skin, size: Number(draft.size) },
      });
      toast('Đã lưu cách tính điểm xếp hạng');
      reloadAll();
    } catch (error) {
      toast((error as Error).message, true);
    }
  }

  const number_input = (
    value: number,
    change: (value: number) => void,
    max = 100000,
  ) => (
    <input
      className="input"
      type="number"
      min={0}
      max={max}
      value={value}
      disabled={!can('liveops')}
      onChange={(e) => change(Math.max(0, Number(e.target.value)))}
    />
  );

  return (
    <Layout
      title="Bảng xếp hạng"
      subtitle="Kinh nghiệm, điểm skin và tiền của người chơi; ẩn tài khoản vi phạm, chỉnh cách tính điểm."
    >
      <div className="notice info">
        Mọi số liệu lấy từ máy chủ: EXP từ trận online / luyện tập trên arena đã
        xác minh và trận Boss, điểm skin từ đồ trang trí trong kho (
        {config.data?.skin_categories.join(', ') ?? '…'}), tiền là số vàng trong
        ví. Trận do client tự báo không được tính. Game đọc qua{' '}
        <code>GET /v1/leaderboards</code>.
      </div>
      <div className="tabs">
        {BOARDS.map(([key, icon, label]) => (
          <button
            key={key}
            className={board === key ? 'active' : ''}
            onClick={() => setBoard(key)}
          >
            {icon} {label}
          </button>
        ))}
      </div>
      <div className="grid two">
        <Card
          title={`Bảng ${BOARDS.find((b) => b[0] === board)?.[2]}`}
          action={
            <input
              className="input"
              placeholder="Tìm tên hoặc ID…"
              value={q}
              maxLength={24}
              onChange={(e) => setQ(e.target.value)}
              aria-label="Tìm người chơi"
            />
          }
        >
          {!list.data ? (
            <Loading error={list.error} />
          ) : list.data.rows.length === 0 ? (
            <Empty title="Chưa có người chơi nào có điểm ở bảng này" />
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Hạng</th>
                    <th>Người chơi</th>
                    <th>
                      {UNIT[board] === 'EXP'
                        ? 'Kinh nghiệm'
                        : UNIT[board] === 'điểm'
                          ? 'Điểm skin'
                          : 'Vàng'}
                    </th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  {list.data.rows.map((row) => (
                    <tr
                      key={row.account_id}
                      className={row.hidden ? 'muted' : ''}
                    >
                      <td>
                        <Medal rank={row.rank} />
                      </td>
                      <td>
                        <div className="toolbar">
                          <img
                            className="thumb"
                            src={
                              iconUrl(`characters/portraits/${row.hero}.png`) ??
                              ''
                            }
                            alt=""
                            loading="lazy"
                          />
                          <div>
                            <a href={`/admin/players/?id=${row.account_id}`}>
                              <b>{row.name}</b>
                            </a>
                            {row.hidden && (
                              <div className="spark">
                                Ẩn bởi {row.hidden.by}: {row.hidden.reason}
                              </div>
                            )}
                          </div>
                        </div>
                      </td>
                      <td>
                        <b>{number(row.value)}</b> {UNIT[board]}
                      </td>
                      <td>
                        {can('liveops') &&
                          (row.hidden ? (
                            <button
                              className="btn small success"
                              onClick={() => show(row.account_id, row.name)}
                            >
                              Hiện lại
                            </button>
                          ) : (
                            <button
                              className="btn small ghost"
                              onClick={() => hide(row)}
                            >
                              Ẩn khỏi bảng
                            </button>
                          ))}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <div className="spark">
                {number(list.data.total)} người có điểm
                {list.data.total > list.data.rows.length &&
                  ` · hiển thị ${list.data.rows.length} đầu tiên`}
              </div>
            </div>
          )}
        </Card>
        <div>
          <Card title="Cách tính điểm">
            {!draft ? (
              <Loading error={config.error} />
            ) : (
              <>
                <h3>Kinh nghiệm (EXP)</h3>
                <div className="form cols">
                  {EXP_FIELDS.map(([key, label]) => (
                    <Field
                      key={key}
                      label={label}
                      hint={`Mặc định ${draft.defaults.exp[key]}`}
                    >
                      {number_input(
                        draft.exp[key],
                        (value) =>
                          setDraft({
                            ...draft,
                            exp: { ...draft.exp, [key]: value },
                          }),
                        10000,
                      )}
                    </Field>
                  ))}
                </div>
                <h3>Điểm skin theo độ hiếm (mỗi món)</h3>
                <div className="form cols">
                  {SKIN_FIELDS.map(([key, label]) => (
                    <Field
                      key={key}
                      label={label}
                      hint={`Mặc định ${draft.defaults.skin[key]}`}
                    >
                      {number_input(draft.skin[key], (value) =>
                        setDraft({
                          ...draft,
                          skin: { ...draft.skin, [key]: value },
                        }),
                      )}
                    </Field>
                  ))}
                  <Field label="Số người tối đa game hiển thị" hint="5–100">
                    {number_input(
                      draft.size,
                      (value) => setDraft({ ...draft, size: value }),
                      100,
                    )}
                  </Field>
                </div>
                <div className="toolbar">
                  <span className="spark grow">
                    {draft.updated_by
                      ? `Sửa lần cuối bởi ${draft.updated_by}, ${dateTime(draft.updated_at)}`
                      : 'Đang dùng giá trị mặc định'}
                  </span>
                  {can('liveops') && (
                    <>
                      <button
                        className="btn ghost small"
                        onClick={() =>
                          setDraft({
                            ...draft,
                            exp: { ...draft.defaults.exp },
                            skin: { ...draft.defaults.skin },
                            size: draft.defaults.size,
                          })
                        }
                      >
                        Về mặc định
                      </button>
                      <button
                        className="btn small"
                        onClick={saveSettings}
                        disabled={draft.size < 5 || draft.size > 100}
                      >
                        Lưu
                      </button>
                    </>
                  )}
                </div>
              </>
            )}
          </Card>
          <Card title={`Đang ẩn (${hidden.data?.players.length ?? '…'})`}>
            {!hidden.data ? (
              <Loading error={hidden.error} />
            ) : hidden.data.players.length === 0 ? (
              <Empty title="Không có ai bị ẩn" />
            ) : (
              <div className="list">
                {hidden.data.players.map((p) => (
                  <div key={p.account_id}>
                    <div className="grow">
                      <a href={`/admin/players/?id=${p.account_id}`}>
                        {p.name}
                      </a>
                      <div className="spark">
                        {p.reason} · {p.by}, {dateTime(p.at)}
                      </div>
                    </div>
                    {can('liveops') && (
                      <button
                        className="btn small success"
                        onClick={() => show(p.account_id, p.name)}
                      >
                        Hiện lại
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      </div>
      {reasonModal}
    </Layout>
  );
}
