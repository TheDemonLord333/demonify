import { useEffect, useState, type FormEvent } from 'react';
import { useParams } from 'react-router';
import { api, errorMessage } from '../lib/api';
import { ErrorBox } from '../components/ui';

/** Öffentliche Seite zum Einlösen einer zeitlich begrenzten Einladung (keine Selbstregistrierung). */
export function InvitePage() {
  const { code = '' } = useParams();
  const [valid, setValid] = useState<boolean | null>(null);
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [password, setPassword] = useState('');
  const [password2, setPassword2] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    api<{ valid: boolean }>(`/auth/invites/${encodeURIComponent(code)}`)
      .then((r) => setValid(r.valid))
      .catch(() => setValid(false));
  }, [code]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (password !== password2) return setError('Die Passwörter stimmen nicht überein.');
    try {
      await api('/auth/invites/redeem', { method: 'POST', body: { code, username, password, displayName: displayName || undefined }, noRefresh: true });
      setDone(true);
    } catch (err) {
      setError(errorMessage(err));
    }
  };

  return (
    <div className="login-wrap">
      <form className="card login-card stack" onSubmit={submit}>
        <img className="logo" src="/admin/icon-192.png" alt="Demonify" />
        <h1 style={{ textAlign: 'center' }}>Einladung zu Demonify</h1>
        {valid === null && <p className="muted">Prüfe Einladung …</p>}
        {valid === false && <div className="alert error">Diese Einladung ist ungültig, abgelaufen oder wurde bereits verwendet.</div>}
        {done && (
          <div className="alert success">
            Konto erstellt! Melde dich jetzt in der Demonify-App mit deinem Benutzernamen und Passwort an.
          </div>
        )}
        {valid && !done && (
          <>
            <label className="field">
              Benutzername (3–32 Zeichen)
              <input value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" required minLength={3} maxLength={32} />
            </label>
            <label className="field">
              Anzeigename (optional)
              <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} maxLength={64} />
            </label>
            <label className="field">
              Passwort (mind. 10 Zeichen)
              <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="new-password" required minLength={10} />
            </label>
            <label className="field">
              Passwort wiederholen
              <input type="password" value={password2} onChange={(e) => setPassword2(e.target.value)} autoComplete="new-password" required minLength={10} />
            </label>
            <ErrorBox error={error} />
            <button className="btn primary">Konto erstellen</button>
          </>
        )}
      </form>
    </div>
  );
}
