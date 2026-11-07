import { api, ApiError, API_BASE } from './api';

/**
 * Wiederaufnehmbarer Abschnitts-Upload (gleiche API wie in der App):
 * Abschnitte ≤ Serverlimit (Standard 8 MB) bleiben unter den Cloudflare-Grenzen.
 * Nach einem Netzwerkfehler wird der Serverstand abgefragt und ab dort fortgesetzt.
 */
export interface UploadInfo {
  id: string;
  kind: 'AUDIO' | 'IMAGE';
  originalName: string;
  declaredSize: number;
  receivedSize: number;
  status: 'RECEIVING' | 'VALIDATED' | 'INVALID' | 'CONSUMED' | 'ABORTED';
  probe: Record<string, unknown> | null;
  error: string | null;
}

export interface UploadProgress {
  sent: number;
  total: number;
  phase: 'upload' | 'validate' | 'done' | 'error';
}

function csrf(): string {
  const m = document.cookie.match(/(?:^|;\s*)dmf_csrf=([^;]+)/);
  return m ? decodeURIComponent(m[1]!) : '';
}

function putChunk(id: string, offset: number, blob: Blob, signal: AbortSignal, onProgress: (loaded: number) => void): Promise<UploadInfo> {
  // XMLHttpRequest liefert Fortschritt innerhalb eines Abschnitts
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('PUT', `${API_BASE}/admin/uploads/${id}/content`);
    xhr.withCredentials = true;
    xhr.setRequestHeader('content-type', 'application/octet-stream');
    xhr.setRequestHeader('upload-offset', String(offset));
    xhr.setRequestHeader('x-csrf-token', csrf());
    xhr.upload.onprogress = (e) => onProgress(e.loaded);
    xhr.onload = () => {
      let body: { upload?: UploadInfo; error?: { code: string; message: string; details?: unknown } } | null = null;
      try {
        body = JSON.parse(xhr.responseText);
      } catch {
        /* kein JSON */
      }
      if (xhr.status >= 200 && xhr.status < 300 && body?.upload) resolve(body.upload);
      else reject(new ApiError(xhr.status, body?.error?.code ?? 'HTTP_' + xhr.status, body?.error?.message ?? `Upload fehlgeschlagen (${xhr.status})`, body?.error?.details));
    };
    xhr.onerror = () => reject(new ApiError(0, 'NETWORK', 'Netzwerkfehler beim Upload.'));
    xhr.onabort = () => reject(new DOMException('Abgebrochen', 'AbortError'));
    signal.addEventListener('abort', () => xhr.abort(), { once: true });
    xhr.send(blob);
  });
}

export async function uploadFile(
  file: File,
  kind: 'AUDIO' | 'IMAGE',
  opts: { signal: AbortSignal; onProgress: (p: UploadProgress) => void; existingId?: string },
): Promise<UploadInfo> {
  let upload: UploadInfo;
  let chunkSize: number;
  if (opts.existingId) {
    upload = (await api<{ upload: UploadInfo }>(`/admin/uploads/${opts.existingId}`)).upload;
    chunkSize = (await api<{ chunkSize: number }>('/admin/uploads/config')).chunkSize;
  } else {
    const created = await api<{ upload: UploadInfo; chunkSize: number }>('/admin/uploads', {
      method: 'POST',
      body: { kind, filename: file.name, size: file.size },
      signal: opts.signal,
    });
    upload = created.upload;
    chunkSize = created.chunkSize;
  }
  let offset = upload.receivedSize;
  let retries = 0;
  while (offset < file.size) {
    const end = Math.min(offset + chunkSize, file.size);
    try {
      upload = await putChunk(upload.id, offset, file.slice(offset, end), opts.signal, (loaded) =>
        opts.onProgress({ sent: offset + loaded, total: file.size, phase: 'upload' }),
      );
      offset = upload.receivedSize;
      retries = 0;
    } catch (e) {
      if ((e as Error).name === 'AbortError') throw e;
      if (e instanceof ApiError && e.code === 'OFFSET_MISMATCH') {
        offset = (e.details as { receivedSize: number }).receivedSize;
        continue;
      }
      if (e instanceof ApiError && (e.status === 0 || e.status >= 500) && retries < 5) {
        retries++;
        await new Promise((r) => setTimeout(r, 1000 * 2 ** retries));
        offset = (await api<{ upload: UploadInfo }>(`/admin/uploads/${upload.id}`)).upload.receivedSize;
        continue;
      }
      throw e;
    }
  }
  opts.onProgress({ sent: file.size, total: file.size, phase: 'validate' });
  const done = await api<{ upload: UploadInfo }>(`/admin/uploads/${upload.id}/complete`, { method: 'POST', signal: opts.signal });
  opts.onProgress({ sent: file.size, total: file.size, phase: done.upload.status === 'VALIDATED' ? 'done' : 'error' });
  return done.upload;
}

export async function abortUpload(id: string) {
  await api(`/admin/uploads/${id}`, { method: 'DELETE' }).catch(() => undefined);
}
