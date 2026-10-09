/**
 * Randomness for picks comes from the Web Crypto API rather than Math.random,
 * so a result can't be predicted from the engine's PRNG state.
 */

const UINT32_RANGE = 2 ** 32;

/** Uniform integer in [0, maxExclusive), free of modulo bias. */
export function randomInt(maxExclusive: number): number {
  if (!Number.isInteger(maxExclusive) || maxExclusive < 1 || maxExclusive > UINT32_RANGE) {
    throw new RangeError(`randomInt: expected an integer in [1, 2^32], got ${maxExclusive}`);
  }
  // Values at or above `limit` would favour the low remainders, so redraw them.
  const limit = UINT32_RANGE - (UINT32_RANGE % maxExclusive);
  const buffer = new Uint32Array(1);
  let value: number;
  do {
    crypto.getRandomValues(buffer);
    value = buffer[0];
  } while (value >= limit);
  return value % maxExclusive;
}

/** Uniform float in [0, 1). */
export function randomFloat(): number {
  const buffer = new Uint32Array(1);
  crypto.getRandomValues(buffer);
  return buffer[0] / UINT32_RANGE;
}

/** Fisher–Yates shuffle into a new array. */
export function shuffle<T>(items: readonly T[]): T[] {
  const result = [...items];
  for (let i = result.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}

/**
 * Deterministic PRNG (mulberry32) for cosmetic jitter such as hand-drawn wobble.
 * Server and client must draw identical paths, so this is seeded — never use it for picks.
 */
export function seededRandom(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / UINT32_RANGE;
  };
}

/** Stable 32-bit hash for turning strings (e.g. a name) into a seed. */
export function hashString(value: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}
