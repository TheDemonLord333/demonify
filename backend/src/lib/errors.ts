/**
 * Einheitliche Fehlerantwort:
 * { "error": { "code": "NOT_FOUND", "message": "…", "details": … } }
 */
export class ApiError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export const badRequest = (message: string, details?: unknown) =>
  new ApiError(400, 'BAD_REQUEST', message, details);
export const unauthorized = (message = 'Anmeldung erforderlich.', code = 'UNAUTHORIZED') =>
  new ApiError(401, code, message);
export const forbidden = (message = 'Keine Berechtigung für diese Aktion.') =>
  new ApiError(403, 'FORBIDDEN', message);
export const notFound = (message = 'Nicht gefunden.') => new ApiError(404, 'NOT_FOUND', message);
export const conflict = (message: string, details?: unknown, code = 'CONFLICT') =>
  new ApiError(409, code, message, details);
export const unprocessable = (message: string, details?: unknown, code = 'UNPROCESSABLE') =>
  new ApiError(422, code, message, details);

export function errorBody(code: string, message: string, details?: unknown) {
  return { error: details === undefined ? { code, message } : { code, message, details } };
}

/** Prisma-Fehler „Unique constraint failed“ */
export function isUniqueViolation(err: unknown): boolean {
  return typeof err === 'object' && err !== null && (err as { code?: string }).code === 'P2002';
}
