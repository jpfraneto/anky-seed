const seen = new Map<string, number>();

export function isFreshRequestTime(requestTime: string, toleranceMs: number, now = Date.now()): boolean {
  if (!/^\d+$/.test(requestTime)) return false;
  const parsed = Number(requestTime);
  if (!Number.isSafeInteger(parsed)) return false;
  return Math.abs(now - parsed) <= toleranceMs;
}

export function rememberRequest(signature: string, requestTime: string, ttlMs: number, now = Date.now()): boolean {
  for (const [key, expiresAt] of seen) {
    if (expiresAt <= now) seen.delete(key);
  }

  const key = `${requestTime}:${signature}`;
  if (seen.has(key)) return false;
  seen.set(key, now + ttlMs);
  return true;
}

export function clearReplayMemoryForTests(): void {
  seen.clear();
}
