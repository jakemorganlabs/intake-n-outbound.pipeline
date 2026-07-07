/**
 * Idempotency key derivation.
 * Invariant: Every lead gets a stable idempotency key derived from either (a) the form provider's
 * authoritative submission ID, or (b) a deterministic hash of email + formId + submittedAt.
 * This module does NOT enforce uniqueness; the database does, via INSERT ... ON CONFLICT.
 * It deliberately does not include the message body, so message edits are treated as new leads.
 */
import { createHash } from 'crypto';

export function deriveIdempotencyKey(
  providerSubmissionId: string | null | undefined,
  email: string,
  formId: string,
  submittedAt: string
): string {
  // Primary: provider's stable id
  if (providerSubmissionId && typeof providerSubmissionId === 'string') {
    return `sub:${providerSubmissionId}`;
  }
  // Fallback: derived hash of email + form + submittedAt
  const normalized = `${email.toLowerCase().trim()}|${formId}|${submittedAt}`;
  const hash = createHash('sha256').update(normalized).digest('hex');
  return `drv:${hash}`;
}
