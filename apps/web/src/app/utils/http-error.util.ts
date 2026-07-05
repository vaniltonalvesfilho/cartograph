/**
 * Extracts a human-readable message from an HttpErrorResponse, handling both
 * shapes the backend produces:
 *   - validation: `{ errors: { field: [msg, ...] } }` (status 422)
 *   - flat:       `{ error: "message" }` (status 403/400/404/...)
 * Falls back to the transport-level message, then the provided default.
 */
export function extractApiError(err: any, fallback: string): string {
  const body = err?.error;

  const errors = body?.errors;
  if (errors && typeof errors === 'object') {
    const parts = Object.entries(errors).map(
      ([field, msgs]) => `${field}: ${(msgs as string[]).join(', ')}`,
    );
    if (parts.length) return parts.join(' · ');
  }

  if (typeof body?.error === 'string') return body.error;
  if (typeof err?.message === 'string') return err.message;
  return fallback;
}
