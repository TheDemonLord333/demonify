import { useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router';
import { api, errorMessage, RELEASE_TYPE_LABEL, type Artist, type Page, type Release } from '../lib/api';
import { abortUpload, uploadFile, type UploadInfo } from '../lib/upload';
import { formatBytes, formatDuration, uuid } from '../lib/format';
import { ArtistPicker } from '../components/ArtistPicker';
import { Cover, ErrorBox, Progress } from '../components/ui';

type RType = Release['type'];

interface FileUpload {
  file: File;
  uploadId: string | null;
  progress: number;
  status: 'uploading' | 'validating' | 'ready' | 'error' | 'cancelled';
  error: string | null;
  ctrl: AbortController;
  probe: UploadInfo['probe'];
}

interface TrackDraft {
  key: string;
  audio: FileUpload;
  title: string;
  disc: number;
  number: number;
  artists: Artist[];
  features: Artist[];
  genre: string;
  cover: FileUpload | null;
  coverPreview: string | null;
}

const STEPS = ['Künstler', 'Typ', 'Veröffentlichung', 'Metadaten & Cover', 'Audiodateien', 'Prüfen', 'Bestätigen'];

function startUpload(file: File, kind: 'AUDIO' | 'IMAGE', update: (f: Partial<FileUpload>) => void, existingId?: string): FileUpload {
  const ctrl = new AbortController();
  const fu: FileUpload = { file, uploadId: existingId ?? null, progress: 0, status: 'uploading', error: null, ctrl, probe: null };
  uploadFile(file, kind, {
    signal: ctrl.signal,
    existingId,
    onProgress: (p) => update({ progress: p.sent / p.total, status: p.phase === 'validate' ? 'validating' : 'uploading' }),
  })
    .then((u) => update({ uploadId: u.id, status: u.status === 'VALIDATED' ? 'ready' : 'error', error: u.error, probe: u.probe, progress: 1 }))
    .catch((e) => {
      if ((e as Error).name === 'AbortError') update({ status: 'cancelled' });
      else update({ status: 'error', error: errorMessage(e) });
    });
  return fu;
}

export function UploadPage() {
  const [step, setStep] = useState(0);
  const [artist, setArtist] = useState<Artist | null>(null);
  const [type, setType] = useState<RType>('ALBUM');
  const [mode, setMode] = useState<'new' | 'existing'>('new');
  const [existing, setExisting] = useState<Release | null>(null);
  const [title, setTitle] = useState('');
  const [year, setYear] = useState<string>(String(new Date().getFullYear()));
  const [genre, setGenre] = useState('');
  const [cover, setCover] = useState<FileUpload | null>(null);
  const [coverPreview, setCoverPreview] = useState<string | null>(null);
  const [tracks, setTracks] = useState<TrackDraft[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ releaseId: string; releaseFolder: string } | null>(null);
  const idempotencyKey = useRef(uuid());
  const [releases, setReleases] = useState<Release[]>([]);

  useEffect(() => {
    if (!artist) return;
    api<Page<Release>>(`/admin/releases?artistId=${artist.id}&type=${type}&limit=100`)
      .then((r) => setReleases(r.items))
      .catch(() => setReleases([]));
  }, [artist, type]);

  const updateTrack = (key: string, patch: Partial<TrackDraft>) => setTracks((ts) => ts.map((t) => (t.key === key ? { ...t, ...patch } : t)));
  const updateAudio = (key: string) => (patch: Partial<FileUpload>) =>
    setTracks((ts) => ts.map((t) => (t.key === key ? applyProbe({ ...t, audio: { ...t.audio, ...patch } }, patch) : t)));

  const applyProbe = (t: TrackDraft, patch: Partial<FileUpload>): TrackDraft => {
    // Vorschläge aus den gelesenen Tags übernehmen (nur wenn noch nicht bearbeitet)
    if (!patch.probe) return t;
    const tags = (patch.probe as { tags?: { title?: string; trackNumber?: number; discNumber?: number; genre?: string } }).tags ?? {};
    return {
      ...t,
      title: t.title === stripExt(t.audio.file.name) && tags.title ? tags.title : t.title,
      number: tags.trackNumber ?? t.number,
      disc: tags.discNumber ?? t.disc,
      genre: t.genre || tags.genre || '',
    };
  };

  const addFiles = (files: FileList | File[]) => {
    const list = [...files]
      .filter((f) => /\.(mp3|flac|m4a|aac|mp4|ogg|oga|opus|wav)$/i.test(f.name))
      .sort((a, b) => a.name.localeCompare(b.name, 'de', { numeric: true }));
    // Uploads außerhalb des State-Updaters starten (StrictMode ruft Updater ggf. doppelt auf)
    const drafts: TrackDraft[] = list.map((f) => {
      const key = uuid();
      return {
        key,
        audio: startUpload(f, 'AUDIO', updateAudio(key)),
        title: stripExt(f.name),
        disc: 1,
        number: 0,
        artists: artist ? [artist] : [],
        features: [],
        genre: '',
        cover: null,
        coverPreview: null,
      };
    });
    setTracks((ts) => [...ts, ...drafts.map((d, i) => ({ ...d, number: ts.length + i + 1 }))]);
  };

  const removeTrack = (t: TrackDraft) => {
    t.audio.ctrl.abort();
    if (t.audio.uploadId) void abortUpload(t.audio.uploadId);
    setTracks((ts) => ts.filter((x) => x.key !== t.key).map((x, i) => ({ ...x, number: i + 1 })));
  };

  const retryTrack = (t: TrackDraft) => {
    updateTrack(t.key, { audio: startUpload(t.audio.file, 'AUDIO', updateAudio(t.key), t.audio.uploadId ?? undefined) });
  };

  const move = (idx: number, dir: -1 | 1) =>
    setTracks((ts) => {
      const next = [...ts];
      const j = idx + dir;
      if (j < 0 || j >= next.length) return ts;
      [next[idx], next[j]] = [next[j]!, next[idx]!];
      return next.map((t, i) => ({ ...t, number: i + 1 }));
    });

  const chooseCover = (f: File | null) => {
    if (cover) cover.ctrl.abort();
    if (!f) {
      setCover(null);
      setCoverPreview(null);
      return;
    }
    setCoverPreview(URL.createObjectURL(f));
    setCover(startUpload(f, 'IMAGE', (p) => setCover((c) => (c ? { ...c, ...p } : c))));
  };

  const chooseTrackCover = (t: TrackDraft, f: File | null) => {
    t.cover?.ctrl.abort();
    if (!f) return updateTrack(t.key, { cover: null, coverPreview: null });
    updateTrack(t.key, {
      coverPreview: URL.createObjectURL(f),
      cover: startUpload(f, 'IMAGE', (p) => setTracks((ts) => ts.map((x) => (x.key === t.key && x.cover ? { ...x, cover: { ...x.cover, ...p } } : x)))),
    });
  };

  const allReady = tracks.length > 0 && tracks.every((t) => t.audio.status === 'ready' && (!t.cover || t.cover.status === 'ready')) && (!cover || cover.status === 'ready');
  const totalBytes = tracks.reduce((s, t) => s + t.audio.file.size, 0);
  const sentBytes = tracks.reduce((s, t) => s + t.audio.file.size * t.audio.progress, 0);

  const validation = useMemo(() => {
    const errs: string[] = [];
    tracks.forEach((t, i) => {
      if (!t.title.trim()) errs.push(`Track ${i + 1}: Titel fehlt.`);
      if (t.artists.length === 0) errs.push(`Track ${i + 1}: mindestens ein Künstler nötig.`);
    });
    const seen = new Set<string>();
    for (const t of tracks) {
      const k = `${t.disc}-${t.number}`;
      if (seen.has(k)) errs.push(`Disc ${t.disc}, Track ${t.number} ist doppelt vergeben.`);
      seen.add(k);
    }
    return errs;
  }, [tracks]);

  const commit = async () => {
    if (!artist) return;
    setBusy(true);
    setError(null);
    try {
      const r = await api<{ result: { releaseId: string; releaseFolder: string } }>('/admin/releases/commit', {
        method: 'POST',
        body: {
          idempotencyKey: idempotencyKey.current,
          artistId: artist.id,
          release:
            mode === 'new'
              ? { mode, title: title.trim(), type, year: year ? Number(year) : null, genre: genre.trim() || null, coverUploadId: cover?.uploadId ?? null }
              : { mode, releaseId: existing!.id, coverUploadId: cover?.uploadId ?? null },
          tracks: tracks.map((t) => ({
            uploadId: t.audio.uploadId,
            title: t.title.trim(),
            discNumber: t.disc,
            trackNumber: t.number,
            artistIds: t.artists.map((a) => a.id),
            featuredArtistIds: t.features.map((a) => a.id),
            genre: t.genre.trim() || null,
            coverUploadId: t.cover?.uploadId ?? null,
          })),
        },
      });
      setResult(r.result);
    } catch (e) {
      // Erneutes Bestätigen verwendet denselben Idempotenzschlüssel → keine doppelte Veröffentlichung
      setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  const reset = () => {
    setStep(0);
    setArtist(null);
    setMode('new');
    setExisting(null);
    setTitle('');
    setGenre('');
    setCover(null);
    setCoverPreview(null);
    setTracks([]);
    setResult(null);
    setError(null);
    idempotencyKey.current = uuid();
  };

  const canNext = [
    !!artist,
    true,
    mode === 'new' || !!existing,
    mode === 'existing' || (title.trim().length > 0 && (!cover || cover.status !== 'error')),
    tracks.length > 0,
    validation.length === 0,
    true,
  ][step];

  if (result) {
    return (
      <div className="card stack" style={{ maxWidth: 640 }}>
        <h1>Upload abgeschlossen ✓</h1>
        <p>
          Die Dateien wurden geprüft und automatisch abgelegt unter:
          <br />
          <code>{result.releaseFolder}</code>
        </p>
        <div className="row">
          <Link className="btn primary" to={`/veroeffentlichungen/${result.releaseId}`}>
            Veröffentlichung öffnen
          </Link>
          <button className="btn" onClick={reset}>
            Weiteren Upload starten
          </button>
        </div>
      </div>
    );
  }

  return (
    <>
      <h1>Musik hochladen</h1>
      <div className="steps" aria-label="Fortschritt">
        {STEPS.map((s, i) => (
          <span key={s} className={`step ${i === step ? 'active' : i < step ? 'done' : ''}`}>
            {i + 1}. {s}
          </span>
        ))}
      </div>

      <div className="card stack">
        {step === 0 && (
          <>
            <h2 style={{ marginTop: 0 }}>Künstler wählen oder anlegen</h2>
            {artist ? (
              <div className="row">
                <Cover id={artist.imageId} size={56} round />
                <strong style={{ fontSize: 18 }}>{artist.name}</strong>
                <button className="btn small ghost" onClick={() => setArtist(null)}>
                  Ändern
                </button>
              </div>
            ) : (
              <ArtistPicker autoFocus onSelect={setArtist} placeholder="Künstlername eingeben – Vorschläge erscheinen sofort" />
            )}
          </>
        )}

        {step === 1 && (
          <>
            <h2 style={{ marginTop: 0 }}>Veröffentlichungstyp</h2>
            <div className="row">
              {(['ALBUM', 'EP', 'SINGLE'] as RType[]).map((t) => (
                <button key={t} className={`btn ${type === t ? 'primary' : ''}`} onClick={() => setType(t)} aria-pressed={type === t}>
                  {RELEASE_TYPE_LABEL[t]}
                </button>
              ))}
            </div>
          </>
        )}

        {step === 2 && (
          <>
            <h2 style={{ marginTop: 0 }}>Neue oder vorhandene Veröffentlichung</h2>
            <div className="row">
              <button className={`btn ${mode === 'new' ? 'primary' : ''}`} onClick={() => setMode('new')}>
                Neue {RELEASE_TYPE_LABEL[type]} anlegen
              </button>
              <button className={`btn ${mode === 'existing' ? 'primary' : ''}`} onClick={() => setMode('existing')} disabled={releases.length === 0}>
                Zu vorhandener hinzufügen ({releases.length})
              </button>
            </div>
            {mode === 'existing' && (
              <div className="stack">
                {releases.map((r) => (
                  <label key={r.id} className="row" style={{ cursor: 'pointer' }}>
                    <input type="radio" name="release" checked={existing?.id === r.id} onChange={() => setExisting(r)} />
                    <Cover id={r.coverImageId} size={40} />
                    <span>
                      <strong>{r.title}</strong> <span className="dim">{r.year ?? ''} · {r.trackCount} Tracks</span>
                    </span>
                  </label>
                ))}
              </div>
            )}
          </>
        )}

        {step === 3 && (
          <>
            <h2 style={{ marginTop: 0 }}>{mode === 'new' ? 'Metadaten & Cover' : `Cover für „${existing?.title}“ (optional ersetzen)`}</h2>
            {mode === 'new' && (
              <div className="form-grid">
                <label className="field" style={{ gridColumn: '1 / -1' }}>
                  Titel *
                  <input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={300} />
                </label>
                <label className="field">
                  Jahr
                  <input type="number" min={1000} max={9999} value={year} onChange={(e) => setYear(e.target.value)} />
                </label>
                <label className="field">
                  Genre
                  <input value={genre} onChange={(e) => setGenre(e.target.value)} maxLength={100} />
                </label>
              </div>
            )}
            <div className="row">
              {coverPreview ? <img className="cover" src={coverPreview} width={120} height={120} alt="Cover" /> : <Cover id={existing?.coverImageId} size={120} />}
              <div className="stack">
                <label className="btn">
                  {cover ? 'Anderes Cover wählen' : 'Veröffentlichungscover wählen'}
                  <input type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => chooseCover(e.target.files?.[0] ?? null)} />
                </label>
                {cover && <UploadState u={cover} />}
                {cover && (
                  <button className="btn small ghost" onClick={() => chooseCover(null)}>
                    Cover entfernen
                  </button>
                )}
              </div>
            </div>
          </>
        )}

        {step === 4 && (
          <>
            <h2 style={{ marginTop: 0 }}>Audiodateien</h2>
            <DropZone onFiles={addFiles} />
            {tracks.length > 0 && (
              <div className="stack">
                <div className="row between">
                  <span className="dim">
                    {tracks.length} Datei(en) · {formatBytes(totalBytes)}
                  </span>
                  <span style={{ minWidth: 200 }}>
                    <Progress value={totalBytes ? sentBytes / totalBytes : 0} state={allReady ? 'done' : undefined} />
                  </span>
                </div>
                {tracks.map((t) => (
                  <div key={t.key} className="row between" style={{ flexWrap: 'nowrap' }}>
                    <span className="ellipsis">{t.audio.file.name}</span>
                    <div className="row" style={{ flexWrap: 'nowrap' }}>
                      <UploadState u={t.audio} />
                      {(t.audio.status === 'error' || t.audio.status === 'cancelled') && (
                        <button className="btn small" onClick={() => retryTrack(t)}>
                          Wiederholen
                        </button>
                      )}
                      {t.audio.status === 'uploading' && (
                        <button className="btn small ghost" onClick={() => t.audio.ctrl.abort()}>
                          Abbrechen
                        </button>
                      )}
                      <button className="icon-btn" aria-label="Entfernen" onClick={() => removeTrack(t)}>
                        ✕
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </>
        )}

        {step === 5 && (
          <>
            <h2 style={{ marginTop: 0 }}>Tracks prüfen</h2>
            <p className="dim">Titel, Künstler, Features, Nummern, Reihenfolge und individuelle Songcover. Ohne eigenes Songcover wird das Veröffentlichungscover verwendet.</p>
            {tracks.map((t, i) => (
              <div key={t.key} className="track-row">
                <div className="stack" style={{ gap: 2 }}>
                  <button className="icon-btn" aria-label="Nach oben" disabled={i === 0} onClick={() => move(i, -1)}>
                    ▲
                  </button>
                  <button className="icon-btn" aria-label="Nach unten" disabled={i === tracks.length - 1} onClick={() => move(i, 1)}>
                    ▼
                  </button>
                </div>
                <label style={{ cursor: 'pointer' }} title="Songcover wählen">
                  {t.coverPreview ? (
                    <img className="cover" src={t.coverPreview} width={56} height={56} alt="Songcover" />
                  ) : coverPreview ? (
                    <img className="cover" src={coverPreview} width={56} height={56} alt="Veröffentlichungscover" style={{ opacity: 0.5 }} />
                  ) : (
                    <Cover id={existing?.coverImageId} size={56} />
                  )}
                  <input type="file" accept="image/jpeg,image/png,image/webp" hidden onChange={(e) => chooseTrackCover(t, e.target.files?.[0] ?? null)} />
                </label>
                <div className="stack" style={{ gap: 8, minWidth: 0 }}>
                  <div className="form-grid" style={{ gridTemplateColumns: '2fr 80px 80px 1fr' }}>
                    <label className="field">
                      Titel
                      <input value={t.title} onChange={(e) => updateTrack(t.key, { title: e.target.value })} />
                    </label>
                    <label className="field">
                      Disc
                      <input type="number" min={1} max={99} value={t.disc} onChange={(e) => updateTrack(t.key, { disc: Number(e.target.value) || 1 })} />
                    </label>
                    <label className="field">
                      Nr.
                      <input type="number" min={1} max={999} value={t.number} onChange={(e) => updateTrack(t.key, { number: Number(e.target.value) || 1 })} />
                    </label>
                    <label className="field">
                      Genre
                      <input value={t.genre} onChange={(e) => updateTrack(t.key, { genre: e.target.value })} />
                    </label>
                  </div>
                  <ArtistChips label="Künstler" list={t.artists} onChange={(l) => updateTrack(t.key, { artists: l })} />
                  <ArtistChips label="Features" list={t.features} onChange={(l) => updateTrack(t.key, { features: l })} />
                  <div className="dim">
                    {t.audio.file.name}
                    {t.audio.probe ? ` · ${formatDuration(Number((t.audio.probe as { durationMs?: number }).durationMs ?? 0))} · ${(t.audio.probe as { codec?: string }).codec ?? ''}` : ''}
                    {t.cover && (
                      <>
                        {' '}
                        · Songcover: <UploadState u={t.cover} />{' '}
                        <button className="btn small ghost" onClick={() => chooseTrackCover(t, null)}>
                          entfernen
                        </button>
                      </>
                    )}
                  </div>
                </div>
              </div>
            ))}
            {validation.length > 0 && <div className="alert error">{validation.map((v) => <div key={v}>{v}</div>)}</div>}
          </>
        )}

        {step === 6 && (
          <>
            <h2 style={{ marginTop: 0 }}>Zusammenfassung</h2>
            <p>
              <strong>{artist?.name}</strong> · {RELEASE_TYPE_LABEL[type]} ·{' '}
              {mode === 'new' ? `neu: „${title}“ (${year || 'ohne Jahr'})` : `vorhanden: „${existing?.title}“`}
            </p>
            <p className="dim">
              {tracks.length} Track(s). Der Server legt Künstler-, Typ- und Veröffentlichungsordner automatisch an und überschreibt keine vorhandenen Dateien.
            </p>
            {!allReady && <div className="alert info">Warte auf Abschluss und Prüfung aller Uploads …</div>}
            <ErrorBox error={error} />
            <button className="btn success" disabled={!allReady || busy} onClick={commit}>
              {busy ? 'Wird abgelegt …' : error ? 'Erneut versuchen' : 'Upload bestätigen'}
            </button>
          </>
        )}
      </div>

      <div className="row between" style={{ marginTop: 16 }}>
        <button className="btn ghost" disabled={step === 0} onClick={() => setStep(step - 1)}>
          Zurück
        </button>
        {step < STEPS.length - 1 && (
          <button className="btn primary" disabled={!canNext} onClick={() => setStep(step + 1)}>
            Weiter
          </button>
        )}
      </div>
    </>
  );
}

function stripExt(name: string) {
  return name.replace(/\.[^.]+$/, '').replace(/^\d+\s*[-.]\s*/, '');
}

function UploadState({ u }: { u: FileUpload }) {
  const label = { uploading: `${Math.round(u.progress * 100)} %`, validating: 'Prüfe …', ready: 'Geprüft ✓', error: 'Fehler', cancelled: 'Abgebrochen' }[u.status];
  return (
    <span className="row" style={{ gap: 6, flexWrap: 'nowrap' }} title={u.error ?? undefined}>
      <span style={{ width: 90 }}>
        <Progress value={u.progress} state={u.status === 'ready' ? 'done' : u.status === 'error' ? 'error' : undefined} />
      </span>
      <span className={`badge ${u.status === 'ready' ? 'success' : u.status === 'error' ? 'danger' : ''}`}>{label}</span>
      {u.error && <span className="dim ellipsis" style={{ maxWidth: 260 }}>{u.error}</span>}
    </span>
  );
}

function ArtistChips({ label, list, onChange }: { label: string; list: Artist[]; onChange: (l: Artist[]) => void }) {
  return (
    <div className="row" style={{ alignItems: 'flex-start' }}>
      <span className="dim" style={{ width: 70, paddingTop: 8 }}>
        {label}
      </span>
      <div className="stack" style={{ flex: 1, gap: 6 }}>
        <div className="chips">
          {list.map((a) => (
            <span className="chip" key={a.id}>
              {a.name}
              <button aria-label={`${a.name} entfernen`} onClick={() => onChange(list.filter((x) => x.id !== a.id))}>
                ✕
              </button>
            </span>
          ))}
        </div>
        <ArtistPicker placeholder={`${label} hinzufügen …`} excludeIds={list.map((a) => a.id)} onSelect={(a) => onChange([...list, a])} />
      </div>
    </div>
  );
}

function DropZone({ onFiles }: { onFiles: (f: FileList) => void }) {
  const [drag, setDrag] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  return (
    <div
      className={`dropzone ${drag ? 'drag' : ''}`}
      onClick={() => input.current?.click()}
      onDragOver={(e) => {
        e.preventDefault();
        setDrag(true);
      }}
      onDragLeave={() => setDrag(false)}
      onDrop={(e) => {
        e.preventDefault();
        setDrag(false);
        onFiles(e.dataTransfer.files);
      }}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => e.key === 'Enter' && input.current?.click()}
    >
      Audiodateien hierher ziehen oder klicken (MP3, FLAC, M4A/AAC, Ogg, WAV) – mehrere möglich
      <input ref={input} type="file" multiple hidden accept=".mp3,.flac,.m4a,.aac,.mp4,.ogg,.oga,.opus,.wav,audio/*" onChange={(e) => e.target.files && onFiles(e.target.files)} />
    </div>
  );
}
