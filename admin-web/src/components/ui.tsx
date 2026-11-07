import { useEffect, type ReactNode } from 'react';
import { imageUrl } from '../lib/api';

export function Cover({ id, size = 48, round = false, alt = '' }: { id: string | null | undefined; size?: number; round?: boolean; alt?: string }) {
  const src = imageUrl(id, size > 120 ? 'medium' : size > 60 ? 'small' : 'thumb');
  if (!src) {
    // Einheitlicher Demonify-Platzhalter
    return (
      <div className={`cover cover-ph ${round ? 'round' : ''}`} style={{ width: size, height: size }} aria-label={alt || 'Kein Bild'}>
        <svg width={size * 0.45} height={size * 0.45} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
          <path d="M12 3v10.55A4 4 0 1 0 14 17V7h4V3h-6z" />
        </svg>
      </div>
    );
  }
  return <img className={`cover ${round ? 'round' : ''}`} src={src} width={size} height={size} alt={alt} loading="lazy" />;
}

export function Progress({ value, state }: { value: number; state?: 'done' | 'error' }) {
  return (
    <div className={`progress ${state ?? ''}`} role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(value * 100)}>
      <div style={{ width: `${Math.max(0, Math.min(1, value)) * 100}%` }} />
    </div>
  );
}

export function Modal({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className={`modal ${wide ? 'wide' : ''}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="row between" style={{ marginBottom: 16 }}>
          <h2 style={{ margin: 0 }}>{title}</h2>
          <button className="icon-btn" onClick={onClose} aria-label="Schließen">
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function ErrorBox({ error }: { error: string | null | undefined }) {
  if (!error) return null;
  return (
    <div className="alert error" role="alert">
      {error}
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="card muted" style={{ textAlign: 'center', padding: 32 }}>{children}</div>;
}

export function JobStatusBadge({ status }: { status: string }) {
  const map: Record<string, [string, string]> = {
    QUEUED: ['Wartet', ''],
    RUNNING: ['Läuft', 'primary'],
    SUCCEEDED: ['Erfolgreich', 'success'],
    FAILED: ['Fehlgeschlagen', 'danger'],
    CANCELLED: ['Abgebrochen', 'warn'],
  };
  const [label, cls] = map[status] ?? [status, ''];
  return <span className={`badge ${cls}`}>{label}</span>;
}
