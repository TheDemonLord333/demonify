/**
 * API-Client der Verwaltung: relative Aufrufe unter /api/v1, Cookie-Authentifizierung
 * (HttpOnly, SameSite=Strict) plus CSRF-Header für zustandsändernde Anfragen.
 * Bei abgelaufenem Access-Token wird einmalig über /auth/refresh erneuert.
 */
export const API_BASE = '/api/v1';

export interface ApiErrorBody {
  error: { code: string; message: string; details?: unknown };
}

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public details?: unknown,
  ) {
    super(message);
  }
}

let csrfToken: string | null = readCsrfCookie();
let refreshing: Promise<boolean> | null = null;
let onUnauthorized: (() => void) | null = null;

function readCsrfCookie(): string | null {
  const m = document.cookie.match(/(?:^|;\s*)dmf_csrf=([^;]+)/);
  return m ? decodeURIComponent(m[1]!) : null;
}

export function setCsrfToken(token: string | null) {
  csrfToken = token;
}

export function setUnauthorizedHandler(fn: () => void) {
  onUnauthorized = fn;
}

async function parseError(res: Response): Promise<ApiError> {
  const ct = res.headers.get('content-type') ?? '';
  if (ct.includes('application/json')) {
    const body = (await res.json().catch(() => null)) as ApiErrorBody | null;
    if (body?.error) return new ApiError(res.status, body.error.code, body.error.message, body.error.details);
  }
  // Niemals HTML-Seiten als Erfolg interpretieren
  return new ApiError(res.status, 'HTTP_' + res.status, `Serverfehler (${res.status}). Ist die API erreichbar?`);
}

async function tryRefresh(): Promise<boolean> {
  refreshing ??= (async () => {
    try {
      const res = await fetch(`${API_BASE}/auth/refresh`, {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'x-csrf-token': csrfToken ?? readCsrfCookie() ?? '' },
      });
      if (!res.ok) return false;
      const body = (await res.json()) as { csrfToken: string };
      csrfToken = body.csrfToken;
      return true;
    } catch {
      return false;
    } finally {
      setTimeout(() => (refreshing = null), 0);
    }
  })();
  return refreshing;
}

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: unknown;
  rawBody?: BodyInit;
  headers?: Record<string, string>;
  signal?: AbortSignal;
  /** Keine automatische Erneuerung (z. B. für Login) */
  noRefresh?: boolean;
}

export async function api<T>(path: string, opts: RequestOptions = {}): Promise<T> {
  const method = opts.method ?? 'GET';
  const doFetch = () => {
    const headers: Record<string, string> = { accept: 'application/json', ...opts.headers };
    if (opts.body !== undefined) headers['content-type'] = 'application/json';
    if (method !== 'GET') headers['x-csrf-token'] = csrfToken ?? readCsrfCookie() ?? '';
    return fetch(`${API_BASE}${path}`, {
      method,
      headers,
      credentials: 'same-origin',
      body: opts.rawBody ?? (opts.body !== undefined ? JSON.stringify(opts.body) : undefined),
      signal: opts.signal,
    });
  };
  let res: Response;
  try {
    res = await doFetch();
  } catch (e) {
    if ((e as Error).name === 'AbortError') throw e;
    throw new ApiError(0, 'NETWORK', 'Keine Verbindung zum Server.');
  }
  if (res.status === 401 && !opts.noRefresh) {
    if (await tryRefresh()) res = await doFetch();
    if (res.status === 401) onUnauthorized?.();
  }
  if (!res.ok) throw await parseError(res);
  const ct = res.headers.get('content-type') ?? '';
  if (!ct.includes('application/json')) {
    throw new ApiError(res.status, 'UNEXPECTED_RESPONSE', 'Unerwartete Antwort vom Server (kein JSON).');
  }
  return (await res.json()) as T;
}

export function imageUrl(id: string | null | undefined, size: 'thumb' | 'small' | 'medium' | 'large' = 'small'): string | null {
  return id ? `${API_BASE}/images/${id}?size=${size}` : null;
}

export function errorMessage(e: unknown): string {
  if (e instanceof ApiError) return e.message;
  if (e instanceof Error) return e.message;
  return String(e);
}

// ───────── Typen (entsprechen den API-DTOs)
export interface User {
  id: string;
  username: string;
  displayName: string | null;
  role: 'ADMIN' | 'USER';
  disabled: boolean;
  createdAt: string;
  lastLoginAt: string | null;
}
export interface Artist {
  id: string;
  name: string;
  imageId: string | null;
}
export interface Release {
  id: string;
  title: string;
  type: 'ALBUM' | 'EP' | 'SINGLE';
  year: number | null;
  genre: string | null;
  coverImageId: string | null;
  albumArtist: { id: string; name: string };
  trackCount: number;
  createdAt: string;
  folder?: string | null;
}
export interface Track {
  id: string;
  title: string;
  discNumber: number;
  trackNumber: number;
  durationMs: number;
  available: boolean;
  genre: string | null;
  year: number | null;
  codec: string | null;
  bitrate: number | null;
  coverImageId: string | null;
  hasOwnCover: boolean;
  artists: Array<{ id: string; name: string; role: 'PRIMARY' | 'FEATURED' }>;
  release: { id: string; title: string; type: string; year: number | null; coverImageId: string | null; albumArtist: { id: string; name: string } };
  audioPath?: string;
  needsReview?: boolean;
}
export interface Job {
  id: string;
  type: 'LIBRARY_SCAN' | 'TRANSCODE' | 'UPLOAD_CLEANUP';
  status: 'QUEUED' | 'RUNNING' | 'SUCCEEDED' | 'FAILED' | 'CANCELLED';
  progress: number;
  total: number;
  done: number;
  message: string | null;
  error: string | null;
  result: Record<string, unknown> | null;
  payload: Record<string, unknown>;
  createdAt: string;
  startedAt: string | null;
  finishedAt: string | null;
}
export interface Page<T> {
  items: T[];
  offset: number;
  limit: number;
  total: number;
  nextOffset: number | null;
}

export const RELEASE_TYPE_LABEL: Record<Release['type'], string> = { ALBUM: 'Album', EP: 'EP', SINGLE: 'Single' };
