import { useState } from 'react';
import { Link, useSearchParams } from 'react-router';
import { RELEASE_TYPE_LABEL, type Page, type Release } from '../lib/api';
import { useApi, useDebounced } from '../lib/hooks';
import { Cover, Empty, ErrorBox } from '../components/ui';
import { formatDate } from '../lib/format';

export function ReleasesPage() {
  const [params, setParams] = useSearchParams();
  const artistId = params.get('artistId');
  const type = params.get('type') ?? '';
  const [q, setQ] = useState('');
  const dq = useDebounced(q, 150);
  const [offset, setOffset] = useState(0);
  const qs = new URLSearchParams({ limit: '50', offset: String(offset) });
  if (artistId) qs.set('artistId', artistId);
  if (type) qs.set('type', type);
  if (dq) qs.set('q', dq);
  const list = useApi<Page<Release>>(`/admin/releases?${qs}`);

  return (
    <>
      <div className="row between">
        <h1>Veröffentlichungen</h1>
        <Link className="btn primary" to="/upload">
          ＋ Neue Veröffentlichung
        </Link>
      </div>
      <div className="row" style={{ marginBottom: 16 }}>
        <input placeholder="Titel filtern …" value={q} onChange={(e) => setQ(e.target.value)} style={{ maxWidth: 320 }} />
        <select
          value={type}
          onChange={(e) => {
            const p = new URLSearchParams(params);
            if (e.target.value) p.set('type', e.target.value);
            else p.delete('type');
            setParams(p);
            setOffset(0);
          }}
          style={{ maxWidth: 180 }}
        >
          <option value="">Alle Typen</option>
          <option value="ALBUM">Alben</option>
          <option value="EP">EPs</option>
          <option value="SINGLE">Singles</option>
        </select>
        {artistId && (
          <button className="btn small ghost" onClick={() => setParams({})}>
            Künstlerfilter entfernen
          </button>
        )}
      </div>
      <ErrorBox error={list.error} />
      {list.data?.items.length === 0 && <Empty>Keine Veröffentlichungen.</Empty>}
      <div className="card table-wrap">
        <table>
          <thead>
            <tr>
              <th></th>
              <th>Titel</th>
              <th>Künstler</th>
              <th>Typ</th>
              <th>Jahr</th>
              <th>Tracks</th>
              <th>Hinzugefügt</th>
            </tr>
          </thead>
          <tbody>
            {list.data?.items.map((r) => (
              <tr key={r.id}>
                <td style={{ width: 56 }}>
                  <Cover id={r.coverImageId} size={44} />
                </td>
                <td>
                  <Link to={`/veroeffentlichungen/${r.id}`}>
                    <strong>{r.title}</strong>
                  </Link>
                </td>
                <td>{r.albumArtist.name}</td>
                <td>
                  <span className="badge primary">{RELEASE_TYPE_LABEL[r.type]}</span>
                </td>
                <td>{r.year ?? '–'}</td>
                <td>{r.trackCount}</td>
                <td className="dim">{formatDate(r.createdAt)}</td>
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
          <span className="dim">{list.data.total} gesamt</span>
          <button className="btn small" disabled={list.data.nextOffset === null} onClick={() => setOffset(list.data!.nextOffset!)}>
            Weiter
          </button>
        </div>
      )}
    </>
  );
}
