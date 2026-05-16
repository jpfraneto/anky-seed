import type { Context } from "hono";

export type ErrorCode =
  | "INVALID_ANKY"
  | "INCOMPLETE_RITUAL"
  | "MISSING_SIGNATURE"
  | "INVALID_SIGNATURE"
  | "BODY_TOO_LARGE"
  | "INSUFFICIENT_CREDITS"
  | "DUPLICATE_IN_PROGRESS"
  | "RATE_LIMITED"
  | "MIRROR_FAILED";

const messages: Record<ErrorCode, string> = {
  INVALID_ANKY: "This does not appear to be a valid .anky file.",
  INCOMPLETE_RITUAL: "Only complete 8-minute ankys can ask for reflection.",
  MISSING_SIGNATURE: "This request is missing Anky signature headers.",
  INVALID_SIGNATURE: "The request signature could not be verified.",
  BODY_TOO_LARGE: "This .anky file is too large for the mirror.",
  INSUFFICIENT_CREDITS: "You need one credit to ask Anky for a reflection. Writing is still free.",
  DUPLICATE_IN_PROGRESS: "This anky is already being reflected.",
  RATE_LIMITED: "Too many mirror requests. Try again soon.",
  MIRROR_FAILED: "Anky could not return a reflection right now.",
};

const statuses: Record<ErrorCode, 400 | 401 | 402 | 409 | 413 | 429 | 500> = {
  INVALID_ANKY: 400,
  INCOMPLETE_RITUAL: 400,
  MISSING_SIGNATURE: 401,
  INVALID_SIGNATURE: 401,
  BODY_TOO_LARGE: 413,
  INSUFFICIENT_CREDITS: 402,
  DUPLICATE_IN_PROGRESS: 409,
  RATE_LIMITED: 429,
  MIRROR_FAILED: 500,
};

export function errorJson(c: Context, code: ErrorCode) {
  return c.json({ error: { code, message: messages[code] } }, statuses[code]);
}
