import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import { api, setCsrfToken, setUnauthorizedHandler, type SetupInfo, type User } from './api';

interface AuthState {
  user: User | null;
  setup: SetupInfo | null;
  loading: boolean;
  /** Anmeldename oder bestätigte E-Mail-Adresse */
  login: (identifier: string, password: string) => Promise<void>;
  setUser: (u: User, setup?: SetupInfo) => void;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUserState] = useState<User | null>(null);
  const [setup, setSetup] = useState<SetupInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const setUser = useCallback((u: User | null, s?: SetupInfo) => {
    setUserState(u);
    if (s) setSetup(s);
  }, []);

  useEffect(() => {
    setUnauthorizedHandler(() => setUser(null));
    api<{ user: User; setup: SetupInfo; csrfToken: string | null }>('/auth/session')
      .then((r) => {
        setUser(r.user, r.setup);
        if (r.csrfToken) setCsrfToken(r.csrfToken);
      })
      .catch(() => setUser(null))
      .finally(() => setLoading(false));
  }, []);

  const login = useCallback(async (identifier: string, password: string) => {
    const r = await api<{ user: User; setup: SetupInfo; csrfToken: string }>('/auth/login', {
      method: 'POST',
      body: { identifier, password, client: 'web', deviceName: 'Verwaltung (Browser)' },
      noRefresh: true,
    });
    setCsrfToken(r.csrfToken);
    setUser(r.user, r.setup);
  }, [setUser]);

  const logout = useCallback(async () => {
    await api('/auth/logout', { method: 'POST', noRefresh: true }).catch(() => undefined);
    setCsrfToken(null);
    setUser(null);
  }, []);

  return <AuthContext.Provider value={{ user, setup, loading, login, logout, setUser }}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('AuthProvider fehlt');
  return ctx;
}
