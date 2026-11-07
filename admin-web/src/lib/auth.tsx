import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import { api, setCsrfToken, setUnauthorizedHandler, type User } from './api';

interface AuthState {
  user: User | null;
  loading: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setUnauthorizedHandler(() => setUser(null));
    api<{ user: User; csrfToken: string | null }>('/auth/session')
      .then((r) => {
        setUser(r.user);
        if (r.csrfToken) setCsrfToken(r.csrfToken);
      })
      .catch(() => setUser(null))
      .finally(() => setLoading(false));
  }, []);

  const login = useCallback(async (username: string, password: string) => {
    const r = await api<{ user: User; csrfToken: string }>('/auth/login', {
      method: 'POST',
      body: { username, password, client: 'web', deviceName: 'Verwaltung (Browser)' },
      noRefresh: true,
    });
    setCsrfToken(r.csrfToken);
    setUser(r.user);
  }, []);

  const logout = useCallback(async () => {
    await api('/auth/logout', { method: 'POST', noRefresh: true }).catch(() => undefined);
    setCsrfToken(null);
    setUser(null);
  }, []);

  return <AuthContext.Provider value={{ user, loading, login, logout }}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('AuthProvider fehlt');
  return ctx;
}
