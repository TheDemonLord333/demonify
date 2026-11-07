import { useEffect, useState } from 'react';
import { useParams } from 'react-router';
import { api, errorMessage, RELEASE_TYPE_LABEL, type Artist, type Release, type Track } from '../lib/api';
import { useApi } from '../lib/hooks';
import { uploadFile } from '../lib/upload';
import { formatDuration } from '../lib/format';
import { ArtistPicker } from '../components/ArtistPicker';
import { Cover, ErrorBox, Modal, Progress } from '../components/ui';

type Detail = { release: Release & { folder: string | null; metaLocked: boolean; coverLocked: boolean }; tracks: Track[] };

async function uploadImage(file: File, onProgress: (v: number) => void): Promise<string> {
  const ctrl = new AbortController();
  const up = await uploadFile(file, 'IMAGE', { signal: ctrl.signal, onProgress: (p) => onProgress(p.sent / p.total) });
  if (up.status !== 'VALIDATED') throw new Error(up.error ?? 'Bild ungültig.');
  return up.id;
}

export function ReleaseDetailPage() {
  const { id = '' } = useParams();
  const detail = useApi<Detail>(`/admin/releases/${id}`);
  const [form, setForm] = useState<{ title: string; type: Release['type']; year: string; genre: string } | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [coverProgress, setCoverProgress] = useState<number | null>(null);
  const [order, setOrder] = useState<Track[] | null>(null);
  const [editing, setEditing] = useState<Track | null>(null);

  useEffect(() => {
    if (detail.data) {
      const r = detail.data.release;
      setForm({ title: r.title, type: r.type, year: r.year ? String(r.year) : '', genre: r.genre ?? '' });
      setOrder(null);
    }
  }, [detail.data]);

  if (detail.error) return <ErrorBox error={detail.error} />;
  if (!detail.data || !form) return <p className="muted">Lade …</p>;
  const { release, tracks } = detail.data;

  const save = async () => {
    try {
      await api(`/admin/releases/${id}`, {
        method: 'PATCH',
        body: { title: form.title, type: form.type, year: form.year ? Number(form.year) : null, genre: form.genre || null },
      });
      setMsg({ ok: true, text: 'Gespeichert.' });
      detail.reload();
    } catch (e) {
      setMsg({ ok: false, text: errorMessage(e) });
    }
  };

  const setCover = async (file: File) => {
    try {
      const uploadId = await uploadImage(file, setCoverProgress);
      await api(`/admin/releases/${id}/cover`, { method: 'PUT', body: { uploadId } });
      setMsg({ ok: true, text: 'Cover aktualisiert.' });
      detail.reload();
    } catch (e) {
      setMsg({ ok: false, text: errorMessage(e) });
    } finally {
      setCoverProgress(null);
    }
  };

  const current = order ?? tracks;
  const move = (i: number, dir: -1 | 1) => {
    const next = [...current];
    const j = i + dir;
    if (j < 0 || j >= next.length) return;
    [next[i], next[j]] = [next[j]!, next[i]!];
    setOrder(next);
  };
  const saveOrder = async () => {
    try {
      await api(`/admin/releases/${id}/order`, { method: 'PUT', body: { tracks: current.map((t) => ({ id: t.id, discNumber: t.discNumber })) } });
      setMsg({ ok: true, text: 'Reihenfolge gespeichert.' });
      detail.reload();
    } catch (e) {
      setMsg({ ok: false, text: errorMessage(e) });
    }
  };

  return (
    <>
      <div className="row" style={{ alignItems: 'flex-end', gap: 24, marginBottom: 24 }}>
        <Cover id={release.coverImageId} size={180} alt="Veröffentlichungscover" />
        <div className="stack" style={{ gap: 4 }}>
          <span className="badge primary" style={{ alignSelf: 'flex-start' }}>
            {RELEASE_TYPE_LABEL[release.type]}
          </span>
          <h1 style={{ margin: 0 }}>{release.title}</h1>
          <span className="muted">
            {release.albumArtist.name} · {release.year ?? 'ohne Jahr'} · {release.trackCount} Tracks
          </span>
          <span className="dim">Ordner: {release.folder ?? '–'}</span>
          <div className="row" style={{ marginTop: 8 }}>
            <label className="btn small">
              {release.coverImageId ? 'Cover ersetzen' : 'Cover hochladen'}
              <input type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => e.target.files?.[0] && setCover(e.target.files[0])} />
            </label>
            {release.coverImageId && (
              <button
                className="btn small ghost"
                onClick={async () => {
                  await api(`/admin/releases/${id}/cover`, { method: 'DELETE' });
                  detail.reload();
                }}
              >
                Cover entfernen
              </button>
            )}
            {coverProgress !== null && (
              <span style={{ width: 120 }}>
                <Progress value={coverProgress} />
              </span>
            )}
          </div>
        </div>
      </div>
      {msg && <div className={`alert ${msg.ok ? 'success' : 'error'}`} style={{ marginBottom: 16 }}>{msg.text}</div>}

      <div className="card stack">
        <h2 style={{ marginTop: 0 }}>Metadaten</h2>
        <div className="form-grid">
          <label className="field" style={{ gridColumn: '1 / -1' }}>
            Titel
            <input value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
          </label>
          <label className="field">
            Typ
            <select value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value as Release['type'] })}>
              <option value="ALBUM">Album</option>
              <option value="EP">EP</option>
              <option value="SINGLE">Single</option>
            </select>
          </label>
          <label className="field">
            Jahr
            <input type="number" value={form.year} onChange={(e) => setForm({ ...form, year: e.target.value })} />
          </label>
          <label className="field">
            Genre
            <input value={form.genre} onChange={(e) => setForm({ ...form, genre: e.target.value })} />
          </label>
        </div>
        <p className="dim">Hinweis: Änderungen wirken in der Datenbank. Bestehende Ordnernamen bleiben unverändert, damit keine Dateien verschoben werden.</p>
        <button className="btn primary" style={{ alignSelf: 'flex-start' }} onClick={save}>
          Speichern
        </button>
      </div>

      <div className="card">
        <div className="row between">
          <h2 style={{ marginTop: 0 }}>Tracks</h2>
          {order && (
            <div className="row">
              <button className="btn ghost small" onClick={() => setOrder(null)}>
                Verwerfen
              </button>
              <button className="btn primary small" onClick={saveOrder}>
                Reihenfolge speichern
              </button>
            </div>
          )}
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th></th>
                <th>#</th>
                <th></th>
                <th>Titel</th>
                <th>Künstler</th>
                <th>Dauer</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {current.map((t, i) => (
                <tr key={t.id}>
                  <td style={{ whiteSpace: 'nowrap' }}>
                    <button className="icon-btn" aria-label="Nach oben" onClick={() => move(i, -1)} disabled={i === 0}>
                      ▲
                    </button>
                    <button className="icon-btn" aria-label="Nach unten" onClick={() => move(i, 1)} disabled={i === current.length - 1}>
                      ▼
                    </button>
                  </td>
                  <td className="dim">
                    {t.discNumber > 1 ? `${t.discNumber}-` : ''}
                    {t.trackNumber}
                  </td>
                  <td>
                    <Cover id={t.coverImageId} size={40} />
                  </td>
                  <td>
                    <strong>{t.title}</strong>
                    {t.hasOwnCover && <span className="badge success" style={{ marginLeft: 8 }}>eigenes Cover</span>}
                  </td>
                  <td className="muted">
                    {t.artists.map((a) => (a.role === 'FEATURED' ? `feat. ${a.name}` : a.name)).join(', ')}
                  </td>
                  <td>{formatDuration(t.durationMs)}</td>
                  <td>
                    {!t.available && <span className="badge danger">nicht verfügbar</span>}
                    {t.needsReview && <span className="badge warn">prüfen</span>}
                    {t.available && !t.needsReview && <span className="badge">{t.codec}</span>}
                  </td>
                  <td>
                    <button className="btn small" onClick={() => setEditing(t)}>
                      Bearbeiten
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      {editing && (
        <TrackEditModal
          track={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            detail.reload();
          }}
        />
      )}
    </>
  );
}

export function TrackEditModal({ track, onClose, onSaved }: { track: Track; onClose: () => void; onSaved: () => void }) {
  const [title, setTitle] = useState(track.title);
  const [disc, setDisc] = useState(track.discNumber);
  const [num, setNum] = useState(track.trackNumber);
  const [genre, setGenre] = useState(track.genre ?? '');
  const [year, setYear] = useState(track.year ? String(track.year) : '');
  const [artists, setArtists] = useState<Artist[]>(track.artists.filter((a) => a.role === 'PRIMARY').map((a) => ({ id: a.id, name: a.name, imageId: null })));
  const [features, setFeatures] = useState<Artist[]>(track.artists.filter((a) => a.role === 'FEATURED').map((a) => ({ id: a.id, name: a.name, imageId: null })));
  const [error, setError] = useState<string | null>(null);
  const [progress, setProgress] = useState<number | null>(null);

  const save = async () => {
    try {
      await api(`/admin/tracks/${track.id}`, {
        method: 'PATCH',
        body: {
          title,
          discNumber: disc,
          trackNumber: num,
          genre: genre || null,
          year: year ? Number(year) : null,
          artistIds: artists.map((a) => a.id),
          featuredArtistIds: features.map((a) => a.id),
        },
      });
      onSaved();
    } catch (e) {
      setError(errorMessage(e));
    }
  };

  const setCover = async (file: File) => {
    try {
      const uploadId = await uploadImage(file, setProgress);
      await api(`/admin/tracks/${track.id}/cover`, { method: 'PUT', body: { uploadId } });
      onSaved();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setProgress(null);
    }
  };

  const removeFromCatalog = async () => {
    if (!confirm('Nicht verfügbaren Song aus dem Katalog entfernen? Playlists/Verlauf verlieren diesen Eintrag.')) return;
    try {
      await api(`/admin/tracks/${track.id}`, { method: 'DELETE' });
      onSaved();
    } catch (e) {
      setError(errorMessage(e));
    }
  };

  return (
    <Modal title="Song bearbeiten" onClose={onClose} wide>
      <div className="stack">
        <div className="row">
          <Cover id={track.coverImageId} size={72} />
          <div className="stack" style={{ gap: 6 }}>
            <label className="btn small">
              Individuelles Songcover {track.hasOwnCover ? 'ersetzen' : 'zuordnen'}
              <input type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => e.target.files?.[0] && setCover(e.target.files[0])} />
            </label>
            {track.hasOwnCover && (
              <button
                className="btn small ghost"
                onClick={async () => {
                  await api(`/admin/tracks/${track.id}/cover`, { method: 'DELETE' });
                  onSaved();
                }}
              >
                Songcover entfernen (Veröffentlichungscover nutzen)
              </button>
            )}
            {progress !== null && <Progress value={progress} />}
          </div>
        </div>
        <div className="form-grid">
          <label className="field" style={{ gridColumn: '1 / -1' }}>
            Titel
            <input value={title} onChange={(e) => setTitle(e.target.value)} />
          </label>
          <label className="field">
            Disc
            <input type="number" min={1} value={disc} onChange={(e) => setDisc(Number(e.target.value) || 1)} />
          </label>
          <label className="field">
            Tracknummer
            <input type="number" min={1} value={num} onChange={(e) => setNum(Number(e.target.value) || 1)} />
          </label>
          <label className="field">
            Genre
            <input value={genre} onChange={(e) => setGenre(e.target.value)} />
          </label>
          <label className="field">
            Jahr
            <input type="number" value={year} onChange={(e) => setYear(e.target.value)} />
          </label>
        </div>
        <Picker label="Künstler" list={artists} onChange={setArtists} />
        <Picker label="Features" list={features} onChange={setFeatures} />
        <ErrorBox error={error} />
        <div className="row between">
          {!track.available ? (
            <button className="btn danger" onClick={removeFromCatalog}>
              Aus Katalog entfernen
            </button>
          ) : (
            <span className="dim">{track.audioPath}</span>
          )}
          <button className="btn primary" disabled={!title.trim() || artists.length === 0} onClick={save}>
            Speichern
          </button>
        </div>
      </div>
    </Modal>
  );
}

function Picker({ label, list, onChange }: { label: string; list: Artist[]; onChange: (l: Artist[]) => void }) {
  return (
    <div className="stack" style={{ gap: 6 }}>
      <span className="dim">{label}</span>
      <div className="chips">
        {list.map((a) => (
          <span className="chip" key={a.id}>
            {a.name}
            <button aria-label="Entfernen" onClick={() => onChange(list.filter((x) => x.id !== a.id))}>
              ✕
            </button>
          </span>
        ))}
      </div>
      <ArtistPicker placeholder={`${label} hinzufügen …`} excludeIds={list.map((a) => a.id)} onSelect={(a) => onChange([...list, a])} />
    </div>
  );
}
