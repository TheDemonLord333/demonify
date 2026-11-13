import { useState, type FormEvent } from 'react';
import { Link } from 'react-router';
import { useAuth } from '../lib/auth';
import { errorMessage } from '../lib/api';
import { ErrorBox } from '../components/ui';

export function LoginPage() {
  const { login } = useAuth();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await login(username, password);
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
        <h1 style={{ textAlign: 'center', marginBottom: 4 }}>Demonify</h1>
        <p className="muted" style={{ textAlign: 'center' }}>Verwaltung – bitte anmelden</p>
        <label className="field">
          Anmeldename oder E-Mail
          <input value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" autoFocus required maxLength={254} />
        </label>
        <label className="field">
          Passwort
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
        </label>
        <ErrorBox error={error} />
        <button className="btn primary" disabled={busy || !username || !password}>
          {busy ? 'Anmelden …' : 'Anmelden'}
        </button>
        <Link to="/passwort-vergessen" style={{ textAlign: 'center' }}>
          Passwort vergessen?
        </Link>
      </form>
    </div>
  );
}
