import { useState } from 'react';
import Layout from '@/components/Layout';
import MatchList, { type MatchRow, SourceBadge } from '@/components/MatchList';
import { Card, Empty, Loading, Stat } from '@/components/ui';
import { api } from '@/lib/api';
import { ago, dateTime, number } from '@/lib/format';
import { useLoad } from '@/lib/session';

type Live = {
  available: boolean;
  players: number;
  rooms: {
    roomId: string;
    players: number;
    maxPlayers: number;
    ready: number;
    joinable: boolean;
  }[];
};
type Room = {
  id: string;
  source: string;
  room_id: string;
  creator_id: string | null;
  creator_name: string;
  status: 'waiting' | 'playing' | 'closed' | 'stale';
  map_name: string;
  players: number;
  max_players: number;
  rounds: number;
  created_at: string;
  updated_at: string;
};
type Rooms = {
  summary: {
    total: number;
    waiting: number;
    playing: number;
    closed: number;
    stale: number;
  };
  top_creators: { account_id: string; name: string; rooms: number }[];
  items: Room[];
  total: number;
  page: number;
  size: number;
};

const ROOM_STATUS: Record<string, [string, string]> = {
  waiting: ['Phòng chờ', 'blue'],
  playing: ['Đang diễn ra', 'green'],
  closed: ['Đã đóng', ''],
  stale: ['Mất kết nối', 'amber'],
};

function Pager({
  page,
  total,
  size,
  onPage,
}: {
  page: number;
  total: number;
  size: number;
  onPage: (page: number) => void;
}) {
  const pages = Math.max(1, Math.ceil(total / size));
  return (
    <div className="pager">
      <button
        className="btn small ghost"
        disabled={page <= 1}
        onClick={() => onPage(page - 1)}
      >
        ‹ Trước
      </button>
      <span>
        Trang {page}/{pages}
      </span>
      <button
        className="btn small ghost"
        disabled={page >= pages}
        onClick={() => onPage(page + 1)}
      >
        Sau ›
      </button>
    </div>
  );
}

export default function Matches() {
  const [tab, setTab] = useState('rooms');
  const [roomStatus, setRoomStatus] = useState('');
  const [roomPage, setRoomPage] = useState(1);
  const [source, setSource] = useState('');
  const [matchPage, setMatchPage] = useState(1);
  const rooms = useLoad(
    () => api<Rooms>(`/rooms?status=${roomStatus}&page=${roomPage}&size=25`),
    [roomStatus, roomPage],
  );
  const matches = useLoad(
    () =>
      api<{ items: MatchRow[]; total: number; page: number; size: number }>(
        `/matches?source=${source}&page=${matchPage}&size=20`,
      ),
    [source, matchPage],
  );
  const live = useLoad(() => api<Live>('/rooms/live'));
  const s = rooms.data?.summary;
  return (
    <Layout
      title="Phòng & trận đấu"
      subtitle="Phòng người chơi đã tạo, trận đã diễn ra và người tham gia."
      actions={
        <button
          className="btn secondary"
          onClick={() => {
            rooms.reload();
            matches.reload();
            live.reload();
          }}
        >
          Làm mới
        </button>
      }
    >
      <div className="grid stats">
        <Stat
          icon="🏠"
          tone="sky"
          value={s ? number(s.total) : '…'}
          label="Tổng phòng đã tạo"
        />
        <Stat
          icon="⏳"
          tone="violet"
          value={s ? number(s.waiting) : '…'}
          label="Phòng chờ"
        />
        <Stat
          icon="⚔️"
          tone="mint"
          value={s ? number(s.playing) : '…'}
          label="Đang diễn ra"
        />
        <Stat
          icon="📜"
          tone="sun"
          value={matches.data ? number(matches.data.total) : '…'}
          label="Trận đã ghi nhận"
        />
      </div>
      <div className="tabs">
        {[
          ['rooms', 'Phòng'],
          ['history', 'Lịch sử trận'],
          ['live', 'Arena LIVE'],
        ].map(([key, label]) => (
          <button
            key={key}
            className={tab === key ? 'active' : ''}
            onClick={() => setTab(key)}
          >
            {label}
          </button>
        ))}
      </div>
      {tab === 'rooms' && (
        <div className="grid two">
          <Card
            title="Danh sách phòng"
            action={
              <select
                className="input"
                value={roomStatus}
                onChange={(e) => {
                  setRoomPage(1);
                  setRoomStatus(e.target.value);
                }}
                aria-label="Lọc trạng thái phòng"
              >
                <option value="">Mọi trạng thái</option>
                <option value="waiting">Phòng chờ</option>
                <option value="playing">Đang diễn ra</option>
                <option value="closed">Đã đóng</option>
                <option value="stale">Mất kết nối</option>
              </select>
            }
          >
            {!rooms.data ? (
              <Loading error={rooms.error} />
            ) : rooms.data.items.length === 0 ? (
              <Empty title="Chưa có phòng nào">
                Phòng xuất hiện khi người chơi tạo phòng online hoặc luyện tập
                (đã đăng nhập).
              </Empty>
            ) : (
              <>
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>Phòng</th>
                        <th>Nguồn</th>
                        <th>Người tạo</th>
                        <th>Trạng thái</th>
                        <th>Người chơi</th>
                        <th>Số trận</th>
                        <th>Tạo lúc</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rooms.data.items.map((room) => (
                        <tr key={room.id}>
                          <td>
                            <b>{room.map_name || '—'}</b>
                            <div className="spark">{room.room_id}</div>
                          </td>
                          <td>
                            <SourceBadge source={room.source} />
                          </td>
                          <td>
                            {room.creator_id ? (
                              <a href={`/admin/players/?id=${room.creator_id}`}>
                                {room.creator_name}
                              </a>
                            ) : (
                              '—'
                            )}
                          </td>
                          <td>
                            <span
                              className={`badge ${ROOM_STATUS[room.status][1]}`}
                            >
                              {ROOM_STATUS[room.status][0]}
                            </span>
                            <div className="spark">
                              cập nhật {ago(room.updated_at)}
                            </div>
                          </td>
                          <td>
                            {room.players}/{room.max_players}
                          </td>
                          <td>{room.rounds}</td>
                          <td>{dateTime(room.created_at)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <Pager
                  page={roomPage}
                  total={rooms.data.total}
                  size={rooms.data.size}
                  onPage={setRoomPage}
                />
              </>
            )}
          </Card>
          <Card title="Người tạo phòng nhiều nhất">
            {!rooms.data ? (
              <Loading error={rooms.error} />
            ) : rooms.data.top_creators.length === 0 ? (
              <Empty title="Chưa có dữ liệu" />
            ) : (
              <div className="list">
                {rooms.data.top_creators.map((c, i) => (
                  <div key={c.account_id}>
                    <span className="badge blue">#{i + 1}</span>
                    <a
                      className="grow"
                      href={`/admin/players/?id=${c.account_id}`}
                    >
                      {c.name}
                    </a>
                    <b>{c.rooms} phòng</b>
                  </div>
                ))}
              </div>
            )}
            <p className="spark">
              “Mất kết nối”: phòng không cập nhật quá 30 phút (arena khởi động
              lại hoặc client thoát đột ngột).
            </p>
          </Card>
        </div>
      )}
      {tab === 'history' && (
        <Card
          title="Lịch sử trận"
          action={
            <select
              className="input"
              value={source}
              onChange={(e) => {
                setMatchPage(1);
                setSource(e.target.value);
              }}
              aria-label="Lọc nguồn"
            >
              <option value="">Mọi nguồn</option>
              <option value="arena">Online (arena, đã xác thực)</option>
              <option value="practice">Luyện tập PC (client báo cáo)</option>
            </select>
          }
        >
          {!matches.data ? (
            <Loading error={matches.error} />
          ) : (
            <>
              <MatchList matches={matches.data.items} />
              <Pager
                page={matchPage}
                total={matches.data.total}
                size={matches.data.size}
                onPage={setMatchPage}
              />
            </>
          )}
          <p className="spark">
            Bấm một trận để xem từng người chơi. Trận luyện tập do app PC tự báo
            cáo nên chỉ để thống kê, không dùng phát thưởng.
          </p>
        </Card>
      )}
      {tab === 'live' && (
        <Card title="Phòng đang chờ trên arena (trực tiếp)">
          {!live.data ? (
            <Loading error={live.error} />
          ) : !live.data.available ? (
            <div className="notice">
              Không đọc được danh sách phòng từ arena.
            </div>
          ) : live.data.rooms.length === 0 ? (
            <Empty title="Không có phòng đang chờ" />
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Room ID</th>
                    <th>Người chơi</th>
                    <th>Sẵn sàng</th>
                    <th>Còn chỗ</th>
                  </tr>
                </thead>
                <tbody>
                  {live.data.rooms.map((room) => (
                    <tr key={room.roomId}>
                      <td>
                        <code>{room.roomId}</code>
                      </td>
                      <td>
                        {room.players}/{room.maxPlayers}
                      </td>
                      <td>{room.ready}</td>
                      <td>
                        {room.joinable ? (
                          <span className="badge green">Có</span>
                        ) : (
                          <span className="badge">Đã khóa</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </Layout>
  );
}
