import { describe, expect, test } from "bun:test";
import {
  LEVEL_BASE_SECONDS,
  LEVEL_MAX,
  levelForTotalSeconds,
  levelRequirementSeconds,
  progressInLevel,
  thresholdForLevel,
} from "../src";

// Parity fixtures — the same values are asserted by the Swift implementation
// (ios Anky/Tests/LevelTests.swift). If one side changes, both must.
const REQUIREMENTS = [
  480, 778, 1260, 2041, 3306, 5356, 8677, 14057, 22772, 36891, 59763, 96816,
];
const THRESHOLDS = [
  0, 480, 1258, 2518, 4559, 7865, 13221, 21898, 35955, 58727, 95618, 155381,
];

describe("level curve", () => {
  test("level 1→2 costs exactly 480 seconds", () => {
    expect(LEVEL_BASE_SECONDS).toBe(480);
    expect(levelRequirementSeconds(1)).toBe(480);
    expect(thresholdForLevel(2)).toBe(480);
    expect(levelForTotalSeconds(479)).toBe(1);
    expect(levelForTotalSeconds(480)).toBe(2);
  });

  test("requirements and thresholds match parity fixtures", () => {
    REQUIREMENTS.forEach((want, i) => {
      expect(levelRequirementSeconds(i + 1)).toBe(want);
    });
    THRESHOLDS.forEach((want, i) => {
      expect(thresholdForLevel(i + 1)).toBe(want);
    });
  });

  test("progress is monotonic and never decays", () => {
    let lastLevel = 1;
    for (let total = 0; total <= 10_000; total += 97) {
      const p = progressInLevel(total);
      expect(p.level).toBeGreaterThanOrEqual(lastLevel);
      expect(p.secondsIntoLevel).toBeGreaterThanOrEqual(0);
      expect(p.secondsIntoLevel).toBeLessThanOrEqual(p.secondsRequired);
      expect(p.percent).toBeGreaterThanOrEqual(0);
      expect(p.percent).toBeLessThanOrEqual(1);
      lastLevel = p.level;
    }
  });

  test("progress at exact boundaries", () => {
    const atBoundary = progressInLevel(480);
    expect(atBoundary.level).toBe(2);
    expect(atBoundary.secondsIntoLevel).toBe(0);
    expect(atBoundary.secondsRequired).toBe(778);
    expect(atBoundary.percent).toBe(0);

    const justBefore = progressInLevel(479);
    expect(justBefore.level).toBe(1);
    expect(justBefore.secondsIntoLevel).toBe(479);
  });

  test("negative and fractional input clamps sanely", () => {
    expect(levelForTotalSeconds(-100)).toBe(1);
    expect(progressInLevel(480.9).level).toBe(2);
    expect(progressInLevel(479.9).level).toBe(1);
  });

  test("level is bounded for any representable total", () => {
    const level = levelForTotalSeconds(Number.MAX_SAFE_INTEGER);
    expect(level).toBeLessThanOrEqual(LEVEL_MAX);
    // the geometric curve outruns 2^53 seconds long before LEVEL_MAX
    expect(level).toBeGreaterThan(60);
    expect(progressInLevel(Number.MAX_SAFE_INTEGER).percent).toBeLessThanOrEqual(1);
  });

  test("rejects invalid levels", () => {
    expect(() => levelRequirementSeconds(0)).toThrow("INVALID_LEVEL");
    expect(() => thresholdForLevel(1.5)).toThrow("INVALID_LEVEL");
  });
});
