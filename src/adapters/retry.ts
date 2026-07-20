// Shared retry helper for outbound adapters. Three attempts, 2s/4s/8s backoff.

export interface RetryConfig {
  attempts: number;
  delaysMs: number[];
}

export const DEFAULT_RETRY: RetryConfig = {
  attempts: 3,
  delaysMs: [2000, 4000, 8000],
};

export async function withRetry<T>(
  fn: () => Promise<T>,
  shouldRetry: (result: { ok: boolean; error?: string; statusCode?: number }) => boolean,
  config: RetryConfig = DEFAULT_RETRY
): Promise<T> {
  let lastResult: { ok: boolean; error?: string; statusCode?: number } = { ok: false, error: 'never invoked' };

  for (let attempt = 0; attempt < config.attempts; attempt++) {
    try {
      const result = await fn();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      lastResult = result as any;
    } catch (e) {
      lastResult = { ok: false, error: (e as Error).message };
    }

    if (!shouldRetry(lastResult)) {
      return lastResult as unknown as T;
    }

    const delay = config.delaysMs[attempt] ?? config.delaysMs[config.delaysMs.length - 1] ?? 1000;
    if (attempt < config.attempts - 1) {
      await new Promise(r => setTimeout(r, delay));
    }
  }

  return lastResult as unknown as T;
}

export function isRetryableHttp(err: { error?: string; statusCode?: number }): boolean {
  // retry on 429 and 5xx, and on transient transport errors
  if (err.statusCode === 429) return true;
  if (err.statusCode && err.statusCode >= 500 && err.statusCode < 600) return true;
  if (err.error && /timeout|econnrefused|enotfound|socket hang up/i.test(err.error)) return true;
  return false;
}