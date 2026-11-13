import { useEffect, useState, type FormEvent, type ReactNode } from 'react';
import { Link } from 'react-router';
import { api, errorMessage, type SetupInfo, type User } from '../lib/api';
import { useAuth } from '../lib/auth';
import { ErrorBox } from '../components/ui';

/**
 * Öffentliche Kontoseiten (auch für App-Nutzer, mobil nutzbar):
 * - /passwort-vergessen                 Link anfordern
 * - /konto/passwort-zuruecksetzen#token  neues Passwort setzen
 * - /konto/email-bestaetigen#token       E-Mail-Adresse bestätigen
 * Das Token steht im Fragment (#…) und wird deshalb nie an den Server gesendet oder protokolliert;
 * es geht nur im Body der API-Anfrage mit.
 */

function tokenFromHash(): string {
  const params = new URLSearchParams(window.location.hash.replace(/^#/, ''));
  return params.get('token') ?? '';
}

function PublicCard({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="login-wrap">
      <div className="card login-card stack">
        <img className="logo" src="/admin/icon-192.png" alt="Demonify" />
        <h1 style={{ textAlign: 'center' }}>{title}</h1>
        {children}
      </div>
    </div>
  );
}

const backToLogin = (
  <p className="muted" style={{ textAlign: 'center' }}>
    Melde dich anschließend wie gewohnt in der Demonify-App an.
    <br />
    <Link to="/">Zur Anmeldung der Verwaltung</Link>
  </p>
);

export function ForgotPasswordPage() {
  const [identifier, setIdentifier] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const r = await api<{ message: string }>('/auth/password/forgot', { method: 'POST', body: { identifier }, noRefresh: true });
      setMessage(r.message);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <PublicCard title="Passwort vergessen">
      {message ? (
        <>
          <div className="alert success">{message}</div>
          {backToLogin}
        </>
      ) : (
        <form className="stack" onSubmit={submit}>
          <p className="muted">Gib deinen Anmeldenamen oder deine bestätigte E-Mail-Adresse ein. Wir senden dir einen Link zum Zurücksetzen.</p>
          <label className="field">
            Anmeldename oder E-Mail
            <input value={identifier} onChange={(e) => setIdentifier(e.target.value)} autoComplete="username" autoFocus required maxLength={254} />
          </label>
          <ErrorBox error={error} />
          <button className="btn primary" disabled={busy || !identifier.trim()}>
            {busy ? 'Senden …' : 'Link senden'}
          </button>
          <p className="dim">Keine bestätigte E-Mail-Adresse oder kein Zugriff mehr darauf? Dann kann ein Administrator dein Passwort zurücksetzen.</p>
        </form>
      )}
    </PublicCard>
  );
}

export function ResetPasswordPage() {
  const [token] = useState(tokenFromHash);
  const [valid, setValid] = useState<boolean | null>(null);
  const [pw, setPw] = useState('');
  const [pw2, setPw2] = useState('');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return setValid(false);
    api<{ valid: boolean }>('/auth/tokens/check', { method: 'POST', body: { token, kind: 'PASSWORD_RESET' }, noRefresh: true })
      .then((r) => setValid(r.valid))
      .catch(() => setValid(false));
  }, [token]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (pw.length < 10) return setError('Das Passwort muss mindestens 10 Zeichen lang sein.');
    if (pw !== pw2) return setError('Die Passwörter stimmen nicht überein.');
    setBusy(true);
    try {
      await api('/auth/password/reset', { method: 'POST', body: { token, password: pw }, noRefresh: true });
      setDone(true);
      // Token aus der Adresszeile entfernen
      history.replaceState(null, '', window.location.pathname);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <PublicCard title="Neues Passwort">
      {valid === null && <p className="muted">Link wird geprüft …</p>}
      {valid === false && !done && (
        <>
          <div className="alert error">Der Link ist ungültig, abgelaufen oder wurde bereits verwendet.</div>
          <Link className="btn" to="/passwort-vergessen">
            Neuen Link anfordern
          </Link>
        </>
      )}
      {done && (
        <>
          <div className="alert success">Dein Passwort wurde geändert. Aus Sicherheitsgründen wurden alle Geräte abgemeldet.</div>
          {backToLogin}
        </>
      )}
      {valid && !done && (
        <form className="stack" onSubmit={submit}>
          <label className="field">
            Neues Passwort (mind. 10 Zeichen)
            <input type="password" value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="new-password" autoFocus required minLength={10} />
          </label>
          <label className="field">
            Passwort wiederholen
            <input type="password" value={pw2} onChange={(e) => setPw2(e.target.value)} autoComplete="new-password" required minLength={10} />
          </label>
          <ErrorBox error={error} />
          <button className="btn primary" disabled={busy}>
            {busy ? 'Speichern …' : 'Passwort speichern'}
          </button>
        </form>
      )}
    </PublicCard>
  );
}

export function ConfirmEmailPage() {
  const [token] = useState(tokenFromHash);
  const [state, setState] = useState<{ valid: boolean; email: string | null } | null>(null);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return setState({ valid: false, email: null });
    api<{ valid: boolean; email: string | null }>('/auth/tokens/check', { method: 'POST', body: { token, kind: 'VERIFY_EMAIL' }, noRefresh: true })
      .then(setState)
      .catch(() => setState({ valid: false, email: null }));
  }, [token]);

  // Bestätigung erst per Knopfdruck: automatische Link-Vorschauen von Mailprogrammen lösen so nichts aus
  const confirm = async () => {
    setBusy(true);
    setError(null);
    try {
      const r = await api<{ email: string }>('/auth/email/confirm', { method: 'POST', body: { token }, noRefresh: true });
      setDone(r.email);
      history.replaceState(null, '', window.location.pathname);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <PublicCard title="E-Mail bestätigen">
      {state === null && <p className="muted">Link wird geprüft …</p>}
      {state?.valid === false && !done && (
        <div className="alert error">Der Link ist ungültig, abgelaufen oder wurde bereits verwendet. Fordere in der App einen neuen Bestätigungslink an.</div>
      )}
      {done && (
        <>
          <div className="alert success">
            <strong>{done}</strong> ist bestätigt. Du kannst dich jetzt auch mit dieser Adresse anmelden.
          </div>
          <p className="muted" style={{ textAlign: 'center' }}>
            Zurück in der App tippst du auf „Ich habe bestätigt“.
          </p>
        </>
      )}
      {state?.valid && !done && (
        <div className="stack">
          <p>
            Adresse <strong>{state.email}</strong> für dein Demonify-Konto bestätigen?
          </p>
          <ErrorBox error={error} />
          <button className="btn primary" onClick={confirm} disabled={busy}>
            {busy ? 'Bestätigen …' : 'Jetzt bestätigen'}
          </button>
        </div>
      )}
    </PublicCard>
  );
}

/** Ersteinrichtung in der Verwaltung (Admin-Konto mit Startpasswort) */
export function SetupPage() {
  const { user, setUser, logout } = useAuth();
  const [displayName, setDisplayName] = useState(user?.displayName ?? '');
  const [current, setCurrent] = useState('');
  const [pw, setPw] = useState('');
  const [pw2, setPw2] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (pw !== pw2) return setError('Die Passwörter stimmen nicht überein.');
    setBusy(true);
    try {
      const r = await api<{ user: User; setup: SetupInfo }>('/me/setup', { method: 'POST', body: { displayName, currentPassword: current, newPassword: pw } });
      setUser(r.user, r.setup);
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="login-wrap">
      <form className="card login-card stack" onSubmit={submit}>
        <img className="logo" src="/admin/icon-192.png" alt="Demonify" />
        <h1 style={{ textAlign: 'center' }}>Ersteinrichtung</h1>
        <p className="muted">Dein Konto wurde mit einem Startpasswort angelegt. Lege deinen Anzeigenamen und ein eigenes Passwort fest.</p>
        <label className="field">
          Anzeigename
          <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} required maxLength={64} autoFocus />
        </label>
        <label className="field">
          Startpasswort
          <input type="password" value={current} onChange={(e) => setCurrent(e.target.value)} autoComplete="current-password" required />
        </label>
        <label className="field">
          Neues Passwort (mind. 10 Zeichen)
          <input type="password" value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="new-password" required minLength={10} />
        </label>
        <label className="field">
          Neues Passwort wiederholen
          <input type="password" value={pw2} onChange={(e) => setPw2(e.target.value)} autoComplete="new-password" required minLength={10} />
        </label>
        <ErrorBox error={error} />
        <button className="btn primary" disabled={busy}>
          {busy ? 'Speichern …' : 'Weiter'}
        </button>
        <button type="button" className="btn ghost" onClick={logout}>
          Abmelden
        </button>
      </form>
    </div>
  );
}

/** Hinweis + Formular, solange keine bestätigte E-Mail-Adresse hinterlegt ist */
export function EmailBanner() {
  const { user, setup, setUser } = useAuth();
  const [open, setOpen] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  if (!user || !setup?.emailRequired || user.emailVerified) return null;
  const pending = setup.pendingEmail;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const r = await api<{ pendingEmail: string }>('/me/email', { method: 'POST', body: { email, password } });
      setUser(user, { ...setup, pendingEmail: r.pendingEmail });
      setOpen(false);
      setPassword('');
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="alert info stack" style={{ marginBottom: 16 }}>
      <div>
        {pending ? (
          <>
            Bitte bestätige <strong>{pending}</strong> über den Link in der Mail, die wir dir gesendet haben.
          </>
        ) : (
          <>Für dein Konto ist noch keine bestätigte E-Mail-Adresse hinterlegt. Sie wird für „Passwort vergessen“ und die Anmeldung per E-Mail benötigt.</>
        )}{' '}
        <button className="btn small" onClick={() => setOpen(!open)}>
          {pending ? 'Erneut senden / ändern' : 'E-Mail hinterlegen'}
        </button>
      </div>
      {open && (
        <form className="stack" onSubmit={submit} style={{ maxWidth: 420 }}>
          <label className="field">
            E-Mail-Adresse
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoComplete="email" />
          </label>
          <label className="field">
            Passwort zur Bestätigung
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required autoComplete="current-password" />
          </label>
          <ErrorBox error={error} />
          <button className="btn primary" disabled={busy}>
            Bestätigungslink senden
          </button>
        </form>
      )}
    </div>
  );
}
