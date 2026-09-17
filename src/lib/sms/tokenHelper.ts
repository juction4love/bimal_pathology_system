/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Public Report Token Generator & Cryptographic Hasher
 * Raw 256-bit unguessable tokens sent to patient; Only SHA-256 stored in DB
 */

/**
 * Generate a cryptographically secure, unguessable URL-safe random 256-bit token
 */
export function generateRawToken(): string {
  if (typeof crypto === 'undefined' || !crypto.getRandomValues) {
    throw new Error('Secure random token generation is unavailable in this browser.');
  }

  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Computes deterministic SHA-256 hex string of the raw token for database storage / lookup
 */
export async function hashToken(rawToken: string): Promise<string> {
  const cleanToken = rawToken.trim().toLowerCase();
  const encoder = new TextEncoder();
  const data = encoder.encode(cleanToken);

  if (typeof crypto === 'undefined' || !crypto.subtle) {
    throw new Error('Secure SHA-256 hashing is unavailable in this browser.');
  }

  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}
