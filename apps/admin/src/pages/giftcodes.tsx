import { useState } from 'react';
import ItemPicker from '@/components/ItemPicker';
import Layout from '@/components/Layout';
import { Card, Empty, Field, Loading, Modal, Phase } from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime, fromLocalInput, number, toLocalInput } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

type Giftcode = {
  id: string;
  code: string;
  name: string;
  reward_items: string[];
  max_redemptions: number;
  used: number;
  starts_at: string;
  expires_at: string;
  status: string;
  phase: string;
  created_by: string;
};

export default function Giftcodes() {
  const { can, toast } = useSession();
  const [q, setQ] = useState('');
  const [creating, setCreating] = useState<{
    code: string;
    name: string;
    reward_items: string[];
    max_redemptions: number;
    expires_at: string;
  } | null>(null);
  const [viewing, setViewing] = useState<Giftcode | null>(null);
  const list = useLoad(
    () =>
      api<{ giftcodes: Giftcode[] }>(`/giftcodes?q=${encodeURIComponent(q)}`),
    [q],
  );
  const users = useLoad(
    () =>
      viewing
        ? api<{
            redemptions: {
              account_id: string;
              name: string;
              created_at: string;
            }[];
          }>(`/giftcodes/${viewing.id}/redemptions`)
        : Promise.resolve({ redemptions: [] }),
    [viewing?.id],
  );

  async function create() {
    if (!creating) return;
    try {
      const saved = await api<Giftcode>('/giftcodes', {
        method: 'POST',
        body: {
          code: creating.code.trim() || null,
          name: creating.name,
          reward_items: creating.reward_items,
          max_redemptions: Number(creating.max_redemptions),
          expires_at: fromLocalInput(creating.expires_at),
        },
      });
      toast(`Đã tạo giftcode ${saved.code}`);
      setCreating(null);
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function toggle(code: Giftcode) {
    try {
      await api(
        `/giftcodes/${code.id}/${code.status === 'active' ? 'disable' : 'enable'}`,
        { method: 'POST' },
      );
      toast(code.status === 'active' ? 'Đã tắt giftcode' : 'Đã bật giftcode');
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  return (
    <Layout
      title="Quản lý giftcode"
      subtitle="Tạo mã quà tặng, giới hạn lượt, theo dõi người đã nhập."
      actions={
        can('liveops') && (
          <button
            className="btn warn"
            onClick={() =>
              setCreating({
                code: '',
                name: '',
                reward_items: [],
                max_redemptions: 1000,
                expires_at: toLocalInput(new Date(Date.now() + 30 * 86400000)),
              })
            }
          >
            + Tạo giftcode
          </button>
        )
      }
    >
      <div className="notice info">
        Người chơi nhập mã qua <code>POST /v1/giftcodes/redeem</code>: mỗi tài
        khoản nhập một lần, vật phẩm thưởng vào thẳng kho đồ. Chưa có ví
        vàng/kim cương thật nên quà chỉ là vật phẩm.
      </div>
      <Card>
        <input
          className="input"
          placeholder="Tìm mã hoặc tên…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          aria-label="Tìm giftcode"
        />
      </Card>
      <Card title="Danh sách giftcode">
        {!list.data ? (
          <Loading error={list.error} />
        ) : list.data.giftcodes.length === 0 ? (
          <Empty title="Chưa có giftcode" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Mã</th>
                  <th>Nội dung</th>
                  <th>Đã dùng / giới hạn</th>
                  <th>Hiệu lực</th>
                  <th>Trạng thái</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {list.data.giftcodes.map((code) => (
                  <tr key={code.id}>
                    <td>
                      <b>{code.code}</b>
                      <div className="spark">bởi {code.created_by}</div>
                    </td>
                    <td>
                      {code.name}
                      <div className="spark">
                        {code.reward_items.join(', ')}
                      </div>
                    </td>
                    <td>
                      {number(code.used)} / {number(code.max_redemptions)}
                    </td>
                    <td className="spark">
                      {dateTime(code.starts_at)}
                      <br />→ {dateTime(code.expires_at)}
                    </td>
                    <td>
                      <Phase value={code.phase} />
                    </td>
                    <td>
                      <div className="toolbar">
                        <button
                          className="btn small secondary"
                          onClick={() => setViewing(code)}
                        >
                          Người đã nhập
                        </button>
                        {can('liveops') && (
                          <button
                            className={`btn small ${code.status === 'active' ? 'ghost' : 'success'}`}
                            onClick={() => toggle(code)}
                          >
                            {code.status === 'active' ? 'Tắt' : 'Bật'}
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
      </Card>
      {creating && (
        <Modal title="Tạo giftcode mới" onClose={() => setCreating(null)} wide>
          <div className="form cols">
            <Field
              label="Mã giftcode"
              hint="Để trống để tạo ngẫu nhiên dạng BUP-XXXXXXXX"
            >
              <input
                className="input"
                maxLength={32}
                value={creating.code}
                onChange={(e) =>
                  setCreating({
                    ...creating,
                    code: e.target.value
                      .toUpperCase()
                      .replace(/[^A-Z0-9-]/g, ''),
                  })
                }
              />
            </Field>
            <Field label="Tên / ghi chú">
              <input
                className="input"
                maxLength={80}
                value={creating.name}
                onChange={(e) =>
                  setCreating({ ...creating, name: e.target.value })
                }
              />
            </Field>
            <Field label="Số lượt tối đa">
              <input
                className="input"
                type="number"
                min={1}
                value={creating.max_redemptions}
                onChange={(e) =>
                  setCreating({
                    ...creating,
                    max_redemptions: Number(e.target.value),
                  })
                }
              />
            </Field>
            <Field label="Hạn sử dụng">
              <input
                className="input"
                type="datetime-local"
                value={creating.expires_at}
                onChange={(e) =>
                  setCreating({ ...creating, expires_at: e.target.value })
                }
              />
            </Field>
            <Field label="Vật phẩm thưởng" full>
              <ItemPicker
                value={creating.reward_items}
                onChange={(ids) =>
                  setCreating({ ...creating, reward_items: ids.slice(0, 10) })
                }
              />
            </Field>
          </div>
          <div className="modal-actions">
            <button className="btn ghost" onClick={() => setCreating(null)}>
              Hủy
            </button>
            <button
              className="btn"
              onClick={create}
              disabled={
                creating.name.trim().length < 3 ||
                creating.reward_items.length === 0
              }
            >
              Tạo giftcode
            </button>
          </div>
        </Modal>
      )}
      {viewing && (
        <Modal
          title={`Người đã nhập ${viewing.code}`}
          onClose={() => setViewing(null)}
        >
          {!users.data ? (
            <Loading error={users.error} />
          ) : users.data.redemptions.length === 0 ? (
            <Empty title="Chưa ai nhập mã này" />
          ) : (
            <div className="list">
              {users.data.redemptions.map((r) => (
                <div key={r.account_id}>
                  <a
                    className="grow"
                    href={`/admin/players/?id=${r.account_id}`}
                  >
                    {r.name}
                  </a>
                  <span className="spark">{dateTime(r.created_at)}</span>
                </div>
              ))}
            </div>
          )}
        </Modal>
      )}
    </Layout>
  );
}
