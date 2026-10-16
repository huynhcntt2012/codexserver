import { useState } from 'react';
import ItemPicker from '@/components/ItemPicker';
import Layout from '@/components/Layout';
import { Card, Empty, Field, Loading, Modal, Phase } from '@/components/ui';
import { api } from '@/lib/api';
import {
  dateTime,
  EVENT_KIND,
  fromLocalInput,
  toLocalInput,
} from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

type GameEvent = {
  id: string;
  name: string;
  kind: string;
  description: string;
  status: string;
  phase: string;
  start_at: string;
  end_at: string;
  reward_items: string[];
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
  reward_items: string[];
};

const STEPS = ['Thông tin cơ bản', 'Phần thưởng', 'Thời gian & xuất bản'];

function blank(): Draft {
  const start = new Date();
  start.setMinutes(0, 0, 0);
  start.setHours(start.getHours() + 1);
  const end = new Date(start.getTime() + 7 * 86400000);
  return {
    name: '',
    kind: 'login',
    description: '',
    start_at: toLocalInput(start),
    end_at: toLocalInput(end),
    reward_items: [],
  };
}

export default function Events() {
  const { can, toast } = useSession();
  const [draft, setDraft] = useState<Draft | null>(null);
  const [step, setStep] = useState(0);
  const list = useLoad(() => api<{ events: GameEvent[] }>('/events'));

  async function save(publish: boolean) {
    if (!draft) return;
    const body = {
      name: draft.name,
      kind: draft.kind,
      description: draft.description,
      start_at: fromLocalInput(draft.start_at),
      end_at: fromLocalInput(draft.end_at),
      reward_items: draft.reward_items,
    };
    try {
      const saved = draft.id
        ? await api<GameEvent>(`/events/${draft.id}`, { method: 'PUT', body })
        : await api<GameEvent>('/events', { method: 'POST', body });
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
          pause: 'Đã tạm dừng',
          resume: 'Đã tiếp tục',
        }[action],
      );
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  return (
    <Layout
      title="Quản lý sự kiện"
      subtitle="Tạo bản nháp, lên lịch, phát hành và tạm dừng sự kiện."
      actions={
        can('liveops') && (
          <button
            className="btn warn"
            onClick={() => {
              setStep(0);
              setDraft(blank());
            }}
          >
            + Tạo sự kiện
          </button>
        )
      }
    >
      <div className="notice info">
        Lịch và trạng thái sự kiện được lưu thật. Việc tự động phát thưởng theo
        điều kiện (đăng nhập, kết quả trận) cần worker và dữ liệu trận ở giai
        đoạn sau, nên hiện chưa có thống kê tham gia.
      </div>
      <Card title="Danh sách sự kiện">
        {!list.data ? (
          <Loading error={list.error} />
        ) : list.data.events.length === 0 ? (
          <Empty title="Chưa có sự kiện">Bấm “Tạo sự kiện” để bắt đầu.</Empty>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Sự kiện</th>
                  <th>Loại</th>
                  <th>Bắt đầu</th>
                  <th>Kết thúc</th>
                  <th>Quà</th>
                  <th>Trạng thái</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {list.data.events.map((event) => (
                  <tr key={event.id}>
                    <td>
                      <b>{event.name}</b>
                      <div className="spark">{event.description}</div>
                    </td>
                    <td>{EVENT_KIND[event.kind] ?? event.kind}</td>
                    <td>{dateTime(event.start_at)}</td>
                    <td>{dateTime(event.end_at)}</td>
                    <td>{event.reward_items.length}</td>
                    <td>
                      <Phase value={event.phase} />
                    </td>
                    <td>
                      {can('liveops') && (
                        <div className="toolbar">
                          {event.phase !== 'running' && (
                            <button
                              className="btn small secondary"
                              onClick={() => {
                                setStep(0);
                                setDraft({
                                  id: event.id,
                                  name: event.name,
                                  kind: event.kind,
                                  description: event.description,
                                  start_at: toLocalInput(event.start_at),
                                  end_at: toLocalInput(event.end_at),
                                  reward_items: event.reward_items,
                                });
                              }}
                            >
                              Sửa
                            </button>
                          )}
                          {event.status === 'draft' && (
                            <button
                              className="btn small success"
                              onClick={() => act(event, 'publish')}
                            >
                              Phát hành
                            </button>
                          )}
                          {event.status === 'published' &&
                            event.phase !== 'ended' && (
                              <button
                                className="btn small warn"
                                onClick={() => act(event, 'pause')}
                              >
                                Tạm dừng
                              </button>
                            )}
                          {event.status === 'paused' && (
                            <button
                              className="btn small success"
                              onClick={() => act(event, 'resume')}
                            >
                              Tiếp tục
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
      {draft && (
        <Modal
          title={draft.id ? 'Sửa sự kiện' : 'Tạo sự kiện mới'}
          onClose={() => setDraft(null)}
          wide
        >
          <div className="tabs">
            {STEPS.map((label, i) => (
              <button
                key={label}
                className={step === i ? 'active' : ''}
                onClick={() => setStep(i)}
              >
                {i + 1}. {label}
              </button>
            ))}
          </div>
          {step === 0 && (
            <div className="form">
              <Field label="Tên sự kiện">
                <input
                  className="input"
                  maxLength={80}
                  value={draft.name}
                  onChange={(e) => setDraft({ ...draft, name: e.target.value })}
                />
              </Field>
              <Field label="Loại sự kiện">
                <div className="chips">
                  {Object.entries(EVENT_KIND).map(([key, label]) => (
                    <button
                      key={key}
                      type="button"
                      className={`btn small ${draft.kind === key ? '' : 'ghost'}`}
                      onClick={() => setDraft({ ...draft, kind: key })}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              </Field>
              <Field label="Mô tả sự kiện">
                <textarea
                  className="input"
                  maxLength={500}
                  value={draft.description}
                  onChange={(e) =>
                    setDraft({ ...draft, description: e.target.value })
                  }
                />
              </Field>
            </div>
          )}
          {step === 1 && (
            <Field
              label="Vật phẩm thưởng"
              hint="Tối đa 10 vật phẩm trong danh mục."
            >
              <ItemPicker
                value={draft.reward_items}
                onChange={(ids) =>
                  setDraft({ ...draft, reward_items: ids.slice(0, 10) })
                }
              />
            </Field>
          )}
          {step === 2 && (
            <div className="form cols">
              <Field label="Bắt đầu (giờ máy bạn)">
                <input
                  className="input"
                  type="datetime-local"
                  value={draft.start_at}
                  onChange={(e) =>
                    setDraft({ ...draft, start_at: e.target.value })
                  }
                />
              </Field>
              <Field label="Kết thúc">
                <input
                  className="input"
                  type="datetime-local"
                  value={draft.end_at}
                  onChange={(e) =>
                    setDraft({ ...draft, end_at: e.target.value })
                  }
                />
              </Field>
              <div className="notice info full">
                “Lưu & phát hành” đưa sự kiện vào lịch: trước giờ bắt đầu là “Đã
                lên lịch”, trong khoảng thời gian là “Đang chạy”.
              </div>
            </div>
          )}
          <div className="modal-actions">
            {step > 0 && (
              <button className="btn ghost" onClick={() => setStep(step - 1)}>
                ‹ Quay lại
              </button>
            )}
            <span className="grow" />
            <button
              className="btn secondary"
              onClick={() => save(false)}
              disabled={draft.name.trim().length < 3}
            >
              Lưu bản nháp
            </button>
            {step < STEPS.length - 1 ? (
              <button className="btn" onClick={() => setStep(step + 1)}>
                Tiếp theo ›
              </button>
            ) : (
              <button
                className="btn success"
                onClick={() => save(true)}
                disabled={draft.name.trim().length < 3}
              >
                Lưu & phát hành
              </button>
            )}
          </div>
        </Modal>
      )}
    </Layout>
  );
}
