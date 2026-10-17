import { useState } from 'react';
import { Bars, LineChart, Point } from '@/components/charts';
import Layout from '@/components/Layout';
import { Card, Loading, Stat } from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime, number } from '@/lib/format';
import { useLoad } from '@/lib/session';

export type Overview = {
  generated_at: string;
  accounts: {
    total: number;
    registered: number;
    guests: number;
    new_24h: number;
    active_24h: number;
    banned: number;
  };
  social: {
    guilds: number;
    guild_members: number;
    friendships: number;
    chat_24h: number;
  };
  liveops: {
    events_running: number;
    events_total: number;
    items_published: number;
    giftcode_redemptions: number;
    offers_on_sale: number;
  };
  live: { available: boolean; rooms: number; players: number };
  online_now: number;
  rooms: {
    total: number;
    waiting: number;
    playing: number;
    closed: number;
    stale: number;
  };
  recent: { matches: number; rooms: number };
  series: {
    registrations: Point[];
    logins: Point[];
    chat: Point[];
    redemptions: Point[];
    topups: Point[];
  };
  revenue: null;
};

function csv(o: Overview): string {
  const rows = [['ngay', 'dang_ky', 'dang_nhap_cuoi', 'tin_nhan', 'giftcode']];
  o.series.registrations.forEach((p, i) =>
    rows.push([
      p.day,
      String(p.count),
      String(o.series.logins[i].count),
      String(o.series.chat[i].count),
      String(o.series.redemptions[i].count),
    ]),
  );
  return rows.map((r) => r.join(',')).join('\n');
}

export default function Reports() {
  const [days, setDays] = useState(30);
  const data = useLoad(
    () => api<Overview>(`/reports/overview?days=${days}`),
    [days],
  );
  const o = data.data;
  return (
    <Layout
      title="Báo cáo"
      subtitle="Số liệu tổng hợp từ tài khoản, chat, giftcode và sự kiện."
      actions={
        <>
          <select
            className="input"
            value={days}
            onChange={(e) => setDays(Number(e.target.value))}
            aria-label="Khoảng thời gian"
          >
            <option value={7}>7 ngày</option>
            <option value={14}>14 ngày</option>
            <option value={30}>30 ngày</option>
            <option value={90}>90 ngày</option>
          </select>
          {o && (
            <a
              className="btn secondary"
              download={`bupbup-report-${days}d.csv`}
              href={`data:text/csv;charset=utf-8,${encodeURIComponent(csv(o))}`}
            >
              Xuất CSV
            </a>
          )}
        </>
      }
    >
      {!o ? (
        <Loading error={data.error} />
      ) : (
        <>
          <div className="grid stats">
            <Stat
              icon="👥"
              tone="sky"
              value={number(o.accounts.total)}
              label={`Tài khoản (${number(o.accounts.registered)} đăng ký)`}
            />
            <Stat
              icon="🔥"
              tone="sun"
              value={number(o.accounts.active_24h)}
              label="Đăng nhập 24 giờ"
            />
            <Stat
              icon="💬"
              tone="violet"
              value={number(o.social.chat_24h)}
              label="Tin nhắn 24 giờ"
            />
            <Stat
              icon="🛡️"
              tone="mint"
              value={number(o.social.guilds)}
              label={`Bang hội (${number(o.social.guild_members)} thành viên)`}
            />
            <Stat
              icon="🤝"
              tone="sky"
              value={number(o.social.friendships)}
              label="Cặp bạn bè"
            />
            <Stat
              icon="🎁"
              tone="coral"
              value={number(o.liveops.giftcode_redemptions)}
              label="Lượt nhập giftcode"
            />
          </div>
          <div className="grid halves">
            <Card title="Đăng ký mới theo ngày">
              <Bars points={o.series.registrations} />
            </Card>
            <Card title="Đăng nhập (lần cuối) theo ngày">
              <Bars points={o.series.logins} color="#ff9f43" />
            </Card>
            <Card title="Tin nhắn chat theo ngày">
              <LineChart series={[o.series.chat]} colors={['#8b6cf0']} />
            </Card>
            <Card title="Nhập giftcode theo ngày">
              <LineChart series={[o.series.redemptions]} colors={['#2fbf8a']} />
            </Card>
          </div>
          <div className="notice info">
            “Đăng nhập” đếm theo thời điểm đăng nhập gần nhất của mỗi tài khoản,
            nên chưa phải DAU/retention đầy đủ. Doanh thu và kết quả trận chưa
            có nguồn dữ liệu. Tạo lúc {dateTime(o.generated_at)}.
          </div>
        </>
      )}
    </Layout>
  );
}
