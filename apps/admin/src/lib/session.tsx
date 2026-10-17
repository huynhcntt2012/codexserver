import { useRouter } from 'next/router';
import {
  createContext,
  ReactNode,
  useCallback,
  useContext,
  useEffect,
  useState,
} from 'react';
import { api, getToken, setToken } from './api';

export type AdminMe = {
  id: string;
  username: string;
  role: 'owner' | 'operator' | 'viewer';
  mfa: boolean;
  permissions: string[];
  last_login_at: string | null;
};

type Session = {
  me: AdminMe | null;
  can: (permission: string) => boolean;
  refresh: () => Promise<void>;
  signOut: () => void;
  toast: (message: string, error?: boolean) => void;
};

const SessionContext = createContext<Session | null>(null);

export function SessionProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [me, setMe] = useState<AdminMe | null>(null);
  const [note, setNote] = useState<{ text: string; error: boolean } | null>(
    null,
  );
  const onLogin = router.pathname === '/login';

  const refresh = useCallback(async () => {
    if (!getToken()) {
      setMe(null);
      return;
    }
    try {
      setMe(await api<AdminMe>('/auth/me'));
    } catch {
      setMe(null);
    }
  }, []);

  useEffect(() => {
    if (!onLogin && !getToken()) {
      router.replace('/login');
      return;
    }
    if (!onLogin) refresh();
  }, [onLogin, refresh, router]);

  useEffect(() => {
    if (!note) return;
    const timer = setTimeout(() => setNote(null), 3200);
    return () => clearTimeout(timer);
  }, [note]);

  const value: Session = {
    me,
    can: (permission) => !!me?.permissions.includes(permission),
    refresh,
    signOut: () => {
      setToken(null);
      setMe(null);
      router.replace('/login');
    },
    toast: (text, error = false) => setNote({ text, error }),
  };

  return (
    <SessionContext.Provider value={value}>
      {children}
      {note && (
        <div className={`toast${note.error ? ' error' : ''}`} role="status">
          {note.text}
        </div>
      )}
    </SessionContext.Provider>
  );
}

export function useSession(): Session {
  const value = useContext(SessionContext);
  if (!value) throw new Error('useSession outside SessionProvider');
  return value;
}

/** Loads data on mount and whenever `deps` change; `reload` re-runs it. */
export function useLoad<T>(
  loader: () => Promise<T>,
  deps: unknown[] = [],
): {
  data: T | null;
  error: string | null;
  loading: boolean;
  reload: () => void;
} {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    if (!getToken()) return;
    let live = true;
    setLoading(true);
    loader()
      .then((value) => {
        if (live) {
          setData(value);
          setError(null);
        }
      })
      .catch((reason: Error) => live && setError(reason.message))
      .finally(() => live && setLoading(false));
    return () => {
      live = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick]);
  return { data, error, loading, reload: () => setTick((t) => t + 1) };
}
