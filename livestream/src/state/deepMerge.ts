import type { DeepPartial } from "./showState";

export function deepMerge<T>(target: T, patch: DeepPartial<T>): T {
  if (Array.isArray(patch)) {
    return patch as T;
  }

  if (!isObject(target) || !isObject(patch)) {
    return patch as T;
  }

  const output: Record<string, unknown> = { ...(target as Record<string, unknown>) };

  for (const [key, patchValue] of Object.entries(patch)) {
    if (patchValue === undefined) {
      continue;
    }

    const targetValue = output[key];
    output[key] =
      isObject(targetValue) && isObject(patchValue) && !Array.isArray(patchValue)
        ? deepMerge(targetValue, patchValue as Record<string, unknown>)
        : patchValue;
  }

  return output as T;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
