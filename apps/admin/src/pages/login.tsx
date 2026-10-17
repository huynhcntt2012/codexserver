import Head from 'next/head';
import { useRouter } from 'next/router';
import { FormEvent, useState } from 'react';
import { api, ApiError, setToken } from '@/lib/api';
import type { AdminMe } from '@/lib/session';
import { useSession } from '@/lib/session';

export default function Login() {
  const router = useRouter();
  const { refresh } = useSession();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [otp, setOtp] = useState('');
  const [needOtp, setNeedOtp] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError('');
    try {
      const reply = await api<{ access_token: string; admin: AdminMe }>(
        '/auth/login',
        {
          method: 'POST',
          body: { username: username.trim(), password, otp: otp || undefined },
        },
      );
      setToken(reply.access_token);
      setPassword('');
      await refresh();
      router.replace('/');
    } catch (reason) {
      const message = (reason as ApiError).message;
      if (message.includes('MFA')) setNeedOtp(true);
      setError(message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <Head>
        <title>Đăng nhập · Bụp Bụp Admin</title>
      </Head>
      <form className="login-card" onSubmit={submit}>
        <div className="brand">
          <img src="/admin/game/ui/launch/mascot_pip.png" alt="" />
          <div>
            <b>BỤP BỤP</b>
            <small>ADMIN PORTAL · GAME OPERATIONS</small>
          </div>
        </div>
        <label className="field">
          <span>Tên đăng nhập</span>
          <input
            className="input"
            name="username"
            autoComplete="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            required
          />
        </label>
        <label className="field">
          <span>Mật khẩu</span>
          <input
            className="input"
            type="password"
            name="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>
        {needOtp && (
          <label className="field">
            <span>Mã MFA (6 số)</span>
            <input
              className="input"
              name="otp"
              inputMode="numeric"
              autoComplete="one-time-code"
              maxLength={6}
              value={otp}
              onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
              autoFocus
            />
          </label>
        )}
        {error && <div className="error">{error}</div>}
        <button className="btn" type="submit" disabled={busy}>
          {busy ? 'Đang đăng nhập…' : 'Đăng nhập'}
        </button>
        <p className="spark">
          Tài khoản quản trị tách riêng tài khoản người chơi. Phiên hết hạn sau
          4 giờ hoặc khi đóng tab.
        </p>
      </form>
    </div>
  );
}
