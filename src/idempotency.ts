/**
 * Idempotency key derivation. Prefer the form provider's stable submission
 * id; fall back to a deterministic hash of email + formId + submittedAt.
 * This function does not enforce uniqueness; the database does, via
 * INSERT ... ON CONFLICT. The message body is deliberately left out so a
 * client-side edit is treated as the same lead.
 */
import { createHash } from 'crypto';

export function deriveIdempotencyKey(
  providerSubmissionId: string | null | undefined,
  email: string,
  formId: string,
  submittedAt: string
): string {
  if (providerSubmissionId && typeof providerSubmissionId === 'string') {
    return `sub:${providerSubmissionId}`;
  }
  const normalized = `${email.toLowerCase().trim()}|${formId}|${submittedAt}`;
  const hash = createHash('sha256').update(normalized).digest('hex');
  return `drv:${hash}`;
}