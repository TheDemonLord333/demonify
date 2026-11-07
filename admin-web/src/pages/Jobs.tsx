import { useState } from 'react';
import { Link } from 'react-router';
import { api, errorMessage, type Job, type Page, type Track } from '../lib/api';
import { useApi, useInterval } from '../lib/hooks';
import { formatDate } from '../lib/format';
import { Cover, ErrorBox, JobStatusBadge, Progress } from '../components/ui';
import { jobLabel } from './Dashboard';
import { TrackEditModal } from './ReleaseDetail';

interface Issue {
  id: string;
  kind: 'FILE_ERROR' | 'MISSING_FILE' | 'INCOMPLETE_METADATA' | 'TRANSCODE_ERROR';
  relPath: string;
  trackId: string | null;
  message: string;
  updatedAt: string;
}

const ISSUE_LABEL: Record<Issue['kind'], string> = {
  FILE_ERROR: 'Fehlerhafte Datei',
  MISSING_FILE: 'Datei fehlt',
  INCOMPLETE_METADATA: 'Metadaten unvollständig',
  TRANSCODE_ERROR: 'Transkodierung fehlgeschlagen',
};

export function JobsPage() {
  const jobs = useApi<Page<Job>>('/admin/jobs?limit=30');
  const issues = useApi<Page<Issue>>('/admin/issues?limit=100');
  const unavailable = useApi<Page<Track>>('/admin/tracks?available=false&limit=100');
  const review = useApi<Page<Track>>('/admin/tracks?needsReview=true&limit=100');
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState<Track | null>(null);
  const running = jobs.data?.items.some((j) => j.status === 'RUNNING' || j.status === 'QUEUED');
  useInterval(() => {
    jobs.reload();
    if (!running) {
      issues.reload();
      unavailable.reload();
    }
  }, running ? 1500 : null);

  const run = async (path: string) => {
    setError(null);
    try {
      await api(path, { method: 'POST' });
      jobs.reload();
    } catch (e) {
      setError(errorMessage(e));
    }
  };

  const reloadAll = () => {
    issues.reload();
    unavailable.reload();
    review.reload();
  };

  return (
    <>
      <div className="row between">
        <h1>Aufträge & Probleme</h1>
        <div className="row">
          <button className="btn primary" onClick={() => run('/admin/library/scan')}>
            Bibliotheksscan starten
          </button>
          <button className="btn" onClick={() => run('/admin/uploads/cleanup')}>
            Alte Uploads bereinigen
          </button>
        </div>
      </div>
      <ErrorBox error={error} />

      <h2>Aufträge</h2>
      <div className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th>Typ</th>
              <th>Status</th>
              <th style={{ minWidth: 220 }}>Fortschritt</th>
              <th>Ergebnis</th>
              <th>Erstellt</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {jobs.data?.items.map((j) => (
              <tr key={j.id}>
                <td>{jobLabel(j.type)}</td>
                <td>
                  <JobStatusBadge status={j.status} />
                </td>
                <td>
                  <Progress value={j.progress} state={j.status === 'SUCCEEDED' ? 'done' : j.status === 'FAILED' ? 'error' : undefined} />
                  <div className="dim">
                    {j.total > 0 ? `${j.done}/${j.total} · ` : ''}
                    <span className="ellipsis">{j.message}</span>
                  </div>
                </td>
                <td className="dim" style={{ maxWidth: 320 }}>
                  {j.error ? <span style={{ color: 'var(--danger)' }}>{j.error}</span> : j.result ? summarize(j.result) : '–'}
                </td>
                <td className="dim">{formatDate(j.createdAt)}</td>
                <td>
                  {(j.status === 'RUNNING' || j.status === 'QUEUED') && (
                    <button className="btn small ghost" onClick={() => run(`/admin/jobs/${j.id}/cancel`)}>
                      Abbrechen
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>Nicht verfügbare Dateien ({unavailable.data?.total ?? 0})</h2>
      <TrackTable tracks={unavailable.data?.items ?? []} onEdit={setEditing} />

      <h2>Metadaten zur Korrektur ({review.data?.total ?? 0})</h2>
      <TrackTable tracks={review.data?.items ?? []} onEdit={setEditing} />

      <h2>Offene Probleme ({issues.data?.total ?? 0})</h2>
      <div className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th>Art</th>
              <th>Datei</th>
              <th>Meldung</th>
              <th>Zuletzt</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {issues.data?.items.map((i) => (
              <tr key={i.id}>
                <td>
                  <span className={`badge ${i.kind === 'INCOMPLETE_METADATA' ? 'warn' : 'danger'}`}>{ISSUE_LABEL[i.kind]}</span>
                </td>
                <td className="ellipsis" style={{ maxWidth: 320 }} title={i.relPath}>
                  {i.relPath}
                </td>
                <td className="dim" style={{ maxWidth: 320 }}>
                  {i.message}
                </td>
                <td className="dim">{formatDate(i.updatedAt)}</td>
                <td>
                  <button
                    className="btn small ghost"
                    onClick={async () => {
                      await api(`/admin/issues/${i.id}/resolve`, { method: 'POST' });
                      issues.reload();
                    }}
                  >
                    Erledigt
                  </button>
                </td>
              </tr>
            ))}
            {issues.data?.items.length === 0 && (
              <tr>
                <td colSpan={5} className="muted">
                  Keine offenen Probleme.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      {editing && (
        <TrackEditModal
          track={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            reloadAll();
          }}
        />
      )}
    </>
  );
}

function TrackTable({ tracks, onEdit }: { tracks: Track[]; onEdit: (t: Track) => void }) {
  if (tracks.length === 0) return <div className="card muted">Keine Einträge.</div>;
  return (
    <div className="card table-wrap">
      <table>
        <tbody>
          {tracks.map((t) => (
            <tr key={t.id}>
              <td style={{ width: 52 }}>
                <Cover id={t.coverImageId} size={36} />
              </td>
              <td>
                <strong>{t.title}</strong>
                <div className="dim">
                  {t.artists.map((a) => a.name).join(', ')} · <Link to={`/veroeffentlichungen/${t.release.id}`}>{t.release.title}</Link>
                </div>
              </td>
              <td className="dim ellipsis" style={{ maxWidth: 360 }} title={t.audioPath}>
                {t.audioPath}
              </td>
              <td>
                <button className="btn small" onClick={() => onEdit(t)}>
                  Bearbeiten
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function summarize(r: Record<string, unknown>): string {
  if ('filesSeen' in r) {
    return `${r.filesSeen} Dateien · ${r.added} neu · ${r.updated} geändert · ${r.moved} verschoben · ${r.missing} fehlend · ${r.errors} Fehler`;
  }
  if ('expired' in r) return `${r.expired} abgelaufen, ${r.orphans} verwaist entfernt`;
  if ('bytes' in r) return `${Math.round(Number(r.bytes) / 1024)} KB erzeugt`;
  return JSON.stringify(r);
}
