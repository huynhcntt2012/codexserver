import Link from 'next/link';
import { Donut, LineChart } from '@/components/charts';
import Layout from '@/components/Layout';
import { Card, Empty, Loading, Phase, Stat } from '@/components/ui';
import { api } from '@/lib/api';
import { ACTION, ago, dateTime, number } from '@/lib/format';
import { useLoad } from '@/lib/session';
import type { Overview } from './reports';

type Audit = {
  entries: {
    id: number;
    actor: string;
    action: string;
    target_id: string;
    created_at: string;
  }[];
};
type Events = {
  events: {
    id: string;
    name: string;
    phase: string;
    start_at: string;
    end_at: string;
  }[];
};
type Server = { checks: { name: string; ok: boolean }[] };

export default function Dashboard() {
  const overview = useLoad(() => api<Overview>('/reports/overview?days=14'));
  const audit = useLoad(() => api<Audit>('/audit?limit=8'));
  const events = useLoad(() => api<Events>('/events'));
  const server = useLoad(() => api<Server>('/server'));
  const o = overview.data;
  const healthy = server.data?.checks.every((c) => c.ok);
  const running = (events.data?.events ?? []).filter((e) =>
    ['running', 'scheduled'].includes(e.phase),
  );
  return (
    <Layout
      title="Tổng quan hệ thống"
      subtitle="Số liệu thật từ API, PostgreSQL và arena đang chạy."
      actions={
        server.data && (
          <span className={`badge ${healthy ? 'green' : 'red'}`}>
            {healthy ? '● Server online' : '● Có dịch vụ lỗi'}
          </span>
        )
      }
    >
      {!o ? (
        <Loading error={overview.error} />
      ) : (
        <>
          <div className="grid stats">
            <Stat
              icon="🟢"
              tone="mint"
              value={number(o.online_now)}
              label="Tài khoản đang online (2 phút)"
            />
            <Stat
              icon="👥"
              tone="sky"
              value={number(o.accounts.active_24h)}
              label="Đăng nhập 24 giờ"
            />
            <Stat
              icon="🏠"
              tone="violet"
              value={`${number(o.rooms.waiting)} / ${number(o.rooms.playing)}`}
              label={`Phòng chờ / đang diễn ra · tổng ${number(o.rooms.total)}`}
            />
            <Stat
              icon="⚔️"
              tone="sun"
              value={number(o.recent.matches)}
              label="Trận 24 giờ qua"
            />
            <Stat
              icon="🎉"
              tone="coral"
              value={number(o.liveops.events_running)}
              label="Sự kiện đang chạy"
            />
          </div>
          <div className="grid two">
            <Card title="Đăng ký và đăng nhập 14 ngày">
              <LineChart
                series={[o.series.logins, o.series.registrations]}
                labels={['Đăng nhập (lần cuối)', 'Đăng ký mới']}
              />
            </Card>
            <Card title="Cơ cấu tài khoản">
              <Donut
                center={number(o.accounts.total)}
                caption="tài khoản"
                parts={[
                  {
                    label: 'Đã đăng ký',
                    value: o.accounts.registered,
                    color: '#1f8fe5',
                  },
                  {
                    label: 'Khách',
                    value: o.accounts.guests,
                    color: '#ffc93c',
                  },
                  {
                    label: 'Đang bị khóa',
                    value: o.accounts.banned,
                    color: '#f4627d',
                  },
                ]}
              />
              <p className="spark">
                Doanh thu: chưa có thanh toán thật ở giai đoạn này, nên không
                hiển thị số liệu doanh thu.
              </p>
            </Card>
          </div>
        </>
      )}
      <div className="grid halves">
        <Card
          title="Hoạt động quản trị gần đây"
          action={<Link href="/settings?tab=audit">Xem tất cả</Link>}
        >
          {!audit.data ? (
            <Loading error={audit.error} />
          ) : audit.data.entries.length === 0 ? (
            <Empty title="Chưa có hoạt động" />
          ) : (
            <div className="list">
              {audit.data.entries.map((e) => (
                <div key={e.id}>
                  <span className="badge blue">{e.actor}</span>
                  <span>{ACTION[e.action] ?? e.action}</span>
                  <span className="muted grow">{e.target_id.slice(0, 12)}</span>
                  <span className="spark">{ago(e.created_at)}</span>
                </div>
              ))}
            </div>
          )}
        </Card>
        <Card
          title="Sự kiện đang chạy / sắp tới"
          action={<Link href="/events">Quản lý</Link>}
        >
          {!events.data ? (
            <Loading error={events.error} />
          ) : running.length === 0 ? (
            <Empty title="Không có sự kiện đang chạy">
              <Link href="/events">Tạo sự kiện mới</Link>
            </Empty>
          ) : (
            <div className="list">
              {running.slice(0, 6).map((e) => (
                <div key={e.id}>
                  <b className="grow">{e.name}</b>
                  <span className="spark">
                    {dateTime(e.start_at)} → {dateTime(e.end_at)}
                  </span>
                  <Phase value={e.phase} />
                </div>
              ))}
            </div>
          )}
        </Card>
      </div>
    </Layout>
  );
}
