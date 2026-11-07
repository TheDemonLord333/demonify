import { useState } from 'react';
import { api, errorMessage, type User } from '../lib/api';
import { useApi } from '../lib/hooks';
import { useAuth } from '../lib/auth';
import { ErrorBox, Modal } from '../components/ui';
import { formatDate } from '../lib/format';

type AdminUser = User & { activeSessions: number };
interface Invite {
  id: string;
  role: 'ADMIN' | 'USER';
  note: string | null;
  createdAt: string;
  expiresAt: string;
  usedAt: string | null;
  usedBy: string | null;
  status: 'OPEN' | 'USED' | 'EXPIRED' | 'REVOKED';
}

export function UsersPage() {
  const { user: me } = useAuth();
  const users = useApi<{ items: AdminUser[] }>('/admin/users');
  const invites = useApi<{ items: Invite[] }>('/admin/invites');
  const [creating, setCreating] = useState(false);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const patch = async (u: AdminUser, body: object, confirmText?: string) => {
    if (confirmText && !confirm(confirmText)) return;
    setError(null);
    try {
      await api(`/admin/users/${u.id}`, { method: 'PATCH', body });
      users.reload();
    } catch (e) {
      setError(errorMessage(e));
    }
  };

  return (
    <>
      <div className="row between">
        <h1>Benutzer</h1>
        <div className="row">
          <button className="btn" onClick={() => setInviteOpen(true)}>
            Einladung erstellen
          </button>
          <button className="btn primary" onClick={() => setCreating(true)}>
            ＋ Benutzer anlegen
          </button>
        </div>
      </div>
      <ErrorBox error={error ?? users.error} />
      <div className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th>Benutzer</th>
              <th>Rolle</th>
              <th>Status</th>
              <th>Sitzungen</th>
              <th>Letzte Anmeldung</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {users.data?.items.map((u) => (
              <tr key={u.id}>
                <td>
                  <strong>{u.username}</strong>
                  {u.displayName && <div className="dim">{u.displayName}</div>}
                </td>
                <td>
                  <span className={`badge ${u.role === 'ADMIN' ? 'primary' : ''}`}>{u.role === 'ADMIN' ? 'Admin' : 'Benutzer'}</span>
                </td>
                <td>{u.disabled ? <span className="badge danger">gesperrt</span> : <span className="badge success">aktiv</span>}</td>
                <td>{u.activeSessions}</td>
                <td className="dim">{formatDate(u.lastLoginAt)}</td>
                <td>
                  <div className="row" style={{ justifyContent: 'flex-end', gap: 6 }}>
                    {u.id !== me?.id && (
                      <>
                        <button className="btn small" onClick={() => patch(u, { role: u.role === 'ADMIN' ? 'USER' : 'ADMIN' })}>
                          {u.role === 'ADMIN' ? 'Zu Benutzer' : 'Zu Admin'}
                        </button>
                        <button
                          className={`btn small ${u.disabled ? '' : 'danger'}`}
                          onClick={() => patch(u, { disabled: !u.disabled }, u.disabled ? undefined : `${u.username} sperren? Alle Sitzungen werden beendet.`)}
                        >
                          {u.disabled ? 'Entsperren' : 'Sperren'}
                        </button>
                      </>
                    )}
                    <button
                      className="btn small ghost"
                      onClick={async () => {
                        if (!confirm(`Alle Sitzungen von ${u.username} beenden?`)) return;
                        await api(`/admin/users/${u.id}/revoke-sessions`, { method: 'POST' });
                        users.reload();
                      }}
                    >
                      Abmelden
                    </button>
                    <ResetPassword user={u} onError={setError} />
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>Einladungen</h2>
      <div className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th>Rolle</th>
              <th>Notiz</th>
              <th>Status</th>
              <th>Gültig bis</th>
              <th>Verwendet von</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {invites.data?.items.map((i) => (
              <tr key={i.id}>
                <td>{i.role === 'ADMIN' ? 'Admin' : 'Benutzer'}</td>
                <td className="muted">{i.note ?? '–'}</td>
                <td>
                  <span className={`badge ${i.status === 'OPEN' ? 'success' : i.status === 'USED' ? 'primary' : ''}`}>
                    {{ OPEN: 'offen', USED: 'verwendet', EXPIRED: 'abgelaufen', REVOKED: 'widerrufen' }[i.status]}
                  </span>
                </td>
                <td className="dim">{formatDate(i.expiresAt)}</td>
                <td>{i.usedBy ?? '–'}</td>
                <td>
                  {i.status === 'OPEN' && (
                    <button
                      className="btn small danger"
                      onClick={async () => {
                        await api(`/admin/invites/${i.id}`, { method: 'DELETE' });
                        invites.reload();
                      }}
                    >
                      Widerrufen
                    </button>
                  )}
                </td>
              </tr>
            ))}
            {invites.data?.items.length === 0 && (
              <tr>
                <td colSpan={6} className="muted">
                  Keine Einladungen.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      {creating && (
        <CreateUserModal
          onClose={() => setCreating(false)}
          onCreated={() => {
            setCreating(false);
            users.reload();
          }}
        />
      )}
      {inviteOpen && <InviteModal onClose={() => { setInviteOpen(false); invites.reload(); }} />}
    </>
  );
}

function ResetPassword({ user, onError }: { user: AdminUser; onError: (e: string) => void }) {
  return (
    <button
      className="btn small ghost"
      onClick={async () => {
        const pw = prompt(`Neues Passwort für ${user.username} (mind. 10 Zeichen):`);
        if (!pw) return;
        try {
          await api(`/admin/users/${user.id}`, { method: 'PATCH', body: { password: pw } });
          alert('Passwort geändert. Alle Sitzungen des Benutzers wurden beendet.');
        } catch (e) {
          onError(errorMessage(e));
        }
      }}
    >
      Passwort
    </button>
  );
}

function CreateUserModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [username, setUsername] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState<'USER' | 'ADMIN'>('USER');
  const [error, setError] = useState<string | null>(null);
  return (
    <Modal title="Benutzer anlegen" onClose={onClose}>
      <form
        className="stack"
        onSubmit={async (e) => {
          e.preventDefault();
          try {
            await api('/admin/users', { method: 'POST', body: { username, password, role, displayName: displayName || undefined } });
            onCreated();
          } catch (err) {
            setError(errorMessage(err));
          }
        }}
      >
        <label className="field">
          Benutzername
          <input value={username} onChange={(e) => setUsername(e.target.value)} required minLength={3} maxLength={32} autoComplete="off" />
        </label>
        <label className="field">
          Anzeigename (optional)
          <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
        </label>
        <label className="field">
          Startpasswort (mind. 10 Zeichen)
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={10} autoComplete="new-password" />
        </label>
        <label className="field">
          Rolle
          <select value={role} onChange={(e) => setRole(e.target.value as 'USER' | 'ADMIN')}>
            <option value="USER">Benutzer</option>
            <option value="ADMIN">Administrator (kann auch Musik hören)</option>
          </select>
        </label>
        <ErrorBox error={error} />
        <button className="btn primary">Anlegen</button>
      </form>
    </Modal>
  );
}

function InviteModal({ onClose }: { onClose: () => void }) {
  const [role, setRole] = useState<'USER' | 'ADMIN'>('USER');
  const [hours, setHours] = useState(72);
  const [note, setNote] = useState('');
  const [link, setLink] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  return (
    <Modal title="Einladung erstellen" onClose={onClose}>
      {link ? (
        <div className="stack">
          <div className="alert success">Einladung erstellt. Der Link wird nur jetzt angezeigt:</div>
          <input readOnly value={link} onFocus={(e) => e.target.select()} />
          <button className="btn primary" onClick={() => navigator.clipboard?.writeText(link)}>
            Link kopieren
          </button>
        </div>
      ) : (
        <div className="stack">
          <label className="field">
            Rolle
            <select value={role} onChange={(e) => setRole(e.target.value as 'USER' | 'ADMIN')}>
              <option value="USER">Benutzer</option>
              <option value="ADMIN">Administrator</option>
            </select>
          </label>
          <label className="field">
            Gültigkeit (Stunden)
            <input type="number" min={1} max={720} value={hours} onChange={(e) => setHours(Number(e.target.value))} />
          </label>
          <label className="field">
            Notiz (z. B. für wen)
            <input value={note} onChange={(e) => setNote(e.target.value)} maxLength={200} />
          </label>
          <ErrorBox error={error} />
          <button
            className="btn primary"
            onClick={async () => {
              try {
                const r = await api<{ link: string }>('/admin/invites', { method: 'POST', body: { role, expiresInHours: hours, note: note || undefined } });
                setLink(r.link);
              } catch (e) {
                setError(errorMessage(e));
              }
            }}
          >
            Erstellen
          </button>
        </div>
      )}
    </Modal>
  );
}
