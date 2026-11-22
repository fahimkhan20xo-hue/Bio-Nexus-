// Small HTTP helpers: JSON responses, one error type, and a body reader with a hard size limit.

export class ApiError extends Error {
  /**
   * @param {number} status HTTP status
   * @param {string} code short machine-readable code, e.g. "rate_limited"
   * @param {string} message safe text for the app (never internal details)
   * @param {object} [extra] e.g. { retryAfterSec }
   */
  constructor(status, code, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
  }
}

const BASE_HEADERS = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
};

export function json(status, body, extraHeaders = {}) {
  return new Response(JSON.stringify(body), { status, headers: { ...BASE_HEADERS, ...extraHeaders } });
}

export function ok(body, rid) {
  return json(200, { ok: true, ...body, requestId: rid });
}

export function errorResponse(err, rid) {
  const headers = { 'X-Error-Code': err.code };
  const error = { code: err.code, message: err.message };
  if (err.extra && Number.isFinite(err.extra.retryAfterSec)) {
    error.retryAfterSec = err.extra.retryAfterSec;
    headers['Retry-After'] = String(Math.max(1, Math.ceil(err.extra.retryAfterSec)));
  }
  return json(err.status, { ok: false, error, requestId: rid }, headers);
}

/**
 * Reads a JSON body without ever holding more than maxBytes in memory.
 * Content-Length is only a hint; the stream itself is counted.
 */
export async function readJsonLimited(request, maxBytes) {
  const ct = (request.headers.get('content-type') || '').toLowerCase();
  if (!ct.startsWith('application/json')) {
    throw new ApiError(415, 'unsupported_media_type', 'Send the body as application/json.');
  }
  const declared = Number(request.headers.get('content-length'));
  if (Number.isFinite(declared) && declared > maxBytes) {
    throw new ApiError(413, 'payload_too_large', 'The request is too large.');
  }
  if (!request.body) throw new ApiError(400, 'invalid_request', 'The request body is empty.');

  const reader = request.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      try {
        await reader.cancel();
      } catch {
        // ignore
      }
      throw new ApiError(413, 'payload_too_large', 'The request is too large.');
    }
    chunks.push(value);
  }
  if (total === 0) throw new ApiError(400, 'invalid_request', 'The request body is empty.');

  const bytes = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) {
    bytes.set(c, off);
    off += c.byteLength;
  }
  let text;
  try {
    text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new ApiError(400, 'invalid_request', 'The body is not valid UTF-8 text.');
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new ApiError(400, 'invalid_json', 'The body is not valid JSON.');
  }
}
