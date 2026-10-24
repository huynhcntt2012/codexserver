import { useState } from 'react';
import Layout from '@/components/Layout';
import {
  Card,
  Empty,
  Field,
  Loading,
  Modal,
  Phase,
  Thumb,
} from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime, fromLocalInput, number } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';
import type { Item } from './items';

type Offer = {
  id: string;
  item_id: string;
  item_name: string;
  icon: string | null;
  price: number;
  final_price: number;
  currency: string;
  discount_percent: number;
  status: string;
  phase: string;
  start_at: string;
  end_at: string | null;
  updated_by: string;
};

export default function Shop() {
  const { can, toast } = useSession();
  const list = useLoad(() => api<{ offers: Offer[] }>('/shop/offers'));
  const catalog = useLoad(() => api<{ items: Item[] }>('/items'));
  const [draft, setDraft] = useState<{
    item_id: string;
    price: number;
    currency: string;
    discount_percent: number;
    end_at: string;
  } | null>(null);

  async function create() {
    if (!draft) return;
    try {
      await api('/shop/offers', {
        method: 'POST',
        body: {
          item_id: draft.item_id,
          price: Number(draft.price),
          currency: draft.currency,
          discount_percent: Number(draft.discount_percent),
          end_at: draft.end_at ? fromLocalInput(draft.end_at) : null,
        },
      });
      toast('Đã tạo ưu đãi (bản nháp)');
      setDraft(null);
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function act(offer: Offer, action: 'publish' | 'pause') {
    try {
      await api(`/shop/offers/${offer.id}/${action}`, { method: 'POST' });
      toast(action === 'publish' ? 'Đã mở bán' : 'Đã dừng bán');
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  return (
    <Layout
      title="Quản lý shop"
      subtitle="Lên kệ vật phẩm, giá, giảm giá và thời gian bán."
      actions={
        can('liveops') && (
          <button
            className="btn warn"
            onClick={() =>
              setDraft({
                item_id: '',
                price: 0,
                currency: 'gold',
                discount_percent: 0,
                end_at: '',
              })
            }
          >
            + Ưu đãi mới
          </button>
        )
      }
    >
      <div className="notice">
        Chưa có ví vàng/kim cương phía server và không có thanh toán thật ở giai
        đoạn này, nên chưa có đơn hàng. Danh sách đang bán được công bố tại{' '}
        <code>GET /v1/shop/offers</code>.
      </div>
      <Card title="Ưu đãi">
        {!list.data ? (
          <Loading error={list.error} />
        ) : list.data.offers.length === 0 ? (
          <Empty title="Chưa có ưu đãi nào" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Vật phẩm</th>
                  <th>Giá gốc</th>
                  <th>Giảm</th>
                  <th>Giá bán</th>
                  <th>Thời gian</th>
                  <th>Trạng thái</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {list.data.offers.map((offer) => (
                  <tr key={offer.id}>
                    <td>
                      <div className="check">
                        <Thumb icon={offer.icon} />
                        <b>{offer.item_name}</b>
                      </div>
                    </td>
                    <td>{number(offer.price)}</td>
                    <td>
                      {offer.discount_percent
                        ? `${offer.discount_percent}%`
                        : '—'}
                    </td>
                    <td>
                      <b>{number(offer.final_price)}</b>{' '}
                      {offer.currency === 'gem' ? '💎' : '🪙'}
                    </td>
                    <td className="spark">
                      {dateTime(offer.start_at)}
                      <br />→{' '}
                      {offer.end_at ? dateTime(offer.end_at) : 'không giới hạn'}
                    </td>
                    <td>
                      <Phase value={offer.phase} />
                    </td>
                    <td>
                      {can('liveops') &&
                        (offer.status === 'published' ? (
                          <button
                            className="btn small ghost"
                            onClick={() => act(offer, 'pause')}
                          >
                            Dừng bán
                          </button>
                        ) : (
                          <button
                            className="btn small success"
                            onClick={() => act(offer, 'publish')}
                          >
                            Mở bán
                          </button>
                        ))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      {draft && (
        <Modal title="Ưu đãi mới" onClose={() => setDraft(null)}>
          <div className="form cols">
            <Field
              label="Vật phẩm"
              full
              hint="Chỉ mở bán được vật phẩm đã phát hành."
            >
              <select
                className="input"
                value={draft.item_id}
                onChange={(e) => {
                  const item = catalog.data?.items.find(
                    (i) => i.id === e.target.value,
                  );
                  setDraft({
                    ...draft,
                    item_id: e.target.value,
                    price: item?.price ?? 0,
                    currency: item?.currency ?? 'gold',
                  });
                }}
              >
                <option value="">Chọn vật phẩm…</option>
                {(catalog.data?.items ?? []).map((i) => (
                  <option key={i.id} value={i.id}>
                    {i.name}{' '}
                    {i.status !== 'published' ? '(chưa phát hành)' : ''}
                  </option>
                ))}
              </select>
            </Field>
            <Field label="Giá">
              <input
                className="input"
                type="number"
                min={0}
                value={draft.price}
                onChange={(e) =>
                  setDraft({ ...draft, price: Number(e.target.value) })
                }
              />
            </Field>
            <Field label="Tiền tệ">
              <select
                className="input"
                value={draft.currency}
                onChange={(e) =>
                  setDraft({ ...draft, currency: e.target.value })
                }
              >
                <option value="gold">Vàng</option>
                <option value="gem">Kim cương</option>
              </select>
            </Field>
            <Field label="Giảm giá (%)">
              <input
                className="input"
                type="number"
                min={0}
                max={90}
                value={draft.discount_percent}
                onChange={(e) =>
                  setDraft({
                    ...draft,
                    discount_percent: Number(e.target.value),
                  })
                }
              />
            </Field>
            <Field label="Kết thúc bán" hint="Để trống = không giới hạn">
              <input
                className="input"
                type="datetime-local"
                value={draft.end_at}
                onChange={(e) => setDraft({ ...draft, end_at: e.target.value })}
              />
            </Field>
          </div>
          <div className="modal-actions">
            <button className="btn ghost" onClick={() => setDraft(null)}>
              Hủy
            </button>
            <button className="btn" onClick={create} disabled={!draft.item_id}>
              Tạo bản nháp
            </button>
          </div>
        </Modal>
      )}
    </Layout>
  );
}
