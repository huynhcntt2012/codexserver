import { Fragment, useState } from 'react';
import { dateTime } from '@/lib/format';
import { Empty } from './ui';

export type Participant = {
  account_id: string | null;
  name: string;
  is_bot: boolean;
  hero: string;
  placement: number;
  kills: number;
  bombs: number;
  items: number;
  score: number;
  survived_ms: number;
  winner: boolean;
};
export type MatchRow = {
  id: string;
  room_id: string;
  creator_name: string;
  source: 'arena' | 'practice';
  round: number;
  map_name: string;
  verified: boolean;
  winner_name: string | null;
  duration_ms: number;
  ended_at: string;
  participants: Participant[];
};

export function duration(ms: number): string {
  const seconds = Math.round(ms / 1000);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

export function SourceBadge({
  source,
  verified,
}: {
  source: string;
  verified?: boolean;
}) {
  return source === 'arena' ? (
    <span className="badge green" title="Arena gửi kết quả bằng token dịch vụ">
      Online · đã xác thực
    </span>
  ) : (
    <span
      className="badge amber"
      title="Client PC tự báo cáo, không dùng để phát thưởng"
    >
      Luyện tập{verified ? '' : ' · client báo cáo'}
    </span>
  );
}

/** Match history; a row expands to every participant's line. */
export default function MatchList({ matches }: { matches: MatchRow[] }) {
  const [open, setOpen] = useState<string | null>(null);
  if (matches.length === 0)
    return <Empty title="Chưa có trận nào được ghi nhận" />;
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Kết thúc</th>
            <th>Nguồn</th>
            <th>Phòng / bản đồ</th>
            <th>Vòng</th>
            <th>Thời lượng</th>
            <th>Người chơi</th>
            <th>Thắng</th>
          </tr>
        </thead>
        <tbody>
          {matches.map((m) => (
            <Fragment key={m.id}>
              <tr
                className={`clickable${open === m.id ? ' selected' : ''}`}
                onClick={() => setOpen(open === m.id ? null : m.id)}
              >
                <td>{dateTime(m.ended_at)}</td>
                <td>
                  <SourceBadge source={m.source} verified={m.verified} />
                </td>
                <td>
                  <b>{m.map_name || '—'}</b>
                  <div className="spark">
                    {m.room_id} · tạo bởi {m.creator_name || '—'}
                  </div>
                </td>
                <td>{m.round}</td>
                <td>{duration(m.duration_ms)}</td>
                <td>{m.participants.length}</td>
                <td>
                  {m.winner_name ?? (
                    <span className="muted">Hòa / hết giờ</span>
                  )}
                </td>
              </tr>
              {open === m.id && (
                <tr>
                  <td colSpan={7}>
                    <table>
                      <thead>
                        <tr>
                          <th>#</th>
                          <th>Người chơi</th>
                          <th>Hạ gục</th>
                          <th>Bom đặt</th>
                          <th>Vật phẩm</th>
                          <th>Điểm</th>
                          <th>Sống sót</th>
                        </tr>
                      </thead>
                      <tbody>
                        {m.participants.map((p) => (
                          <tr key={`${p.placement}-${p.name}`}>
                            <td>{p.winner ? '🏆' : p.placement}</td>
                            <td>
                              {p.account_id ? (
                                <a href={`/admin/players/?id=${p.account_id}`}>
                                  {p.name}
                                </a>
                              ) : (
                                p.name
                              )}{' '}
                              {p.is_bot && <span className="badge">Bot</span>}
                              {p.hero && (
                                <span className="spark"> · {p.hero}</span>
                              )}
                            </td>
                            <td>{p.kills}</td>
                            <td>{m.source === 'arena' ? p.bombs : '—'}</td>
                            <td>{m.source === 'practice' ? p.items : '—'}</td>
                            <td>{m.source === 'practice' ? p.score : '—'}</td>
                            <td>
                              {p.survived_ms ? duration(p.survived_ms) : '—'}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </td>
                </tr>
              )}
            </Fragment>
          ))}
        </tbody>
      </table>
    </div>
  );
}
