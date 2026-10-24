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
import { Card, Empty, Field, Loading, Modal } from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

type Quest = {
  key: string;
  scope: 'daily' | 'weekly';
  title: string;
  description: string;
  objectives: Objective[];
  rewards: Reward[];
  enabled: boolean;
  sort: number;
  updated_by: string;
  updated_at: string;
};

const SCOPE = {
  daily: 'Hằng ngày (reset 00:00)',
  weekly: 'Hằng tuần (reset thứ Hai)',
};

export default function Quests() {
  const { can, toast } = useSession();
  const list = useLoad(() => api<{ quests: Quest[] }>('/quests'));
  const { mapIds, items } = useCatalog();
  const [editing, setEditing] = useState<
    (Quest & { existing: boolean }) | null
  >(null);

  async function save(quest: Quest) {
    try {
      const {
        key,
        scope,
        title,
        description,
        objectives,
        rewards,
        enabled,
        sort,
      } = quest;
      await api(`/quests/${key}`, {
        method: 'PUT',
        body: {
          key,
          scope,
          title,
          description,
          objectives,
          rewards,
          enabled,
          sort,
        },
      });
      toast(
        'Đã lưu nhiệm vụ; người chơi thấy ngay ở lần mở cửa sổ Nhiệm vụ tới',
      );
      setEditing(null);
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function seed() {
    try {
      const done = await api<{ added: number }>('/quests/seed', {
        method: 'POST',
      });
      toast(`Đã thêm ${done.added} nhiệm vụ mặc định`);
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  return (
    <Layout
      title="Nhiệm vụ"
      subtitle="Nhiệm vụ hằng ngày / hằng tuần. Tiến độ chỉ tăng từ trận do server ghi nhận."
      actions={
        can('liveops') && (
          <div className="toolbar">
            <button className="btn secondary" onClick={seed}>
              Thêm bộ mặc định (D01–D05, W01–W03)
            </button>
            <button
              className="btn warn"
              onClick={() =>
                setEditing({
                  key: '',
                  scope: 'daily',
                  title: '',
                  description: '',
                  objectives: [newObjective()],
                  rewards: [newReward()],
                  enabled: true,
                  sort: 10,
                  updated_by: '',
                  updated_at: '',
                  existing: false,
                })
              }
            >
              + Nhiệm vụ mới
            </button>
          </div>
        )
      }
    >
      {(['daily', 'weekly'] as const).map((scope) => {
        const rows = list.data?.quests.filter((q) => q.scope === scope) ?? [];
        return (
          <Card key={scope} title={SCOPE[scope]}>
            {!list.data ? (
              <Loading error={list.error} />
            ) : rows.length === 0 ? (
              <Empty title="Chưa có nhiệm vụ">
                Bấm “Thêm bộ mặc định” để bắt đầu.
              </Empty>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Mã</th>
                      <th>Nhiệm vụ</th>
                      <th>Điều kiện → thưởng</th>
                      <th>Trạng thái</th>
                      <th>Cập nhật</th>
                      <th />
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((quest) => (
                      <tr key={quest.key}>
                        <td>{quest.key}</td>
                        <td>
                          <b>{quest.title}</b>
                          <div className="spark">{quest.description}</div>
                        </td>
                        <td className="spark">
                          {summary(quest.objectives, quest.rewards)}
                        </td>
                        <td>
                          <span
                            className={`badge ${quest.enabled ? 'green' : ''}`}
                          >
                            {quest.enabled ? 'Đang bật' : 'Đang tắt'}
                          </span>
                        </td>
                        <td className="spark">
                          {quest.updated_by}
                          <br />
                          {dateTime(quest.updated_at)}
                        </td>
                        <td>
                          {can('liveops') && (
                            <div className="toolbar">
                              <button
                                className="btn small secondary"
                                onClick={() =>
                                  setEditing({ ...quest, existing: true })
                                }
                              >
                                Sửa
                              </button>
                              <button
                                className="btn small ghost"
                                onClick={() =>
                                  save({ ...quest, enabled: !quest.enabled })
                                }
                              >
                                {quest.enabled ? 'Tắt' : 'Bật'}
                              </button>
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
        );
      })}
      {editing && (
        <Modal
          title={
            editing.existing ? `Sửa nhiệm vụ ${editing.key}` : 'Nhiệm vụ mới'
          }
          onClose={() => setEditing(null)}
          wide
        >
          <div className="form cols">
            <Field
              label="Mã"
              hint="2–32 ký tự A-Z, 0-9, _; không đổi sau khi tạo"
            >
              <input
                className="input"
                value={editing.key}
                disabled={editing.existing}
                onChange={(e) =>
                  setEditing({ ...editing, key: e.target.value })
                }
              />
            </Field>
            <Field label="Chu kỳ">
              <select
                className="input"
                value={editing.scope}
                onChange={(e) =>
                  setEditing({
                    ...editing,
                    scope: e.target.value as Quest['scope'],
                  })
                }
              >
                <option value="daily">Hằng ngày</option>
                <option value="weekly">Hằng tuần</option>
              </select>
            </Field>
            <Field label="Tên">
              <input
                className="input"
                value={editing.title}
                onChange={(e) =>
                  setEditing({ ...editing, title: e.target.value })
                }
              />
            </Field>
            <Field label="Thứ tự">
              <input
                className="input"
                type="number"
                value={editing.sort}
                onChange={(e) =>
                  setEditing({ ...editing, sort: Number(e.target.value) })
                }
              />
            </Field>
            <Field label="Mô tả" full>
              <input
                className="input"
                value={editing.description}
                onChange={(e) =>
                  setEditing({ ...editing, description: e.target.value })
                }
              />
            </Field>
          </div>
          <QuestEditor
            objectives={editing.objectives}
            rewards={editing.rewards}
            allowToken={false}
            mapIds={mapIds}
            items={items}
            onChange={(objectives, rewards) =>
              setEditing({ ...editing, objectives, rewards })
            }
          />
          <div className="modal-actions">
            <button className="btn" onClick={() => save(editing)}>
              Lưu nhiệm vụ
            </button>
          </div>
        </Modal>
      )}
    </Layout>
  );
}
