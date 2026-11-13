import { useState } from 'react';
import { Link } from 'react-router';
import { api, ApiError, errorMessage, type Artist, type Page } from '../lib/api';
import { useApi, useDebounced } from '../lib/hooks';
import { uploadFile } from '../lib/upload';
import { Cover, Empty, ErrorBox, Modal, Progress } from '../components/ui';
import { CreateArtistModal } from '../components/ArtistPicker';
import { ImageCropper, type Crop } from '../components/ImageCropper';

type Origin = 'MANUAL' | 'SCAN' | 'LEGACY';
type AdminArtist = Artist & { releaseCount: number; trackCount: number; folder: string | null; origin: Origin };

const ORIGIN_LABEL: Record<Origin, string> = { MANUAL: 'manuell', SCAN: 'automatisch (Scan)', LEGACY: 'Altbestand' };
const ORIGIN_HINT: Record<Origin, string> = {
  MANUAL: 'Bleibt auch ohne Veröffentlichungen bestehen.',
  SCAN: 'Wird nach einem Scan entfernt, sobald keine Veröffentlichung mehr auf ihn verweist.',
  LEGACY: 'Herkunft unklar (vor der Erfassung angelegt) – wird nicht automatisch entfernt.',
};

interface DeletePreview {
  ownReleases: number;
  ownTracks: number;
  otherReleases: number;
  otherTracks: number;
  followers: number;
}

export function ArtistsPage() {
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 150);
  const [offset, setOffset] = useState(0);
  const list = useApi<Page<AdminArtist>>(`/admin/artists?limit=50&offset=${offset}${dq ? `&q=${encodeURIComponent(dq)}` : ''}`);
  const [creating, setCreating] = useState(false);
  const [editing, setEditing] = useState<AdminArtist | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const setOrigin = async (a: AdminArtist, origin: Origin) => {
    setError(null);
    try {
      await api(`/admin/artists/${a.id}`, { method: 'PATCH', body: { origin } });
      list.reload();
    } catch (e) {
      setError(errorMessage(e));
    }
  };

  const remove = async (a: AdminArtist) => {
    setError(null);
    setNotice(null);
    try {
      const p = await api<DeletePreview>(`/admin/artists/${a.id}/delete-preview`);
      const lines = [`Künstler „${a.name}“ löschen?`, ''];
      if (p.ownReleases)
        lines.push(
          `• ${p.ownReleases} eigene Veröffentlichung(en) mit ${p.ownTracks} Song(s) werden aus dem Katalog entfernt. Die Audiodateien werden in den Papierkorb-Ordner „.demonify-papierkorb“ im Musikverzeichnis verschoben (nicht endgültig gelöscht) und kehren beim Scan nicht zurück.`,
        );
      if (p.otherReleases)
        lines.push(`• Auf ${p.otherReleases} fremden/gemeinsamen Veröffentlichung(en) (${p.otherTracks} Song(s)) wird nur die Mitwirkung entfernt – diese bleiben verfügbar.`);
      if (p.followers) lines.push(`• ${p.followers} Person(en) folgen diesem Künstler.`);
      if (!p.ownReleases && !p.otherReleases) lines.push('Der Künstler ist mit keiner Veröffentlichung verbunden.');
      lines.push('', 'Playlists und Favoriten mit den entfernten Songs verlieren diese Einträge.');
      if (!confirm(lines.join('\n'))) return;
      const r = await api<{ removedReleases: number; removedTracks: number; movedFiles: number; trashFolder: string | null }>(`/admin/artists/${a.id}`, {
        method: 'DELETE',
      });
      setNotice(
        `„${a.name}“ gelöscht: ${r.removedReleases} Veröffentlichung(en), ${r.removedTracks} Song(s) entfernt` +
          (r.trashFolder ? `; ${r.movedFiles} Datei(en) liegen in „${r.trashFolder}“.` : '.'),
      );
      list.reload();
    } catch (e) {
      setError(errorMessage(e));
    }
  };

  return (
    <>
      <div className="row between">
        <h1>Künstler</h1>
        <button className="btn primary" onClick={() => setCreating(true)}>
          ＋ Künstler anlegen
        </button>
      </div>
      <input
        placeholder="Künstler filtern …"
        value={q}
        onChange={(e) => {
          setQ(e.target.value);
          setOffset(0);
        }}
        style={{ marginBottom: 16, maxWidth: 420 }}
      />
      <ErrorBox error={error ?? list.error} />
      {notice && <div className="alert success" style={{ marginBottom: 12 }}>{notice}</div>}
      {list.data && list.data.items.length === 0 && <Empty>Keine Künstler gefunden.</Empty>}
      <div className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th></th>
              <th>Name</th>
              <th>Veröffentlichungen</th>
              <th>Songs</th>
              <th>Ordner</th>
              <th>Herkunft</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {list.data?.items.map((a) => (
              <tr key={a.id}>
                <td style={{ width: 56 }}>
                  <Cover id={a.imageId} size={40} round />
                </td>
                <td>
                  <strong>{a.name}</strong>
                </td>
                <td>
                  <Link to={`/veroeffentlichungen?artistId=${a.id}`}>{a.releaseCount}</Link>
                </td>
                <td>{a.trackCount}</td>
                <td className="dim ellipsis" style={{ maxWidth: 240 }}>
                  {a.folder ?? '–'}
                </td>
                <td title={ORIGIN_HINT[a.origin]}>
                  <select value={a.origin} onChange={(e) => setOrigin(a, e.target.value as Origin)} aria-label="Herkunft">
                    {a.origin === 'LEGACY' && <option value="LEGACY">{ORIGIN_LABEL.LEGACY}</option>}
                    <option value="MANUAL">{ORIGIN_LABEL.MANUAL}</option>
                    <option value="SCAN">{ORIGIN_LABEL.SCAN}</option>
                  </select>
                </td>
                <td style={{ textAlign: 'right' }}>
                  <div className="row" style={{ justifyContent: 'flex-end', gap: 6 }}>
                    <button className="btn small" onClick={() => setEditing(a)}>
                      Bearbeiten
                    </button>
                    <button className="btn small danger" onClick={() => remove(a)}>
                      Löschen
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {list.data && (
        <div className="row" style={{ marginTop: 12 }}>
          <button className="btn small" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - 50))}>
            Zurück
          </button>
          <span className="dim">
            {list.data.total === 0 ? 0 : offset + 1}–{offset + list.data.items.length} von {list.data.total}
          </span>
          <button className="btn small" disabled={list.data.nextOffset === null} onClick={() => setOffset(list.data!.nextOffset!)}>
            Weiter
          </button>
        </div>
      )}
      {creating && (
        <CreateArtistModal
          initialName=""
          onClose={() => setCreating(false)}
          onCreated={() => {
            setCreating(false);
            list.reload();
          }}
        />
      )}
      {editing && (
        <EditArtistModal
          artist={editing}
          onClose={() => setEditing(null)}
          onChanged={() => {
            list.reload();
          }}
        />
      )}
    </>
  );
}

function EditArtistModal({ artist, onClose, onChanged }: { artist: AdminArtist; onClose: () => void; onChanged: () => void }) {
  const [name, setName] = useState(artist.name);
  const [imageId, setImageId] = useState(artist.imageId);
  const [file, setFile] = useState<File | null>(null);
  const [crop, setCrop] = useState<Crop | null>(null);
  const [progress, setProgress] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const saveName = async () => {
    setBusy(true);
    setError(null);
    try {
      await api(`/admin/artists/${artist.id}`, { method: 'PATCH', body: { name } });
      onChanged();
    } catch (e) {
      setError(e instanceof ApiError && e.code === 'ARTIST_EXISTS' ? e.message : errorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  const uploadImage = async () => {
    if (!file || !crop) return;
    setBusy(true);
    setError(null);
    try {
      const ctrl = new AbortController();
      const up = await uploadFile(file, 'IMAGE', { signal: ctrl.signal, onProgress: (p) => setProgress(p.sent / p.total) });
      if (up.status !== 'VALIDATED') throw new Error(up.error ?? 'Bild ungültig.');
      const r = await api<{ artist: Artist }>(`/admin/artists/${artist.id}/image`, { method: 'PUT', body: { uploadId: up.id, crop } });
      setImageId(r.artist.imageId);
      setFile(null);
      onChanged();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setBusy(false);
      setProgress(null);
    }
  };

  const removeImage = async () => {
    if (!confirm('Profilbild entfernen? Die Datei bleibt im Musikordner erhalten.')) return;
    try {
      await api(`/admin/artists/${artist.id}/image`, { method: 'DELETE' });
      setImageId(null);
      onChanged();
    } catch (e) {
      setError(errorMessage(e));
    }
  };

  const remove = async () => {
    if (!confirm(`Künstler „${artist.name}“ löschen?`)) return;
    try {
      await api(`/admin/artists/${artist.id}`, { method: 'DELETE' });
      onChanged();
      onClose();
    } catch (e) {
      setError(errorMessage(e));
    }
  };

  return (
    <Modal title="Künstler bearbeiten" onClose={onClose}>
      <div className="stack">
        <label className="field">
          Name
          <div className="row" style={{ flexWrap: 'nowrap' }}>
            <input value={name} onChange={(e) => setName(e.target.value)} />
            <button className="btn primary" disabled={busy || !name.trim() || name === artist.name} onClick={saveName}>
              Speichern
            </button>
          </div>
        </label>
        <h3>Profilbild</h3>
        <div className="row">
          <Cover id={imageId} size={96} round />
          <div className="stack">
            <label className="btn small">
              Bild auswählen
              <input type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
            </label>
            {imageId && (
              <button className="btn small danger" onClick={removeImage}>
                Profilbild entfernen
              </button>
            )}
          </div>
        </div>
        {file && (
          <>
            <p className="dim">Ausschnitt verschieben und zoomen:</p>
            <ImageCropper file={file} onChange={setCrop} />
            {progress !== null && <Progress value={progress} />}
            <button className="btn primary" disabled={busy || !crop} onClick={uploadImage}>
              {imageId ? 'Profilbild ersetzen' : 'Profilbild hochladen'}
            </button>
          </>
        )}
        <ErrorBox error={error} />
        {artist.releaseCount === 0 && artist.trackCount === 0 && (
          <button className="btn danger" onClick={remove}>
            Künstler löschen
          </button>
        )}
      </div>
    </Modal>
  );
}
