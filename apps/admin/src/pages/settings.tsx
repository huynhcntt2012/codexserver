import { useRouter } from 'next/router';
import { useEffect, useState } from 'react';
import Layout from '@/components/Layout';
import { Card, Empty, Field, Loading, Modal } from '@/components/ui';
import { api } from '@/lib/api';
import { ACTION, dateTime, ROLE } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

type AdminRow = {
  id: string;
  username: string;
  role: string;
  mfa: boolean;
  disabled: boolean;
  last_login_at: string | null;
};
type Audit = {
  entries: {
    id: number;
    actor: string;
    action: string;
    target_type: string;
    target_id: string;
    reason: string;
    detail: Record<string, unknown>;
    created_at: string;
  }[];
};

export default function Settings() {
  const router = useRouter();
  const { can } = useSession();
  const [tab, setTab] = useState('me');
  useEffect(() => {
    if (typeof router.query.tab === 'string') setTab(router.query.tab);
  }, [router.query.tab]);
  const tabs = [
    ['me', 'Tài khoản của tôi'],
    ...(can('admins') ? [['admins', 'Quản trị viên']] : []),
    ['audit', 'Nhật ký audit'],
  ];
  return (
    <Layout
      title="Cài đặt"
      subtitle="Tài khoản quản trị, phân quyền và nhật ký thao tác."
    >
      <div className="tabs">
        {tabs.map(([key, label]) => (
          <button
            key={key}
            className={tab === key ? 'active' : ''}
            onClick={() => setTab(key)}
          >
            {label}
          </button>
        ))}
      </div>
      {tab === 'me' && <MyAccount />}
      {tab === 'admins' && can('admins') && <Admins />}
      {tab === 'audit' && <AuditLog />}
    </Layout>
  );
}

function MyAccount() {
  const { me, toast, refresh } = useSession();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [setup, setSetup] = useState<{ secret: string; uri: string } | null>(
    null,
  );
  const [otp, setOtp] = useState('');
  if (!me) return <Loading />;
  return (
    <div className="grid halves">
      <Card title="Đổi mật khẩu">
        <div className="form">
          <Field label="Mật khẩu hiện tại">
            <input
              className="input"
              type="password"
              autoComplete="current-password"
              value={current}
              onChange={(e) => setCurrent(e.target.value)}
            />
          </Field>
          <Field label="Mật khẩu mới" hint="Ít nhất 12 ký tự">
            <input
              className="input"
              type="password"
              autoComplete="new-password"
              value={next}
              onChange={(e) => setNext(e.target.value)}
            />
          </Field>
          <button
            className="btn"
            disabled={!current || next.length < 12}
            onClick={async () => {
              try {
                await api('/auth/password', {
                  method: 'POST',
                  body: { password: current, new_password: next },
                });
                setCurrent('');
                setNext('');
                toast('Đã đổi mật khẩu');
              } catch (reason) {
                toast((reason as Error).message, true);
              }
            }}
          >
            Đổi mật khẩu
          </button>
        </div>
      </Card>
      <Card title="Xác thực 2 lớp (MFA)">
        {me.mfa ? (
          <div className="notice info">
            MFA đang bật. Mỗi lần đăng nhập cần mã 6 số từ ứng dụng xác thực.
          </div>
        ) : !setup ? (
          <div className="form">
            <div className="notice">
              Nên bật MFA cho mọi tài khoản owner/operator. Dùng Google
              Authenticator, Microsoft Authenticator hoặc ứng dụng TOTP tương
              tự.
            </div>
            <button
              className="btn"
              onClick={async () => {
                try {
                  setSetup(await api('/auth/mfa/setup', { method: 'POST' }));
                } catch (reason) {
                  toast((reason as Error).message, true);
                }
              }}
            >
              Bắt đầu bật MFA
            </button>
          </div>
        ) : (
          <div className="form">
            <Field label="Khóa bí mật (nhập tay vào ứng dụng)">
              <input
                className="input"
                readOnly
                value={setup.secret}
                onFocus={(e) => e.target.select()}
              />
            </Field>
            <Field label="Hoặc liên kết otpauth">
              <input
                className="input"
                readOnly
                value={setup.uri}
                onFocus={(e) => e.target.select()}
              />
            </Field>
            <Field label="Mã 6 số trong ứng dụng">
              <input
                className="input"
                inputMode="numeric"
                maxLength={6}
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
              />
            </Field>
            <button
              className="btn success"
              disabled={otp.length !== 6}
              onClick={async () => {
                try {
                  await api('/auth/mfa/enable', {
                    method: 'POST',
                    body: { otp },
                  });
                  setSetup(null);
                  await refresh();
                  toast('Đã bật MFA');
                } catch (reason) {
                  toast((reason as Error).message, true);
                }
              }}
            >
              Xác nhận bật MFA
            </button>
          </div>
        )}
      </Card>
    </div>
  );
}

function Admins() {
  const { me, toast } = useSession();
  const list = useLoad(() => api<{ admins: AdminRow[] }>('/admins'));
  const [adding, setAdding] = useState<{
    username: string;
    password: string;
    role: string;
  } | null>(null);

  async function patch(
    admin: AdminRow,
    body: Record<string, unknown>,
    done: string,
  ) {
    try {
      await api(`/admins/${admin.id}`, { method: 'PATCH', body });
      toast(done);
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  return (
    <Card
      title="Quản trị viên"
      action={
        <button
          className="btn warn"
          onClick={() =>
            setAdding({ username: '', password: '', role: 'operator' })
          }
        >
          + Thêm admin
        </button>
      }
    >
      {!list.data ? (
        <Loading error={list.error} />
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Tên</th>
                <th>Vai trò</th>
                <th>MFA</th>
                <th>Đăng nhập cuối</th>
                <th>Trạng thái</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {list.data.admins.map((admin) => (
                <tr key={admin.id}>
                  <td>
                    <b>{admin.username}</b>{' '}
                    {admin.id === me?.id && (
                      <span className="badge blue">Bạn</span>
                    )}
                  </td>
                  <td>
                    <select
                      className="input"
                      value={admin.role}
                      disabled={admin.id === me?.id}
                      onChange={(e) =>
                        patch(admin, { role: e.target.value }, 'Đã đổi vai trò')
                      }
                      aria-label={`Vai trò của ${admin.username}`}
                    >
                      {Object.entries(ROLE).map(([key, label]) => (
                        <option key={key} value={key}>
                          {label}
                        </option>
                      ))}
                    </select>
                  </td>
                  <td>
                    {admin.mfa ? (
                      <span className="badge green">Bật</span>
                    ) : (
                      <span className="badge amber">Tắt</span>
                    )}
                  </td>
                  <td>{dateTime(admin.last_login_at)}</td>
                  <td>
                    {admin.disabled ? (
                      <span className="badge red">Đã khóa</span>
                    ) : (
                      <span className="badge green">Hoạt động</span>
                    )}
                  </td>
                  <td>
                    {admin.id !== me?.id && (
                      <div className="toolbar">
                        <button
                          className={`btn small ${admin.disabled ? 'success' : 'danger'}`}
                          onClick={() =>
                            patch(
                              admin,
                              { disabled: !admin.disabled },
                              admin.disabled
                                ? 'Đã mở khóa admin'
                                : 'Đã khóa admin',
                            )
                          }
                        >
                          {admin.disabled ? 'Mở khóa' : 'Khóa'}
                        </button>
                        {admin.mfa && (
                          <button
                            className="btn small ghost"
                            onClick={() =>
                              patch(
                                admin,
                                { reset_mfa: true },
                                'Đã đặt lại MFA',
                              )
                            }
                          >
                            Đặt lại MFA
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
      {adding && (
        <Modal title="Thêm quản trị viên" onClose={() => setAdding(null)}>
          <div className="form">
            <Field label="Tên đăng nhập" hint="a-z, 0-9, dấu . hoặc _">
              <input
                className="input"
                value={adding.username}
                onChange={(e) =>
                  setAdding({
                    ...adding,
                    username: e.target.value.toLowerCase(),
                  })
                }
              />
            </Field>
            <Field
              label="Mật khẩu tạm"
              hint="Ít nhất 12 ký tự; người dùng nên đổi sau khi đăng nhập."
            >
              <input
                className="input"
                type="password"
                autoComplete="new-password"
                value={adding.password}
                onChange={(e) =>
                  setAdding({ ...adding, password: e.target.value })
                }
              />
            </Field>
            <Field label="Vai trò">
              <select
                className="input"
                value={adding.role}
                onChange={(e) => setAdding({ ...adding, role: e.target.value })}
              >
                {Object.entries(ROLE).map(([key, label]) => (
                  <option key={key} value={key}>
                    {label}
                  </option>
                ))}
              </select>
            </Field>
          </div>
          <div className="modal-actions">
            <button className="btn ghost" onClick={() => setAdding(null)}>
              Hủy
            </button>
            <button
              className="btn"
              disabled={
                adding.username.length < 3 || adding.password.length < 12
              }
              onClick={async () => {
                try {
                  await api('/admins', { method: 'POST', body: adding });
                  toast('Đã thêm quản trị viên');
                  setAdding(null);
                  list.reload();
                } catch (reason) {
                  toast((reason as Error).message, true);
                }
              }}
            >
              Thêm
            </button>
          </div>
        </Modal>
      )}
    </Card>
  );
}

function AuditLog() {
  const [action, setAction] = useState('');
  const list = useLoad(
    () => api<Audit>(`/audit?limit=200&action=${encodeURIComponent(action)}`),
    [action],
  );
  return (
    <Card
      title="Nhật ký audit"
      action={
        <select
          className="input"
          value={action}
          onChange={(e) => setAction(e.target.value)}
          aria-label="Lọc thao tác"
        >
          <option value="">Tất cả thao tác</option>
          <option value="admin.">Quản trị viên</option>
          <option value="account.">Khóa/mở khóa</option>
          <option value="inventory.">Vật phẩm người chơi</option>
          <option value="chat.">Chat</option>
          <option value="item.">Danh mục vật phẩm</option>
          <option value="event.">Sự kiện</option>
          <option value="giftcode.">Giftcode</option>
          <option value="offer.">Shop</option>
        </select>
      }
    >
      {!list.data ? (
        <Loading error={list.error} />
      ) : list.data.entries.length === 0 ? (
        <Empty title="Chưa có bản ghi" />
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>Lúc</th>
                <th>Admin</th>
                <th>Thao tác</th>
                <th>Đối tượng</th>
                <th>Lý do</th>
              </tr>
            </thead>
            <tbody>
              {list.data.entries.map((e) => (
                <tr key={e.id}>
                  <td>{dateTime(e.created_at)}</td>
                  <td>{e.actor}</td>
                  <td>{ACTION[e.action] ?? e.action}</td>
                  <td>
                    {e.target_type === 'account' ? (
                      <a href={`/admin/players/?id=${e.target_id}`}>
                        {e.target_id.slice(0, 8)}…
                      </a>
                    ) : (
                      <span className="spark">
                        {e.target_type}: {e.target_id.slice(0, 18)}
                      </span>
                    )}
                  </td>
                  <td>{e.reason || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}
