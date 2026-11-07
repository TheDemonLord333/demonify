import { Link } from 'react-router';
import { api, errorMessage, type Job, type Page } from '../lib/api';
import { useApi, useInterval } from '../lib/hooks';
import { ErrorBox, JobStatusBadge, Progress } from '../components/ui';
import { formatDate } from '../lib/format';
import { useState } from 'react';

interface Stats {
  artists: number;
  releases: number;
  tracks: number;
  unavailable: number;
  needsReview: number;
  users: number;
  openIssues: number;
  runningJobs: number;
}

export function DashboardPage() {
  const stats = useApi<Stats>('/admin/stats');
  const jobs = useApi<Page<Job>>('/admin/jobs?limit=5');
  const [msg, setMsg] = useState<string | null>(null);
  const running = jobs.data?.items.some((j) => j.status === 'RUNNING' || j.status === 'QUEUED');
  useInterval(() => {
    jobs.reload();
    stats.reload();
  }, running ? 2000 : null);

  const scan = async () => {
    try {
      await api('/admin/library/scan', { method: 'POST' });
      setMsg('Bibliotheksscan gestartet.');
      jobs.reload();
    } catch (e) {
      setMsg(errorMessage(e));
    }
  };

  const s = stats.data;
  return (
    <>
      <div className="row between">
        <h1>Übersicht</h1>
        <div className="row">
          <Link className="btn primary" to="/upload">
            Musik hochladen
          </Link>
          <button className="btn" onClick={scan}>
            Bibliothek scannen
          </button>
        </div>
      </div>
      {msg && <div className="alert info" style={{ marginBottom: 16 }}>{msg}</div>}
      <ErrorBox error={stats.error} />
      {s && (
        <div className="grid stats">
          <Stat label="Künstler" value={s.artists} />
          <Stat label="Veröffentlichungen" value={s.releases} />
          <Stat label="Songs" value={s.tracks} />
          <Stat label="Benutzer" value={s.users} />
          <Stat label="Nicht verfügbar" value={s.unavailable} warn={s.unavailable > 0} />
          <Stat label="Metadaten prüfen" value={s.needsReview} warn={s.needsReview > 0} />
          <Stat label="Offene Probleme" value={s.openIssues} warn={s.openIssues > 0} />
          <Stat label="Laufende Aufträge" value={s.runningJobs} />
        </div>
      )}
      <h2>Letzte Aufträge</h2>
      <div className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th>Typ</th>
              <th>Status</th>
              <th>Fortschritt</th>
              <th>Erstellt</th>
            </tr>
          </thead>
          <tbody>
            {jobs.data?.items.map((j) => (
              <tr key={j.id}>
                <td>{jobLabel(j.type)}</td>
                <td>
                  <JobStatusBadge status={j.status} />
                </td>
                <td style={{ minWidth: 160 }}>
                  <Progress value={j.progress} state={j.status === 'SUCCEEDED' ? 'done' : j.status === 'FAILED' ? 'error' : undefined} />
                  <div className="dim ellipsis" style={{ maxWidth: 320 }}>{j.error ?? j.message}</div>
                </td>
                <td className="dim">{formatDate(j.createdAt)}</td>
              </tr>
            ))}
            {jobs.data?.items.length === 0 && (
              <tr>
                <td colSpan={4} className="muted">
                  Noch keine Aufträge.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}

export function jobLabel(t: Job['type']) {
  return { LIBRARY_SCAN: 'Bibliotheksscan', TRANSCODE: 'Transkodierung', UPLOAD_CLEANUP: 'Upload-Bereinigung' }[t] ?? t;
}

function Stat({ label, value, warn }: { label: string; value: number; warn?: boolean }) {
  return (
    <div className={`stat ${warn ? 'warn' : ''}`}>
      <div className="value">{value.toLocaleString('de-DE')}</div>
      <div className="label">{label}</div>
    </div>
  );
}
