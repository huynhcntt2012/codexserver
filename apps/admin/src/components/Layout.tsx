import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ReactNode } from 'react';
import { ROLE } from '@/lib/format';
import { useSession } from '@/lib/session';

const NAV = [
  ['/', '🏠', 'Dashboard'],
  ['/players', '👥', 'Người chơi'],
  ['/quests', '📋', 'Nhiệm vụ'],
  ['/events', '🎉', 'Sự kiện'],
  ['/items', '🎒', 'Vật phẩm'],
  ['/maps', '🗺️', 'Bản đồ'],
  ['/leaderboard', '🏆', 'Xếp hạng'],
  ['/exp', '⭐', 'Match EXP'],
  ['/giftcodes', '🎁', 'Giftcode'],
  ['/mail', '✉️', 'Hộp thư'],
  ['/shop', '🛒', 'Shop'],
  ['/website', '🌐', 'Website'],
  ['/matches', '⚔️', 'Phòng & trận'],
  ['/economy', '💰', 'Giao dịch'],
  ['/reports', '📊', 'Báo cáo'],
  ['/server', '🖥️', 'Server'],
  ['/settings', '⚙️', 'Cài đặt'],
] as const;

export default function Layout({
  title,
  subtitle,
  actions,
  children,
}: {
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  children: ReactNode;
}) {
  const router = useRouter();
  const { me, signOut } = useSession();
  return (
    <div className="shell">
      <Head>
        <title>{`${title} · Bụp Bụp Admin`}</title>
      </Head>
      <aside className="sidebar">
        <div className="brand">
          <img src="/admin/game/ui/launch/mascot_pip.png" alt="" />
          <div>
            <b>BỤP BỤP</b>
            <small>ADMIN PORTAL</small>
          </div>
        </div>
        <nav className="nav" aria-label="Điều hướng quản trị">
          {NAV.map(([href, icon, label]) => {
            const active =
              href === '/'
                ? router.pathname === '/'
                : router.pathname.startsWith(href);
            return (
              <Link
                key={href}
                href={href}
                className={active ? 'active' : undefined}
              >
                <span className="icon" aria-hidden>
                  {icon}
                </span>
                {label}
              </Link>
            );
          })}
        </nav>
        <img
          className="mascot"
          src="/admin/game/ui/launch/mascot_nop.png"
          alt=""
        />
      </aside>
      <div className="main">
        <header className="topbar">
          <div className="title">
            <h1>{title}</h1>
            {subtitle && <p>{subtitle}</p>}
          </div>
          {actions}
          {me && (
            <div className="who">
              <div className="avatar">
                {me.username.slice(0, 1).toUpperCase()}
              </div>
              <div>
                <b>{me.username}</b>
                <small>{ROLE[me.role]}</small>
              </div>
              <button className="btn small secondary" onClick={signOut}>
                Đăng xuất
              </button>
            </div>
          )}
        </header>
        <main className="content">{children}</main>
      </div>
    </div>
  );
}
