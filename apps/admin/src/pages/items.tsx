import { useState } from 'react';
import Layout from '@/components/Layout';
import {
  Card,
  Empty,
  Field,
  Loading,
  Modal,
  Phase,
  Rarity,
  Thumb,
} from '@/components/ui';
import { api, upload } from '@/lib/api';
import { CATEGORY, dateTime, iconUrl, number, RARITY } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

export type Item = {
  id: string;
  name: string;
  category: string;
  rarity: string;
  description: string;
  price: number;
  currency: 'gold' | 'gem';
  duration_days: number | null;
  icon: string | null;
  icon_sha256: string | null;
  status: string;
  updated_by: string;
  updated_at: string;
  owners: number;
};

const BLANK = {
  id: '',
  name: '',
  category: 'outfit',
  rarity: 'common',
  description: '',
  price: 0,
  currency: 'gold' as 'gold' | 'gem',
  duration_days: null as number | null,
  icon: '',
};

export default function Items() {
  const { can, toast } = useSession();
  const [q, setQ] = useState('');
  const [category, setCategory] = useState('');
  const [status, setStatus] = useState('');
  const [editing, setEditing] = useState<
    (typeof BLANK & { existing?: boolean }) | null
  >(null);
  const list = useLoad(
    () =>
      api<{ items: Item[] }>(
        `/items?q=${encodeURIComponent(q)}&category=${category}&status=${status}`,
      ),
    [q, category, status],
  );

  async function save() {
    if (!editing) return;
    const body = {
      name: editing.name,
      category: editing.category,
      rarity: editing.rarity,
      description: editing.description,
      price: Number(editing.price),
      currency: editing.currency,
      duration_days: editing.duration_days
        ? Number(editing.duration_days)
        : null,
      icon: editing.icon || null,
    };
    try {
      if (editing.existing)
        await api(`/items/${editing.id}`, { method: 'PATCH', body });
      else
        await api('/items', {
          method: 'POST',
          body: { ...body, id: editing.id },
        });
      toast(
        editing.existing ? 'Đã lưu thay đổi' : 'Đã tạo vật phẩm (bản nháp)',
      );
      setEditing(null);
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function uploadIcon(item: Item, file: File) {
    try {
      await upload(`/items/${item.id}/icon`, file);
      toast('Đã cập nhật ảnh; client sẽ tải ảnh mới ở lần đồng bộ tới');
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function setItemStatus(item: Item, action: 'publish' | 'hide') {
    try {
      await api(`/items/${item.id}/${action}`, { method: 'POST' });
      toast(action === 'publish' ? 'Đã phát hành' : 'Đã ẩn vật phẩm');
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  return (
    <Layout
      title="Quản lý vật phẩm"
      subtitle="Danh mục vật phẩm: tạo bản nháp, chỉnh sửa, phát hành hoặc ẩn."
      actions={
        can('liveops') && (
          <button className="btn warn" onClick={() => setEditing({ ...BLANK })}>
            + Vật phẩm mới
          </button>
        )
      }
    >
      <Card>
        <div className="toolbar">
          <input
            className="input grow"
            placeholder="Tìm theo tên hoặc ID…"
            value={q}
            onChange={(e) => setQ(e.target.value)}
            aria-label="Tìm vật phẩm"
          />
          <select
            className="input"
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            aria-label="Loại"
          >
            <option value="">Tất cả loại</option>
            {Object.entries(CATEGORY).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </select>
          <select
            className="input"
            value={status}
            onChange={(e) => setStatus(e.target.value)}
            aria-label="Trạng thái"
          >
            <option value="">Mọi trạng thái</option>
            <option value="draft">Bản nháp</option>
            <option value="published">Đã phát hành</option>
            <option value="hidden">Đang ẩn</option>
          </select>
        </div>
      </Card>
      <Card
        title={list.data ? `${list.data.items.length} vật phẩm` : 'Vật phẩm'}
      >
        {!list.data ? (
          <Loading error={list.error} />
        ) : list.data.items.length === 0 ? (
          <Empty title="Chưa có vật phẩm phù hợp" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Vật phẩm</th>
                  <th>Loại</th>
                  <th>Độ hiếm</th>
                  <th>Giá</th>
                  <th>Thời hạn</th>
                  <th>Người sở hữu</th>
                  <th>Trạng thái</th>
                  <th>Cập nhật</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {list.data.items.map((item) => (
                  <tr key={item.id}>
                    <td>
                      <div className="check">
                        <Thumb icon={item.icon} sha={item.icon_sha256} />
                        <div>
                          <b>{item.name}</b>
                          <div className="spark">{item.id}</div>
                        </div>
                      </div>
                    </td>
                    <td>{CATEGORY[item.category] ?? item.category}</td>
                    <td>
                      <Rarity value={item.rarity} />
                    </td>
                    <td>
                      {number(item.price)}{' '}
                      {item.currency === 'gem' ? '💎' : '🪙'}
                    </td>
                    <td>
                      {item.duration_days
                        ? `${item.duration_days} ngày`
                        : 'Vĩnh viễn'}
                    </td>
                    <td>{number(item.owners)}</td>
                    <td>
                      <Phase value={item.status} />
                    </td>
                    <td className="spark">
                      {item.updated_by}
                      <br />
                      {dateTime(item.updated_at)}
                    </td>
                    <td>
                      {can('liveops') && (
                        <div className="toolbar">
                          <button
                            className="btn small secondary"
                            onClick={() =>
                              setEditing({
                                ...item,
                                icon: item.icon ?? '',
                                existing: true,
                              })
                            }
                          >
                            Sửa
                          </button>
                          <label className="btn small ghost upload">
                            Ảnh
                            <input
                              type="file"
                              accept="image/png"
                              aria-label={`Tải ảnh PNG cho ${item.name}`}
                              onChange={(e) => {
                                const file = e.target.files?.[0];
                                e.target.value = '';
                                if (file) uploadIcon(item, file);
                              }}
                            />
                          </label>
                          {item.status === 'published' ? (
                            <button
                              className="btn small ghost"
                              onClick={() => setItemStatus(item, 'hide')}
                            >
                              Ẩn
                            </button>
                          ) : (
                            <button
                              className="btn small success"
                              onClick={() => setItemStatus(item, 'publish')}
                            >
                              Phát hành
                            </button>
                          )}
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      {editing && (
        <Modal
          title={editing.existing ? `Sửa: ${editing.name}` : 'Vật phẩm mới'}
          onClose={() => setEditing(null)}
          wide
        >
          <div className="grid two">
            <div className="form cols">
              <Field
                label="ID vật phẩm"
                hint="a-z, 0-9, _ · không đổi được sau khi tạo"
              >
                <input
                  className="input"
                  value={editing.id}
                  disabled={editing.existing}
                  onChange={(e) =>
                    setEditing({ ...editing, id: e.target.value.toLowerCase() })
                  }
                />
              </Field>
              <Field label="Tên vật phẩm">
                <input
                  className="input"
                  value={editing.name}
                  maxLength={80}
                  onChange={(e) =>
                    setEditing({ ...editing, name: e.target.value })
                  }
                />
              </Field>
              <Field label="Loại">
                <select
                  className="input"
                  value={editing.category}
                  onChange={(e) =>
                    setEditing({ ...editing, category: e.target.value })
                  }
                >
                  {Object.entries(CATEGORY).map(([key, label]) => (
                    <option key={key} value={key}>
                      {label}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Độ hiếm">
                <select
                  className="input"
                  value={editing.rarity}
                  onChange={(e) =>
                    setEditing({ ...editing, rarity: e.target.value })
                  }
                >
                  {Object.entries(RARITY).map(([key, [label]]) => (
                    <option key={key} value={key}>
                      {label}
                    </option>
                  ))}
                </select>
              </Field>
              <Field label="Giá">
                <input
                  className="input"
                  type="number"
                  min={0}
                  value={editing.price}
                  onChange={(e) =>
                    setEditing({ ...editing, price: Number(e.target.value) })
                  }
                />
              </Field>
              <Field label="Tiền tệ">
                <select
                  className="input"
                  value={editing.currency}
                  onChange={(e) =>
                    setEditing({
                      ...editing,
                      currency: e.target.value as 'gold' | 'gem',
                    })
                  }
                >
                  <option value="gold">Vàng</option>
                  <option value="gem">Kim cương</option>
                </select>
              </Field>
              <Field label="Thời hạn (ngày)" hint="Để trống = vĩnh viễn">
                <input
                  className="input"
                  type="number"
                  min={1}
                  value={editing.duration_days ?? ''}
                  onChange={(e) =>
                    setEditing({
                      ...editing,
                      duration_days: e.target.value
                        ? Number(e.target.value)
                        : null,
                    })
                  }
                />
              </Field>
              <Field
                label="Ảnh (đường dẫn trong game)"
                hint="Ví dụ items/heart.png"
              >
                <input
                  className="input"
                  value={editing.icon}
                  onChange={(e) =>
                    setEditing({ ...editing, icon: e.target.value })
                  }
                />
              </Field>
              <Field label="Mô tả" full>
                <textarea
                  className="input"
                  maxLength={200}
                  value={editing.description}
                  onChange={(e) =>
                    setEditing({ ...editing, description: e.target.value })
                  }
                />
              </Field>
            </div>
            <Card title="Xem trước">
              <div className="empty">
                {iconUrl(editing.icon) ? (
                  <img
                    src={iconUrl(editing.icon) ?? ''}
                    alt=""
                    width={140}
                    height={140}
                  />
                ) : (
                  <span className="muted">Chưa có ảnh</span>
                )}
                <b>{editing.name || 'Tên vật phẩm'}</b>
                <div>
                  <Rarity value={editing.rarity} /> {CATEGORY[editing.category]}
                </div>
                <p>
                  {number(editing.price)}{' '}
                  {editing.currency === 'gem' ? 'kim cương' : 'vàng'}
                </p>
                <p className="spark">{editing.description}</p>
              </div>
            </Card>
          </div>
          <div className="modal-actions">
            <button className="btn ghost" onClick={() => setEditing(null)}>
              Hủy
            </button>
            <button className="btn" onClick={save}>
              {editing.existing ? 'Lưu thay đổi' : 'Tạo bản nháp'}
            </button>
          </div>
        </Modal>
      )}
    </Layout>
  );
}
