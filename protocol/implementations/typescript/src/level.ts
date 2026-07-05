/**
 * Level curve — the single source of truth for level math.
 *
 * The only input is lifetime seconds written. Level 1→2 costs exactly
 * LEVEL_BASE_SECONDS (one full ritual); each subsequent level costs
 * LEVEL_RATIO times the previous one, rounded to whole seconds at every
 * step so the sequence is exactly reproducible in any IEEE-754 runtime
 * (mirrored in Swift as AnkyLevel — keep the two in lockstep).
 */

export const LEVEL_BASE_SECONDS = 480;
export const LEVEL_RATIO = 1.62;
export const LEVEL_MAX = 120;

// 2^53 − 1: the largest integer doubles represent exactly; curve values are
// clamped here on both platforms (Swift mirrors this to avoid Int64 traps).
const MAX_EXACT_SECONDS = Number.MAX_SAFE_INTEGER;

export type LevelProgress = {
  level: number;
  secondsIntoLevel: number;
  secondsRequired: number;
  percent: number;
  totalSeconds: number;
};

/** Seconds needed to go from `level` to `level + 1`. Levels are 1-based. */
export function levelRequirementSeconds(level: number): number {
  if (!Number.isInteger(level) || level < 1) throw new Error("INVALID_LEVEL");
  let requirement = LEVEL_BASE_SECONDS;
  for (let n = 1; n < Math.min(level, LEVEL_MAX); n++) {
    requirement = Math.round(requirement * LEVEL_RATIO);
  }
  return Math.min(requirement, MAX_EXACT_SECONDS);
}

/** Lifetime seconds required to reach `level`. thresholdForLevel(1) === 0. */
export function thresholdForLevel(level: number): number {
  if (!Number.isInteger(level) || level < 1) throw new Error("INVALID_LEVEL");
  let threshold = 0;
  let requirement = LEVEL_BASE_SECONDS;
  for (let n = 1; n < Math.min(level, LEVEL_MAX + 1); n++) {
    threshold += requirement;
    requirement = Math.round(requirement * LEVEL_RATIO);
  }
  return Math.min(threshold, MAX_EXACT_SECONDS);
}

export function levelForTotalSeconds(totalSeconds: number): number {
  const total = Math.max(0, Math.floor(totalSeconds));
  let level = 1;
  let threshold = 0;
  let requirement = LEVEL_BASE_SECONDS;
  while (level < LEVEL_MAX && total >= threshold + requirement) {
    threshold += requirement;
    requirement = Math.round(requirement * LEVEL_RATIO);
    level += 1;
  }
  return level;
}

export function progressInLevel(totalSeconds: number): LevelProgress {
  const total = Math.max(0, Math.floor(totalSeconds));
  const level = levelForTotalSeconds(total);
  const threshold = thresholdForLevel(level);
  const required = levelRequirementSeconds(level);
  const into = Math.min(total - threshold, required);
  return {
    level,
    secondsIntoLevel: into,
    secondsRequired: required,
    percent: level >= LEVEL_MAX ? 1 : Math.min(1, into / required),
    totalSeconds: total,
  };
}
