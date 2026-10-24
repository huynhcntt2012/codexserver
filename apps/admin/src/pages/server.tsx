import Layout from '@/components/Layout';
import { Card, Loading } from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime } from '@/lib/format';
import { useLoad } from '@/lib/session';

type Server = {
  checks: { name: string; ok: boolean; ms: number | null }[];
  uptime_seconds: number;
  mail_mode: string;
  time: string;
};

const MAIL: Record<string, string> = {
  smtp: 'SMTP (gửi email thật)',
  log: 'Log (chỉ thử local, mã in trong log API)',
  disabled: 'Tắt (Quên mật khẩu không gửi được mã)',
};

function uptime(seconds: number): string {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return `${d ? `${d} ngày ` : ''}${h} giờ ${m} phút`;
}

export default function ServerPage() {
  const data = useLoad(() => api<Server>('/server'));
  const d = data.data;
  return (
    <Layout
      title="Server"
      subtitle="Tình trạng các dịch vụ của game."
      actions={
        <button className="btn secondary" onClick={data.reload}>
          Kiểm tra lại
        </button>
      }
    >
      {!d ? (
        <Loading error={data.error} />
      ) : (
        <>
          <div className="grid stats">
            {d.checks.map((c) => (
              <section key={c.name} className="card stat">
                <div
                  className={`bubble ${c.ok ? 'mint' : 'coral'}`}
                  aria-hidden
                >
                  {c.ok ? '✅' : '❌'}
                </div>
                <div>
                  <b>{c.name}</b>
                  <span>
                    {c.ok
                      ? `Hoạt động${c.ms !== null ? ` · ${c.ms.toFixed(1)} ms` : ''}`
                      : 'Không phản hồi'}
                  </span>
                </div>
              </section>
            ))}
          </div>
          <Card title="Thông tin">
            <dl className="kv">
              <dt>API chạy được</dt>
              <dd>{uptime(d.uptime_seconds)}</dd>
              <dt>Email</dt>
              <dd>{MAIL[d.mail_mode] ?? d.mail_mode}</dd>
              <dt>Giờ máy chủ</dt>
              <dd>{dateTime(d.time)}</dd>
              <dt>Kiến trúc</dt>
              <dd>
                FastAPI + PostgreSQL 16 + Redis 7.2, arena Colyseus một process
                (20 Hz)
              </dd>
            </dl>
          </Card>
        </>
      )}
    </Layout>
  );
}
