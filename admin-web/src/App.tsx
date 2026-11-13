import { useState } from 'react';
import { NavLink, Navigate, Route, Routes, useLocation } from 'react-router';
import { useAuth } from './lib/auth';
import { LoginPage } from './pages/Login';
import { InvitePage } from './pages/Invite';
import { DashboardPage } from './pages/Dashboard';
import { ArtistsPage } from './pages/Artists';
import { UploadPage } from './pages/Upload';
import { ReleasesPage } from './pages/Releases';
import { ReleaseDetailPage } from './pages/ReleaseDetail';
import { UsersPage } from './pages/Users';
import { JobsPage } from './pages/Jobs';
import { ConfirmEmailPage, EmailBanner, ForgotPasswordPage, ResetPasswordPage, SetupPage } from './pages/Account';

const NAV = [
  { to: '/', label: 'Übersicht', icon: '◉', end: true },
  { to: '/upload', label: 'Upload', icon: '⇪' },
  { to: '/kuenstler', label: 'Künstler', icon: '♪' },
  { to: '/veroeffentlichungen', label: 'Veröffentlichungen', icon: '◎' },
  { to: '/benutzer', label: 'Benutzer', icon: '☺' },
  { to: '/auftraege', label: 'Aufträge & Probleme', icon: '⟳' },
];

export function App() {
  const { user, loading, logout } = useAuth();
  const location = useLocation();
  const [navOpen, setNavOpen] = useState(false);

  // Öffentliche Seiten (ohne Anmeldung, auch für App-Nutzer)
  if (/^\/(einladung\/|passwort-vergessen|konto\/)/.test(location.pathname)) {
    return (
      <Routes>
        <Route path="/einladung/:code" element={<InvitePage />} />
        <Route path="/passwort-vergessen" element={<ForgotPasswordPage />} />
        <Route path="/konto/passwort-zuruecksetzen" element={<ResetPasswordPage />} />
        <Route path="/konto/email-bestaetigen" element={<ConfirmEmailPage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    );
  }
  if (loading) return <div className="login-wrap muted">Lade …</div>;
  if (!user) return <LoginPage />;
  if (user.mustChangePassword) return <SetupPage />;
  if (user.role !== 'ADMIN') {
    return (
      <div className="login-wrap">
        <div className="card login-card stack" style={{ textAlign: 'center' }}>
          <h2>Kein Zugriff</h2>
          <p className="muted">Die Verwaltung ist nur für Administratoren. Musik hörst du in der Demonify-App.</p>
          <button className="btn" onClick={logout}>
            Abmelden
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="shell">
      <div className="topbar-mobile">
        <button className="icon-btn" aria-label="Menü öffnen" onClick={() => setNavOpen(true)}>
          ☰
        </button>
        <strong>Demonify Verwaltung</strong>
      </div>
      <nav className={`sidebar ${navOpen ? 'open' : ''}`} aria-label="Hauptnavigation" onClick={() => setNavOpen(false)}>
        <div className="brand">
          <img src="/admin/icon-192.png" alt="" />
          <div>
            Demonify
            <small>Verwaltung</small>
          </div>
        </div>
        {NAV.map((n) => (
          <NavLink key={n.to} to={n.to} end={n.end} className={({ isActive }) => `nav-link ${isActive ? 'active' : ''}`}>
            <span aria-hidden>{n.icon}</span> {n.label}
          </NavLink>
        ))}
        <div className="spacer" />
        <div className="dim" style={{ padding: '0 12px 8px' }}>
          Angemeldet als <strong>{user.username}</strong>
        </div>
        <button className="btn ghost" onClick={logout}>
          Abmelden
        </button>
      </nav>
      <main className="main">
        <EmailBanner />
        <Routes>
          <Route path="/" element={<DashboardPage />} />
          <Route path="/upload" element={<UploadPage />} />
          <Route path="/kuenstler" element={<ArtistsPage />} />
          <Route path="/veroeffentlichungen" element={<ReleasesPage />} />
          <Route path="/veroeffentlichungen/:id" element={<ReleaseDetailPage />} />
          <Route path="/benutzer" element={<UsersPage />} />
          <Route path="/auftraege" element={<JobsPage />} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>
    </div>
  );
}
