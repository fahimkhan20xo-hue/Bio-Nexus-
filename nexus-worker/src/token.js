// Anonymous installation tokens: base64url(payload) + "." + base64url(HMAC-SHA256(payload)).
// This proves "the server issued this token to some installation". It does NOT prove who the
// person is: anyone can register a new installation. Limits therefore also exist per IP and globally.

const enc = new TextEncoder();
const keyCache = new Map();

function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function unb64url(str) {
  const pad = '='.repeat((4 - (str.length % 4)) % 4);
  const bin = atob(str.replace(/-/g, '+').replace(/_/g, '/') + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function hmacKey(secret) {
  let k = keyCache.get(secret);
  if (!k) {
    k = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
    if (keyCache.size > 4) keyCache.clear();
    keyCache.set(secret, k);
  }
  return k;
}

export async function signToken(secret, payload) {
  const body = b64url(enc.encode(JSON.stringify(payload)));
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', await hmacKey(secret), enc.encode(body)));
  return `${body}.${b64url(sig)}`;
}

/** Returns the payload, or null if the token is malformed, forged or expired. */
export async function verifyToken(secret, token, nowSec) {
  if (typeof token !== 'string' || token.length > 600) return null;
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  let payload;
  try {
    const sig = unb64url(parts[1]);
    const valid = await crypto.subtle.verify('HMAC', await hmacKey(secret), sig, enc.encode(parts[0]));
    if (!valid) return null; // constant-time comparison inside verify()
    payload = JSON.parse(new TextDecoder().decode(unb64url(parts[0])));
  } catch {
    return null;
  }
  if (!payload || payload.v !== 1 || typeof payload.iid !== 'string') return null;
  if (!Number.isFinite(payload.exp) || payload.exp <= nowSec) return null;
  return payload;
}

/** A short, non-reversible label for logs and storage keys. */
export async function shortHash(secret, value, bytes = 12) {
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', await hmacKey(secret), enc.encode(value)));
  return Array.from(sig.slice(0, bytes), (b) => b.toString(16).padStart(2, '0')).join('');
}
