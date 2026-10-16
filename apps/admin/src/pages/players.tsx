import { useRouter } from 'next/router';
import { useEffect, useState } from 'react';
import Layout from '@/components/Layout';
import { type Ledger, LedgerTable } from '@/components/Ledger';
import MatchList, { type MatchRow } from '@/components/MatchList';
import {
  Card,
  Empty,
  Field,
  Loading,
  Modal,
  Rarity,
  Stat,
  Thumb,
  useReason,
} from '@/components/ui';
import { api } from '@/lib/api';
import {
  ACTION,
  ago,
  CATEGORY,
  dateTime,
  fromLocalInput,
  number,
  toLocalInput,
} from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

type Status = 'active' | 'locked' | 'unlocked';
type Row = {
  id: string;
  username: string | null;
  name: string;
  guest: boolean;
  email: string | null;
  created_at: string | null;
  last_login_at: string | null;
  last_seen_at: string | null;
  vip: boolean;
  banned: boolean;
  status: Status;
  online: boolean;
  gold: number | null;
  gem: number | null;
  items: number;
};
type Page = { items: Row[]; total: number; page: number; size: number };
type Sanction = {
  id: string;
  reason: string;
  created_by: string;
  created_at: string;
  expires_at: string | null;
  revoked_at: string | null;
  active: boolean;
};
type Detail = Row & {
  vip_until: string | null;
  inventory: {
    item_id: string;
    name: string;
    category: string | null;
    rarity: string | null;
    icon: string | null;
  }[];
  stock: { item_id: string; quantity: number }[];
  ledger: Ledger[];
  stats: {
    matches: number;
    wins: number;
    kills: number;
    rooms_created: number;
  };
  friends: number;
  guild: string | null;
  sanctions: Sanction[];
  messages: { id: number; channel: string; body: string; created_at: string }[];
  giftcodes: { code: string; created_at: string }[];
};
type Catalog = { items: { id: string; name: string; status: string }[] };
type Audit = {
  entries: {
    id: number;
    actor: string;
    action: string;
    reason: string;
    created_at: string;
  }[];
};

const CHANNEL: Record<string, string> = {
  world: 'Thế giới',
  guild: 'Bang',
  private: 'Riêng',
  room: 'Phòng',
};
const STATUS: Record<Status, [string, string]> = {
  active: ['Hoạt động', 'green'],
  locked: ['Đã khóa', 'red'],
  unlocked: ['Đã mở khóa', 'blue'],
};

function StatusBadge({ status, online }: { status: Status; online?: boolean }) {
  const [label, tone] = STATUS[status];
  return (
    <>
      <span className={`badge ${tone}`}>{label}</span>{' '}
      {online && <span className="badge green">● Online</span>}
    </>
  );
}

export default function Players() {
  const router = useRouter();
  const { can, toast } = useSession();
  const [q, setQ] = useState('');
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('all');
  const [page, setPage] = useState(1);
  const [open, setOpen] = useState<string | null>(null);
  const [locking, setLocking] = useState<Row | null>(null);
  const [reasonModal, askReason] = useReason();
  const list = useLoad(
    () =>
      api<Page>(
        `/accounts?q=${encodeURIComponent(search)}&status=${status}&page=${page}&size=20`,
      ),
    [search, status, page],
  );
  useEffect(() => {
    const id = router.query.id;
    if (typeof id === 'string') setOpen(id);
  }, [router.query.id]);
  const pages = list.data
    ? Math.max(1, Math.ceil(list.data.total / list.data.size))
    : 1;

  /** Inline status change: locking asks for duration + reason, unlocking for a reason. */
  async function changeStatus(row: Row, next: string) {
    if (next === 'locked') return setLocking(row);
    if (row.status !== 'locked') return;
    const reason = await askReason(`Mở khóa ${row.name}`, 'Mở khóa');
    if (!reason) return;
    try {
      const detail = await api<Detail>(`/accounts/${row.id}`);
      const active = detail.sanctions.find((s) => s.active);
      if (active)
        await api(`/accounts/${row.id}/sanctions/${active.id}/revoke`, {
          method: 'POST',
          body: { reason },
        });
      toast('Đã mở khóa tài khoản');
      list.reload();
    } catch (error) {
      toast((error as Error).message, true);
    }
  }

  return (
    <Layout
      title="Quản lý người chơi"
      subtitle="Trạng thái, tài sản, giao dịch, trận đấu và khóa tài khoản có ghi nhật ký."
    >
      {reasonModal}
      <Card>
        <form
          className="toolbar"
          onSubmit={(event) => {
            event.preventDefault();
            setPage(1);
            setSearch(q.trim());
          }}
        >
          <input
            className="input grow"
            placeholder="Tìm theo tên tài khoản, tên hiển thị, email hoặc ID…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            aria-label="Tìm người chơi"
          />
          <select
            className="input"
            value={status}
            onChange={(e) => {
              setPage(1);
              setStatus(e.target.value);
            }}
            aria-label="Lọc trạng thái"
          >
            <option value="all">Tất cả</option>
            <option value="online">Đang online</option>
            <option value="registered">Đã đăng ký</option>
            <option value="guest">Khách</option>
            <option value="banned">Đã khóa</option>
            <option value="unlocked">Đã mở khóa</option>
          </select>
          <button className="btn" type="submit">
            Tìm kiếm
          </button>
        </form>
      </Card>
      <Card
        title={list.data ? `${number(list.data.total)} tài khoản` : 'Tài khoản'}
      >
        {!list.data ? (
          <Loading error={list.error} />
        ) : list.data.items.length === 0 ? (
          <Empty title="Không có tài khoản phù hợp" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Tên</th>
                  <th>Trạng thái</th>
                  <th>Vàng</th>
                  <th>Kim cương</th>
                  <th>Vật phẩm</th>
                  <th>Hoạt động gần nhất</th>
                  <th>Tạo lúc</th>
                </tr>
              </thead>
              <tbody>
                {list.data.items.map((row) => (
                  <tr
                    key={row.id}
                    className="clickable"
                    onClick={() => setOpen(row.id)}
                  >
                    <td>
                      <b>{row.name}</b>{' '}
                      {row.guest && <span className="badge">Khách</span>}{' '}
                      {row.vip && <span className="badge amber">VIP</span>}
                      <div className="spark">{row.email ?? row.id}</div>
                    </td>
                    <td onClick={(e) => e.stopPropagation()}>
                      {can('sanction') ? (
                        <select
                          className={`input status-${row.status}`}
                          value={row.status === 'locked' ? 'locked' : 'active'}
                          onChange={(e) => changeStatus(row, e.target.value)}
                          aria-label={`Trạng thái của ${row.name}`}
                        >
                          <option value="active">
                            {row.status === 'unlocked'
                              ? 'Đã mở khóa'
                              : 'Hoạt động'}
                          </option>
                          <option value="locked">Đã khóa</option>
                        </select>
                      ) : (
                        <StatusBadge status={row.status} />
                      )}
                      {row.online && (
                        <div className="spark online">● Đang online</div>
                      )}
                    </td>
                    <td>
                      {row.gold === null ? (
                        <span className="muted">—</span>
                      ) : (
                        number(row.gold)
                      )}
                    </td>
                    <td>
                      {row.gem === null ? (
                        <span className="muted">—</span>
                      ) : (
                        number(row.gem)
                      )}
                    </td>
                    <td>{row.items}</td>
                    <td>{ago(row.last_seen_at ?? row.last_login_at)}</td>
                    <td>{dateTime(row.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="pager">
          <button
            className="btn small ghost"
            disabled={page <= 1}
            onClick={() => setPage(page - 1)}
          >
            ‹ Trước
          </button>
          <span>
            Trang {page}/{pages}
          </span>
          <button
            className="btn small ghost"
            disabled={page >= pages}
            onClick={() => setPage(page + 1)}
          >
            Sau ›
          </button>
        </div>
        <p className="spark">
          “—” ở cột vàng/kim cương: tài khoản chưa mở ví server (chưa đăng nhập
          từ khi có ví).
        </p>
      </Card>
      {locking && (
        <BanModal
          account={locking}
          onClose={() => setLocking(null)}
          onDone={() => {
            setLocking(null);
            list.reload();
          }}
        />
      )}
      {open && (
        <PlayerDetail
          id={open}
          onClose={() => {
            setOpen(null);
            list.reload();
            if (router.query.id) router.replace('/players');
          }}
        />
      )}
    </Layout>
  );
}

function BanModal({
  account,
  onClose,
  onDone,
}: {
  account: { id: string; name: string };
  onClose: () => void;
  onDone: () => void;
}) {
  const { toast } = useSession();
  const [hours, setHours] = useState('24');
  const [reason, setReason] = useState('');
  return (
    <Modal title={`Khóa tài khoản ${account.name}`} onClose={onClose}>
      <div className="form">
        <div className="notice">
          Khóa chặn đăng nhập và mọi API tài khoản ngay. Trận arena đang chơi
          không bị ngắt giữa chừng.
        </div>
        <Field label="Thời hạn">
          <select
            className="input"
            value={hours}
            onChange={(e) => setHours(e.target.value)}
          >
            <option value="1">1 giờ</option>
            <option value="24">1 ngày</option>
            <option value="168">7 ngày</option>
            <option value="720">30 ngày</option>
            <option value="">Vĩnh viễn</option>
          </select>
        </Field>
        <Field label="Lý do" hint="Ít nhất 5 ký tự, lưu vào nhật ký audit.">
          <textarea
            className="input"
            value={reason}
            maxLength={500}
            onChange={(e) => setReason(e.target.value)}
          />
        </Field>
      </div>
      <div className="modal-actions">
        <button className="btn ghost" onClick={onClose}>
          Hủy
        </button>
        <button
          className="btn danger"
          disabled={reason.trim().length < 5}
          onClick={async () => {
            try {
              await api(`/accounts/${account.id}/sanctions`, {
                method: 'POST',
                body: {
                  reason: reason.trim(),
                  hours: hours ? Number(hours) : null,
                },
              });
              toast('Đã khóa tài khoản');
              onDone();
            } catch (error) {
              toast((error as Error).message, true);
            }
          }}
        >
          Khóa
        </button>
      </div>
    </Modal>
  );
}

function PlayerDetail({ id, onClose }: { id: string; onClose: () => void }) {
  const { can, toast } = useSession();
  const [tab, setTab] = useState('overview');
  const [reasonModal, askReason] = useReason();
  const [banning, setBanning] = useState(false);
  const [grantItem, setGrantItem] = useState('');
  const [edit, setEdit] = useState<{
    display_name: string;
    email: string;
    vip_until: string;
  } | null>(null);
  const [adjust, setAdjust] = useState({ currency: 'gem', delta: '' });
  const detail = useLoad(() => api<Detail>(`/accounts/${id}`), [id]);
  const catalog = useLoad(() => api<Catalog>('/items?status=published'));
  const audit = useLoad(
    () => api<Audit>(`/audit?target_id=${id}&limit=50`),
    [id],
  );
  const matches = useLoad(
    () => api<{ items: MatchRow[] }>(`/matches?account_id=${id}&size=30`),
    [id],
  );
  const d = detail.data;

  async function run(action: () => Promise<unknown>, done: string) {
    try {
      await action();
      toast(done);
      detail.reload();
      audit.reload();
      return true;
    } catch (error) {
      toast((error as Error).message, true);
      return false;
    }
  }

  const active = d?.sanctions.find((s) => s.active);
  return (
    <Modal
      title={d ? `Người chơi: ${d.name}` : 'Người chơi'}
      onClose={onClose}
      wide
    >
      {reasonModal}
      {!d ? (
        <Loading error={detail.error} />
      ) : (
        <>
          <div className="toolbar">
            <StatusBadge status={d.status} online={d.online} />
            {d.guest && <span className="badge">Khách</span>}
            {d.vip && <span className="badge amber">VIP</span>}
            <span className="grow" />
            {can('sanction') &&
              (active ? (
                <button
                  className="btn success"
                  onClick={async () => {
                    const reason = await askReason(
                      'Mở khóa tài khoản',
                      'Mở khóa',
                    );
                    if (reason)
                      run(
                        () =>
                          api(`/accounts/${id}/sanctions/${active.id}/revoke`, {
                            method: 'POST',
                            body: { reason },
                          }),
                        'Đã mở khóa tài khoản',
                      );
                  }}
                >
                  Mở khóa
                </button>
              ) : (
                <button className="btn danger" onClick={() => setBanning(true)}>
                  Khóa tài khoản
                </button>
              ))}
          </div>
          <div className="tabs" role="tablist">
            {[
              ['overview', 'Thông tin'],
              ['assets', 'Tài sản'],
              ['ledger', `Giao dịch (${d.ledger.length})`],
              ['matches', `Trận đấu (${d.stats.matches})`],
              ['chat', `Chat (${d.messages.length})`],
              ['sanctions', `Lịch sử khóa (${d.sanctions.length})`],
              ['audit', 'Nhật ký'],
            ].map(([key, label]) => (
              <button
                key={key}
                className={tab === key ? 'active' : ''}
                onClick={() => setTab(key)}
              >
                {label}
              </button>
            ))}
          </div>
          {tab === 'overview' &&
            (edit ? (
              <div className="form cols">
                <Field label="Tên hiển thị">
                  <input
                    className="input"
                    maxLength={24}
                    value={edit.display_name}
                    onChange={(e) =>
                      setEdit({ ...edit, display_name: e.target.value })
                    }
                  />
                </Field>
                <Field label="Email" hint="Dùng để nhận mã quên mật khẩu">
                  <input
                    className="input"
                    type="email"
                    value={edit.email}
                    onChange={(e) =>
                      setEdit({ ...edit, email: e.target.value })
                    }
                  />
                </Field>
                <Field label="VIP đến" hint="Để trống = không VIP">
                  <input
                    className="input"
                    type="datetime-local"
                    value={edit.vip_until}
                    onChange={(e) =>
                      setEdit({ ...edit, vip_until: e.target.value })
                    }
                  />
                </Field>
                <div className="modal-actions full">
                  <button className="btn ghost" onClick={() => setEdit(null)}>
                    Hủy
                  </button>
                  <button
                    className="btn"
                    onClick={async () => {
                      const reason = await askReason(
                        'Lưu thay đổi thông tin',
                        'Lưu',
                      );
                      if (!reason) return;
                      const ok = await run(
                        () =>
                          api(`/accounts/${id}`, {
                            method: 'PATCH',
                            body: {
                              reason,
                              display_name: edit.display_name.trim(),
                              email: edit.email.trim(),
                              vip_until: edit.vip_until
                                ? fromLocalInput(edit.vip_until)
                                : null,
                              clear_vip: !edit.vip_until,
                            },
                          }),
                        'Đã lưu thông tin',
                      );
                      if (ok) setEdit(null);
                    }}
                  >
                    Lưu
                  </button>
                </div>
              </div>
            ) : (
              <>
                <dl className="kv">
                  <dt>ID</dt>
                  <dd>{d.id}</dd>
                  <dt>Tên tài khoản</dt>
                  <dd>{d.username ?? '— (khách)'}</dd>
                  <dt>Tên hiển thị</dt>
                  <dd>{d.name}</dd>
                  <dt>Email</dt>
                  <dd>{d.email ?? 'Chưa có (không lấy lại mật khẩu được)'}</dd>
                  <dt>Tạo lúc</dt>
                  <dd>{dateTime(d.created_at)}</dd>
                  <dt>Đăng nhập cuối</dt>
                  <dd>{dateTime(d.last_login_at)}</dd>
                  <dt>Hoạt động gần nhất</dt>
                  <dd>
                    {dateTime(d.last_seen_at)}{' '}
                    {d.online && <span className="badge green">● Online</span>}
                  </dd>
                  <dt>VIP đến</dt>
                  <dd>{dateTime(d.vip_until)}</dd>
                  <dt>Bạn bè / bang</dt>
                  <dd>
                    {d.friends} bạn · {d.guild ?? 'chưa có bang'}
                  </dd>
                  <dt>Giftcode đã dùng</dt>
                  <dd>{d.giftcodes.map((g) => g.code).join(', ') || '—'}</dd>
                </dl>
                {can('sanction') && (
                  <div className="modal-actions">
                    <button
                      className="btn secondary"
                      onClick={() =>
                        setEdit({
                          display_name: d.name,
                          email: d.email ?? '',
                          vip_until: d.vip_until
                            ? toLocalInput(d.vip_until)
                            : '',
                        })
                      }
                    >
                      Sửa thông tin
                    </button>
                  </div>
                )}
              </>
            ))}
          {tab === 'assets' && (
            <>
              <div className="grid stats">
                <Stat
                  icon="🪙"
                  tone="sun"
                  value={d.gold === null ? '—' : number(d.gold)}
                  label="Vàng"
                />
                <Stat
                  icon="💎"
                  tone="sky"
                  value={d.gem === null ? '—' : number(d.gem)}
                  label="Kim cương"
                />
                <Stat
                  icon="🎒"
                  tone="violet"
                  value={number(d.inventory.length)}
                  label="Vật phẩm sở hữu"
                />
                <Stat
                  icon="📦"
                  tone="mint"
                  value={number(
                    d.stock.reduce((sum, s) => sum + s.quantity, 0),
                  )}
                  label="Vật phẩm tiêu hao"
                />
              </div>
              {can('liveops') && (
                <Card title="Cộng / trừ tiền (ghi vào sổ giao dịch)">
                  <div className="toolbar">
                    <select
                      className="input"
                      value={adjust.currency}
                      onChange={(e) =>
                        setAdjust({ ...adjust, currency: e.target.value })
                      }
                      aria-label="Loại tiền"
                    >
                      <option value="gem">Kim cương</option>
                      <option value="gold">Vàng</option>
                    </select>
                    <input
                      className="input"
                      type="number"
                      placeholder="Ví dụ 100 hoặc -50"
                      value={adjust.delta}
                      onChange={(e) =>
                        setAdjust({ ...adjust, delta: e.target.value })
                      }
                      aria-label="Số lượng"
                    />
                    <button
                      className="btn warn"
                      disabled={!Number(adjust.delta)}
                      onClick={async () => {
                        const reason = await askReason(
                          `${Number(adjust.delta) > 0 ? 'Cộng' : 'Trừ'} ${Math.abs(Number(adjust.delta))} ${adjust.currency === 'gem' ? 'kim cương' : 'vàng'}`,
                          'Xác nhận',
                        );
                        if (
                          reason &&
                          (await run(
                            () =>
                              api(`/accounts/${id}/wallet`, {
                                method: 'POST',
                                body: {
                                  currency: adjust.currency,
                                  delta: Number(adjust.delta),
                                  reason,
                                },
                              }),
                            'Đã cập nhật ví',
                          ))
                        )
                          setAdjust({ ...adjust, delta: '' });
                      }}
                    >
                      Áp dụng
                    </button>
                  </div>
                </Card>
              )}
              <Card title="Kho đồ">
                {can('liveops') && (
                  <div className="toolbar">
                    <select
                      className="input grow"
                      value={grantItem}
                      onChange={(e) => setGrantItem(e.target.value)}
                      aria-label="Chọn vật phẩm để tặng"
                    >
                      <option value="">
                        Chọn vật phẩm đã phát hành để tặng…
                      </option>
                      {(catalog.data?.items ?? [])
                        .filter(
                          (i) =>
                            !d.inventory.some(
                              (owned) => owned.item_id === i.id,
                            ),
                        )
                        .map((i) => (
                          <option key={i.id} value={i.id}>
                            {i.name} ({i.id})
                          </option>
                        ))}
                    </select>
                    <button
                      className="btn"
                      disabled={!grantItem}
                      onClick={async () => {
                        const reason = await askReason('Tặng vật phẩm', 'Tặng');
                        if (
                          reason &&
                          (await run(
                            () =>
                              api(`/accounts/${id}/inventory`, {
                                method: 'POST',
                                body: { item_id: grantItem, reason },
                              }),
                            'Đã tặng vật phẩm',
                          ))
                        )
                          setGrantItem('');
                      }}
                    >
                      Tặng
                    </button>
                  </div>
                )}
                {d.inventory.length === 0 ? (
                  <Empty title="Kho đồ trống" />
                ) : (
                  <div className="chips">
                    {d.inventory.map((item) => (
                      <div className="item-chip" key={item.item_id}>
                        <Thumb icon={item.icon} />
                        <div>
                          <b>{item.name}</b>
                          <div className="spark">
                            {item.category
                              ? CATEGORY[item.category]
                              : item.item_id}{' '}
                            <Rarity value={item.rarity} />
                          </div>
                        </div>
                        {can('liveops') && (
                          <button
                            className="btn small ghost"
                            onClick={async () => {
                              const reason = await askReason(
                                `Thu hồi ${item.name}`,
                                'Thu hồi',
                              );
                              if (reason)
                                run(
                                  () =>
                                    api(
                                      `/accounts/${id}/inventory/${item.item_id}/revoke`,
                                      { method: 'POST', body: { reason } },
                                    ),
                                  'Đã thu hồi vật phẩm',
                                );
                            }}
                          >
                            Thu hồi
                          </button>
                        )}
                      </div>
                    ))}
                  </div>
                )}
                {d.stock.length > 0 && (
                  <p className="spark">
                    Tiêu hao:{' '}
                    {d.stock
                      .map((s) => `${s.item_id} ×${s.quantity}`)
                      .join(', ')}
                  </p>
                )}
              </Card>
            </>
          )}
          {tab === 'ledger' && <LedgerTable entries={d.ledger} />}
          {tab === 'matches' && (
            <>
              <div className="grid stats">
                <Stat
                  icon="⚔️"
                  tone="sky"
                  value={d.stats.matches}
                  label="Trận đã chơi"
                />
                <Stat
                  icon="🏆"
                  tone="sun"
                  value={d.stats.wins}
                  label="Trận thắng"
                />
                <Stat
                  icon="💥"
                  tone="coral"
                  value={d.stats.kills}
                  label="Hạ gục"
                />
                <Stat
                  icon="🏠"
                  tone="violet"
                  value={d.stats.rooms_created}
                  label="Phòng đã tạo"
                />
              </div>
              {!matches.data ? (
                <Loading error={matches.error} />
              ) : (
                <MatchList matches={matches.data.items} />
              )}
            </>
          )}
          {tab === 'chat' &&
            (d.messages.length === 0 ? (
              <Empty title="Chưa gửi tin nhắn nào" />
            ) : (
              <div className="list">
                {d.messages.map((m) => (
                  <div key={m.id}>
                    <span className="badge blue">
                      {CHANNEL[m.channel] ?? m.channel}
                    </span>
                    <span className="grow">{m.body}</span>
                    <span className="spark">{dateTime(m.created_at)}</span>
                    {can('sanction') && (
                      <button
                        className="btn small danger"
                        onClick={async () => {
                          const reason = await askReason('Xóa tin nhắn', 'Xóa');
                          if (reason)
                            run(
                              () =>
                                api(`/chat/${m.id}/delete`, {
                                  method: 'POST',
                                  body: { reason },
                                }),
                              'Đã xóa tin nhắn',
                            );
                        }}
                      >
                        Xóa
                      </button>
                    )}
                  </div>
                ))}
              </div>
            ))}
          {tab === 'sanctions' &&
            (d.sanctions.length === 0 ? (
              <Empty title="Chưa từng bị khóa" />
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Lý do</th>
                      <th>Người khóa</th>
                      <th>Lúc</th>
                      <th>Hết hạn</th>
                      <th>Trạng thái</th>
                    </tr>
                  </thead>
                  <tbody>
                    {d.sanctions.map((s) => (
                      <tr key={s.id}>
                        <td>{s.reason}</td>
                        <td>{s.created_by}</td>
                        <td>{dateTime(s.created_at)}</td>
                        <td>
                          {s.expires_at ? dateTime(s.expires_at) : 'Vĩnh viễn'}
                        </td>
                        <td>
                          {s.active ? (
                            <span className="badge red">Hiệu lực</span>
                          ) : s.revoked_at ? (
                            <span className="badge blue">
                              Đã mở {dateTime(s.revoked_at)}
                            </span>
                          ) : (
                            <span className="badge">Hết hạn</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            ))}
          {tab === 'audit' &&
            (!audit.data ? (
              <Loading error={audit.error} />
            ) : audit.data.entries.length === 0 ? (
              <Empty title="Chưa có thao tác quản trị trên tài khoản này" />
            ) : (
              <div className="list">
                {audit.data.entries.map((e) => (
                  <div key={e.id}>
                    <span className="badge blue">{e.actor}</span>
                    <b>{ACTION[e.action] ?? e.action}</b>
                    <span className="grow muted">{e.reason}</span>
                    <span className="spark">{dateTime(e.created_at)}</span>
                  </div>
                ))}
              </div>
            ))}
        </>
      )}
      {banning && d && (
        <BanModal
          account={d}
          onClose={() => setBanning(false)}
          onDone={() => {
            setBanning(false);
            detail.reload();
            audit.reload();
          }}
        />
      )}
    </Modal>
  );
}
