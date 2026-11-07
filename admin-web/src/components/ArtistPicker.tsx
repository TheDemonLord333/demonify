import { useEffect, useRef, useState } from 'react';
import { api, ApiError, errorMessage, type Artist } from '../lib/api';
import { useDebounced } from '../lib/hooks';
import { Cover, ErrorBox, Modal } from './ui';

interface SuggestResponse {
  items: Artist[];
  exactMatch: Artist | null;
}

/**
 * Künstlerauswahl mit Live-Vorschlägen ab dem ersten Buchstaben (ohne Enter).
 * „Neuen Künstler erstellen“ übernimmt den eingetippten Namen ins Formular,
 * prüft vor dem Speichern erneut auf normalisierte Duplikate und wählt den neuen Künstler aus.
 */
export function ArtistPicker({
  onSelect,
  placeholder = 'Künstler suchen …',
  autoFocus,
  excludeIds = [],
}: {
  onSelect: (a: Artist) => void;
  placeholder?: string;
  autoFocus?: boolean;
  excludeIds?: string[];
}) {
  const [q, setQ] = useState('');
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState<Artist[]>([]);
  const [exact, setExact] = useState<Artist | null>(null);
  const [active, setActive] = useState(0);
  const [creating, setCreating] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const debounced = useDebounced(q, 120);
  const reqId = useRef(0);

  useEffect(() => {
    const term = debounced.trim();
    if (!term) {
      setItems([]);
      setExact(null);
      return;
    }
    const id = ++reqId.current;
    const ctrl = new AbortController();
    api<SuggestResponse>(`/admin/artists/suggest?q=${encodeURIComponent(term)}&limit=8`, { signal: ctrl.signal })
      .then((r) => {
        if (id !== reqId.current) return; // veraltete Antwort ignorieren
        setItems(r.items.filter((a) => !excludeIds.includes(a.id)));
        setExact(r.exactMatch);
        setActive(0);
        setError(null);
      })
      .catch((e) => {
        if ((e as Error).name !== 'AbortError' && id === reqId.current) setError(errorMessage(e));
      });
    return () => ctrl.abort();
  }, [debounced, excludeIds.join(',')]); // eslint-disable-line react-hooks/exhaustive-deps

  const choose = (a: Artist) => {
    onSelect(a);
    setQ('');
    setOpen(false);
  };

  const total = items.length + (q.trim() ? 1 : 0);
  return (
    <div className="combo">
      <input
        value={q}
        autoFocus={autoFocus}
        placeholder={placeholder}
        onChange={(e) => {
          setQ(e.target.value);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        onBlur={() => setTimeout(() => setOpen(false), 150)}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown') setActive((a) => Math.min(a + 1, total - 1));
          else if (e.key === 'ArrowUp') setActive((a) => Math.max(a - 1, 0));
          else if (e.key === 'Enter') {
            e.preventDefault();
            if (active < items.length) choose(items[active]!);
            else if (q.trim()) setCreating(q.trim());
          } else if (e.key === 'Escape') setOpen(false);
        }}
        role="combobox"
        aria-expanded={open}
        aria-autocomplete="list"
      />
      {open && q.trim() && (
        <div className="combo-list" role="listbox">
          {items.map((a, i) => (
            <div
              key={a.id}
              className={`combo-item ${i === active ? 'active' : ''}`}
              role="option"
              aria-selected={i === active}
              onMouseDown={(e) => {
                e.preventDefault();
                choose(a);
              }}
            >
              <Cover id={a.imageId} size={36} round />
              <span className="ellipsis">{a.name}</span>
              {exact?.id === a.id && <span className="badge success">Exakter Treffer</span>}
            </div>
          ))}
          {items.length === 0 && <div className="combo-item dim">Keine vorhandenen Künstler gefunden.</div>}
          <div
            className={`combo-item create ${active === items.length ? 'active' : ''}`}
            onMouseDown={(e) => {
              e.preventDefault();
              setCreating(q.trim());
            }}
          >
            ＋ Neuen Künstler erstellen: „{q.trim()}“
          </div>
        </div>
      )}
      <ErrorBox error={error} />
      {creating !== null && (
        <CreateArtistModal
          initialName={creating}
          onClose={() => setCreating(null)}
          onCreated={(a) => {
            setCreating(null);
            choose(a);
          }}
        />
      )}
    </div>
  );
}

interface CheckResponse {
  exists: boolean;
  artist: Artist | null;
  similar: Array<Artist & { score: number }>;
}

export function CreateArtistModal({ initialName, onClose, onCreated }: { initialName: string; onClose: () => void; onCreated: (a: Artist) => void }) {
  const [name, setName] = useState(initialName);
  const [check, setCheck] = useState<CheckResponse | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [conflictArtist, setConflictArtist] = useState<Artist | null>(null);
  const debounced = useDebounced(name, 200);

  useEffect(() => {
    if (!debounced.trim()) return setCheck(null);
    const ctrl = new AbortController();
    api<CheckResponse>(`/admin/artists/check?name=${encodeURIComponent(debounced)}`, { signal: ctrl.signal })
      .then(setCheck)
      .catch(() => undefined);
    return () => ctrl.abort();
  }, [debounced]);

  const save = async () => {
    setBusy(true);
    setError(null);
    setConflictArtist(null);
    try {
      // Erneute Prüfung direkt vor dem Speichern; die Datenbank-Constraint entscheidet verbindlich
      const r = await api<{ artist: Artist }>('/admin/artists', { method: 'POST', body: { name } });
      onCreated(r.artist);
    } catch (e) {
      if (e instanceof ApiError && e.code === 'ARTIST_EXISTS') {
        setError(e.message);
        setConflictArtist((e.details as { artist?: Artist } | undefined)?.artist ?? null);
      } else setError(errorMessage(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title="Neuen Künstler erstellen" onClose={onClose}>
      <div className="stack">
        <label className="field">
          Künstlername
          <input value={name} onChange={(e) => setName(e.target.value)} autoFocus maxLength={200} />
        </label>
        {check?.exists && check.artist && (
          <div className="alert error">
            „{check.artist.name}“ existiert bereits (gleicher Name nach Normalisierung).{' '}
            <button className="btn small" onClick={() => onCreated(check.artist!)}>
              Vorhandenen auswählen
            </button>
          </div>
        )}
        {!check?.exists && check?.similar.length ? (
          <div className="alert info">
            Ähnliche Namen vorhanden – bitte prüfen (werden nicht automatisch zusammengeführt):
            <div className="stack" style={{ marginTop: 8 }}>
              {check.similar.map((s) => (
                <div key={s.id} className="row">
                  <Cover id={s.imageId} size={28} round />
                  <span>{s.name}</span>
                  <button className="btn small ghost" onClick={() => onCreated(s)}>
                    Diesen verwenden
                  </button>
                </div>
              ))}
            </div>
          </div>
        ) : null}
        <ErrorBox error={error} />
        {conflictArtist && (
          <button className="btn" onClick={() => onCreated(conflictArtist)}>
            „{conflictArtist.name}“ auswählen
          </button>
        )}
        <div className="row" style={{ justifyContent: 'flex-end' }}>
          <button className="btn ghost" onClick={onClose}>
            Abbrechen
          </button>
          <button className="btn primary" disabled={busy || !name.trim() || !!check?.exists} onClick={save}>
            {busy ? 'Speichere …' : 'Künstler anlegen'}
          </button>
        </div>
      </div>
    </Modal>
  );
}
