import { useState } from 'react';
import Layout from '@/components/Layout';
import {
  Card,
  Empty,
  Field,
  Loading,
  Modal,
  Phase,
  useReason,
} from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime, number } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';
import type { Item } from '@/pages/items';

type Reward = {
  type: 'gold' | 'gem' | 'item';
  amount: number;
  item_id?: string;
  name?: string;
};
type Message = {
  id: string;
  category: string;
  sender: string;
  title: string;
  body: string;
  rewards: Reward[];
  audience: 'all' | 'players';
  targets: string[];
  status: string;
  phase: string;
  read_count: number;
  claim_count: number;
  created_by: string;
  created_at: string;
  expires_at: string;
};
type Player = { id: string; name: string; username: string | null };
type Draft = {
  title: string;
  body: string;
  category: string;
  sender: string;
  audience: 'all' | 'players';
  targets: Player[];
  rewards: Reward[];
  expires_days: number;
};

const CATEGORY: Record<string, string> = {
  admin: 'Ban điều hành',
  system: 'Hệ thống',
  event: 'Sự kiện',
  maintenance: 'Bảo trì máy chủ',
  reward: 'Quà tặng',
};

const EMPTY: Draft = {
  title: '',
  body: '',
  category: 'admin',
  sender: 'Ban điều hành',
  audience: 'all',
  targets: [],
  rewards: [],
  expires_days: 30,
};

function rewardText(reward: Reward): string {
  const name =
    reward.type === 'gold'
      ? 'vàng'
      : reward.type === 'gem'
        ? 'kim cương'
        : (reward.name ?? reward.item_id);
  return `${number(reward.amount)} ${name}`;
}

export default function Mail() {
  const { can, toast } = useSession();
  const [q, setQ] = useState('');
  const [draft, setDraft] = useState<Draft | null>(null);
  const [search, setSearch] = useState('');
  const [found, setFound] = useState<Player[]>([]);
  const [reasonModal, askReason] = useReason();
  const list = useLoad(
    () =>
      api<{ messages: Message[] }>(`/mail?q=${encodeURIComponent(q.trim())}`),
    [q],
  );
  const catalog = useLoad(() => api<{ items: Item[] }>('/items'), []);

  async function findPlayers() {
    if (search.trim().length < 2) return;
    try {
      const reply = await api<{ players: Player[] }>(
        `/mail/players?q=${encodeURIComponent(search.trim())}`,
      );
      setFound(reply.players);
      if (reply.players.length === 0) toast('Không tìm thấy người chơi', true);
    } catch (error) {
      toast((error as Error).message, true);
    }
  }

  async function send() {
    if (!draft) return;
    const everyone = draft.audience === 'all';
    const question = everyone
      ? `Gửi "${draft.title}" tới TOÀN BỘ người chơi?`
      : `Gửi "${draft.title}" tới ${draft.targets.length} người chơi?`;
    if (!window.confirm(question)) return;
    try {
      await api('/mail', {
        method: 'POST',
        body: {
          title: draft.title,
          body: draft.body,
          category: draft.category,
          sender: draft.sender,
          audience: draft.audience,
          targets: draft.targets.map((p) => p.id),
          rewards: draft.rewards.map((r) => ({
            type: r.type,
            amount: Number(r.amount),
            ...(r.type === 'item' ? { item_id: r.item_id } : {}),
          })),
          expires_days: Number(draft.expires_days),
        },
      });
      toast(everyone ? 'Đã gửi thư tới toàn server' : 'Đã gửi thư');
      setDraft(null);
      setFound([]);
      setSearch('');
      list.reload();
    } catch (error) {
      toast((error as Error).message, true);
    }
  }

  async function recall(message: Message) {
    const reason = await askReason(`Thu hồi thư "${message.title}"`, 'Thu hồi');
    if (!reason) return;
    try {
      await api(`/mail/${message.id}/recall`, {
        method: 'POST',
        body: { reason },
      });
      toast('Đã thu hồi thư');
      list.reload();
    } catch (error) {
      toast((error as Error).message, true);
    }
  }

  const items = catalog.data?.items ?? [];
  const setReward = (index: number, patch: Partial<Reward>) =>
    draft &&
    setDraft({
      ...draft,
      rewards: draft.rewards.map((r, i) =>
        i === index ? { ...r, ...patch } : r,
      ),
    });
  const ready =
    draft &&
    draft.title.trim().length >= 2 &&
    (draft.audience === 'all' || draft.targets.length > 0) &&
    draft.rewards.every(
      (r) => r.amount >= 1 && (r.type !== 'item' || r.item_id),
    );

  return (
    <Layout
      title="Hộp thư"
      subtitle="Gửi thông báo sự kiện, bảo trì hoặc quà tặng tới người chơi chỉ định hay toàn server."
      actions={
        can('liveops') && (
          <button className="btn warn" onClick={() => setDraft({ ...EMPTY })}>
            + Soạn thư
          </button>
        )
      }
    >
      <div className="notice info">
        Thư hiện trong <b>Hộp thư</b> của game. Thư gửi toàn server đến cả người
        tạo tài khoản sau khi gửi, cho tới khi hết hạn. Phần thưởng (vàng, kim
        cương, vật phẩm) người chơi bấm <b>Nhận quà</b> mới vào ví / kho, mỗi
        người một lần. Thu hồi sẽ ẩn thư với người chưa nhận.
      </div>
      <Card>
        <input
          className="input"
          placeholder="Tìm theo tiêu đề…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          aria-label="Tìm thư"
        />
      </Card>
      <Card title="Thư đã gửi">
        {!list.data ? (
          <Loading error={list.error} />
        ) : list.data.messages.length === 0 ? (
          <Empty title="Chưa gửi thư nào" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Thư</th>
                  <th>Người nhận</th>
                  <th>Phần thưởng</th>
                  <th>Đã đọc / đã nhận</th>
                  <th>Hiệu lực</th>
                  <th>Trạng thái</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {list.data.messages.map((m) => (
                  <tr key={m.id}>
                    <td>
                      <b>{m.title}</b>
                      <div className="spark">
                        {CATEGORY[m.category] ?? m.category} · {m.sender} · bởi{' '}
                        {m.created_by}
                      </div>
                    </td>
                    <td>
                      {m.audience === 'all'
                        ? 'Toàn server'
                        : `${m.targets.length} người chơi`}
                    </td>
                    <td className="spark">
                      {m.rewards.length
                        ? m.rewards.map(rewardText).join(', ')
                        : '—'}
                    </td>
                    <td>
                      {number(m.read_count)} / {number(m.claim_count)}
                    </td>
                    <td className="spark">
                      {dateTime(m.created_at)}
                      <br />→ {dateTime(m.expires_at)}
                    </td>
                    <td>
                      {m.phase === 'recalled' ? (
                        <span className="badge red">Đã thu hồi</span>
                      ) : (
                        <Phase value={m.phase} />
                      )}
                    </td>
                    <td>
                      {can('liveops') && m.status === 'active' && (
                        <button
                          className="btn small ghost"
                          onClick={() => recall(m)}
                        >
                          Thu hồi
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      {draft && (
        <Modal title="Soạn thư" onClose={() => setDraft(null)} wide>
          <div className="form cols">
            <Field label="Tiêu đề">
              <input
                className="input"
                maxLength={80}
                value={draft.title}
                onChange={(e) => setDraft({ ...draft, title: e.target.value })}
              />
            </Field>
            <Field label="Loại thư" hint="Biểu tượng trong hộp thư của game">
              <select
                className="input"
                value={draft.category}
                onChange={(e) =>
                  setDraft({ ...draft, category: e.target.value })
                }
              >
                {Object.entries(CATEGORY).map(([key, label]) => (
                  <option key={key} value={key}>
                    {label}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Người gửi">
              <input
                className="input"
                maxLength={40}
                value={draft.sender}
                onChange={(e) => setDraft({ ...draft, sender: e.target.value })}
              />
            </Field>
            <Field label="Hết hạn sau (ngày)">
              <input
                className="input"
                type="number"
                min={1}
                max={365}
                value={draft.expires_days}
                onChange={(e) =>
                  setDraft({ ...draft, expires_days: Number(e.target.value) })
                }
              />
            </Field>
            <Field label="Nội dung" full>
              <textarea
                className="input"
                rows={5}
                maxLength={2000}
                value={draft.body}
                onChange={(e) => setDraft({ ...draft, body: e.target.value })}
              />
            </Field>
            <Field label="Người nhận" full>
              <div className="toolbar">
                <label className="check">
                  <input
                    type="radio"
                    checked={draft.audience === 'all'}
                    onChange={() => setDraft({ ...draft, audience: 'all' })}
                  />
                  <span>Toàn server</span>
                </label>
                <label className="check">
                  <input
                    type="radio"
                    checked={draft.audience === 'players'}
                    onChange={() => setDraft({ ...draft, audience: 'players' })}
                  />
                  <span>Người chơi chỉ định</span>
                </label>
              </div>
              {draft.audience === 'players' && (
                <>
                  <div className="toolbar">
                    <input
                      className="input grow"
                      placeholder="Tên, tên đăng nhập hoặc ID…"
                      value={search}
                      onChange={(e) => setSearch(e.target.value)}
                      onKeyDown={(e) => e.key === 'Enter' && findPlayers()}
                    />
                    <button className="btn secondary" onClick={findPlayers}>
                      Tìm
                    </button>
                  </div>
                  {found.length > 0 && (
                    <div className="list">
                      {found.map((p) => (
                        <div key={p.id}>
                          <span className="grow">
                            {p.name}{' '}
                            <span className="spark">
                              {p.username ?? 'khách'} · {p.id.slice(0, 8)}
                            </span>
                          </span>
                          <button
                            className="btn small"
                            disabled={draft.targets.some((t) => t.id === p.id)}
                            onClick={() =>
                              setDraft({
                                ...draft,
                                targets: [...draft.targets, p],
                              })
                            }
                          >
                            Thêm
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                  <div className="toolbar">
                    {draft.targets.length === 0 && (
                      <span className="muted">Chưa chọn người nhận</span>
                    )}
                    {draft.targets.map((p) => (
                      <button
                        key={p.id}
                        className="btn small ghost"
                        title="Bỏ người này"
                        onClick={() =>
                          setDraft({
                            ...draft,
                            targets: draft.targets.filter((t) => t.id !== p.id),
                          })
                        }
                      >
                        {p.name} ✕
                      </button>
                    ))}
                  </div>
                </>
              )}
            </Field>
            <Field label="Phần thưởng đính kèm" hint="Tối đa 6 món" full>
              {draft.rewards.map((reward, index) => (
                <div className="toolbar" key={index}>
                  <select
                    className="input"
                    value={reward.type}
                    onChange={(e) =>
                      setReward(index, {
                        type: e.target.value as Reward['type'],
                        item_id: undefined,
                      })
                    }
                  >
                    <option value="gold">Vàng</option>
                    <option value="gem">Kim cương</option>
                    <option value="item">Vật phẩm</option>
                  </select>
                  {reward.type === 'item' && (
                    <select
                      className="input grow"
                      value={reward.item_id ?? ''}
                      onChange={(e) =>
                        setReward(index, { item_id: e.target.value })
                      }
                    >
                      <option value="">Chọn vật phẩm…</option>
                      {items.map((item) => (
                        <option key={item.id} value={item.id}>
                          {item.name} ({item.id})
                        </option>
                      ))}
                    </select>
                  )}
                  <input
                    className="input"
                    type="number"
                    min={1}
                    value={reward.amount}
                    onChange={(e) =>
                      setReward(index, { amount: Number(e.target.value) })
                    }
                    aria-label="Số lượng"
                  />
                  <button
                    className="btn small ghost"
                    onClick={() =>
                      setDraft({
                        ...draft,
                        rewards: draft.rewards.filter((_, i) => i !== index),
                      })
                    }
                  >
                    Bỏ
                  </button>
                </div>
              ))}
              {draft.rewards.length < 6 && (
                <button
                  className="btn small secondary"
                  onClick={() =>
                    setDraft({
                      ...draft,
                      rewards: [
                        ...draft.rewards,
                        { type: 'gold', amount: 1000 },
                      ],
                    })
                  }
                >
                  + Thêm phần thưởng
                </button>
              )}
            </Field>
          </div>
          <div className="modal-actions">
            <button className="btn ghost" onClick={() => setDraft(null)}>
              Hủy
            </button>
            <button className="btn" onClick={send} disabled={!ready}>
              {draft.audience === 'all' ? 'Gửi toàn server' : 'Gửi thư'}
            </button>
          </div>
        </Modal>
      )}
      {reasonModal}
    </Layout>
  );
}
