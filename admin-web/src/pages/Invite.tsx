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
  const [email, setEmail] = useState('');
  const [emailRequired, setEmailRequired] = useState(false);
  const [mailNote, setMailNote] = useState<string | null>(null);
  const [password, setPassword] = useState('');
  const [password2, setPassword2] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    api<{ valid: boolean }>(`/auth/invites/${encodeURIComponent(code)}`)
      .then((r) => setValid(r.valid))
      .catch(() => setValid(false));
    api<{ emailRequired: boolean }>('/auth/config', { noRefresh: true })
      .then((r) => setEmailRequired(r.emailRequired))
      .catch(() => undefined);
  }, [code]);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError(null);
    if (password !== password2) return setError('Die Passwörter stimmen nicht überein.');
    try {
      const r = await api<{ emailSent: boolean; emailError: string | null }>('/auth/invites/redeem', {
        method: 'POST',
        body: { code, username, password, displayName: displayName || undefined, email: email || undefined },
        noRefresh: true,
      });
      setMailNote(
        r.emailSent
          ? `Wir haben dir einen Bestätigungslink an ${email} gesendet. Bitte öffne ihn, um deine E-Mail-Adresse zu bestätigen.`
          : r.emailError
            ? `${r.emailError} Du kannst die Adresse nach der Anmeldung in der App erneut eingeben.`
            : null,
      );
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
            Konto erstellt! Melde dich jetzt in der Demonify-App mit deinem Anmeldenamen und Passwort an.
          </div>
        )}
        {done && mailNote && <div className="alert info">{mailNote}</div>}
        {valid && !done && (
          <>
            <label className="field">
              Anmeldename (3–32 Zeichen, ohne @)
              <input value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" required minLength={3} maxLength={32} pattern="[^@\s]+" />
            </label>
            <label className="field">
              Anzeigename{emailRequired ? '' : ' (optional)'}
              <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} maxLength={64} required={emailRequired} />
            </label>
            {emailRequired && (
              <label className="field">
                E-Mail-Adresse (wird per Link bestätigt)
                <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" required maxLength={254} />
              </label>
            )}
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
