// -----------------------------------------------------------------------------
// Cloudflare Stream Live Inputs — the only network surface of livestreaming.
//
// Shapes (verified against developers.cloudflare.com on 2026-10-27):
//   POST   /client/v4/accounts/{account}/stream/live_inputs
//          -> {success, errors, messages, result: {uid, rtmps: {url, streamKey},
//              webRTC: {url}, webRTCPlayback: {url}, ...}}
//   DELETE /client/v4/accounts/{account}/stream/live_inputs/{uid}
//   GET    /client/v4/accounts/{account}/stream/live_inputs/{uid}/videos
//   DELETE /client/v4/accounts/{account}/stream/{videoUid}
//   viewer: https://customer-{CODE}.cloudflarestream.com/{uid}/iframe
//
// Every call goes through an injectable fetch so tests never touch the network.
// -----------------------------------------------------------------------------

export type LiveFetch = (
  url: string,
  init: { method: string; headers: Record<string, string>; body?: string },
) => Promise<{ ok: boolean; status: number; json: () => Promise<unknown> }>;

export type LiveRecordingMode = "off" | "automatic";

export type CloudflareStreamConfig = {
  accountId: string;
  apiToken: string;
  customerCode: string;
  recordingMode: LiveRecordingMode;
};

export type CreatedLiveInput = {
  uid: string;
  rtmpsUrl: string;
  streamKey: string;
  whipUrl: string | null;
  whepPlaybackUrl: string | null;
};

const API_ROOT = "https://api.cloudflare.com/client/v4";

export function isCloudflareStreamConfigured(config: CloudflareStreamConfig): boolean {
  return Boolean(config.accountId && config.apiToken && config.customerCode);
}

/** Accepts either `abc123` or `customer-abc123` for the customer code. */
export function normalizedCustomerCode(code: string): string {
  return code.trim().replace(/^customer-/, "").replace(/\.cloudflarestream\.com.*$/, "");
}

export function viewerIframeUrl(config: CloudflareStreamConfig, uid: string): string {
  return `https://customer-${normalizedCustomerCode(config.customerCode)}.cloudflarestream.com/${encodeURIComponent(uid)}/iframe`;
}

function headers(config: CloudflareStreamConfig): Record<string, string> {
  return {
    Authorization: `Bearer ${config.apiToken}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  };
}

function liveInputsUrl(config: CloudflareStreamConfig): string {
  return `${API_ROOT}/accounts/${encodeURIComponent(config.accountId)}/stream/live_inputs`;
}

function asString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

export async function createLiveInput(
  config: CloudflareStreamConfig,
  fetchImpl: LiveFetch,
  input: { liveId: string },
): Promise<CreatedLiveInput> {
  const response = await fetchImpl(liveInputsUrl(config), {
    method: "POST",
    headers: headers(config),
    body: JSON.stringify({
      // Only the random live id: never the account, never a session title.
      meta: { name: `anky-live-${input.liveId}` },
      recording: {
        mode: config.recordingMode,
        // The live viewer count is not a feature; it invites performance.
        hideLiveViewerCount: true,
      },
      // Backstop only (Cloudflare's minimum). Recordings are also purged
      // explicitly when the broadcast ends.
      ...(config.recordingMode === "automatic" ? { deleteRecordingAfterDays: 30 } : {}),
    }),
  });
  if (!response.ok) throw new Error(`CF_CREATE_FAILED:${response.status}`);
  const json = (await response.json()) as {
    success?: unknown;
    result?: {
      uid?: unknown;
      rtmps?: { url?: unknown; streamKey?: unknown };
      webRTC?: { url?: unknown };
      webRTCPlayback?: { url?: unknown };
    };
  };
  const result = json?.result;
  const uid = asString(result?.uid);
  const rtmpsUrl = asString(result?.rtmps?.url);
  const streamKey = asString(result?.rtmps?.streamKey);
  if (json?.success === false || !uid || !rtmpsUrl || !streamKey) {
    throw new Error("CF_CREATE_MALFORMED");
  }
  return {
    uid,
    rtmpsUrl,
    streamKey,
    whipUrl: asString(result?.webRTC?.url),
    whepPlaybackUrl: asString(result?.webRTCPlayback?.url),
  };
}

/** Deletes the live input (its stream key stops working). A 404 means it is
 * already gone, which is success. Throws on any other failure so the caller
 * keeps the broadcast marked active and can retry. */
export async function deleteLiveInput(
  config: CloudflareStreamConfig,
  fetchImpl: LiveFetch,
  uid: string,
): Promise<void> {
  if (config.recordingMode === "automatic") {
    await purgeRecordings(config, fetchImpl, uid).catch(() => undefined);
  }
  const response = await fetchImpl(`${liveInputsUrl(config)}/${encodeURIComponent(uid)}`, {
    method: "DELETE",
    headers: headers(config),
  });
  if (!response.ok && response.status !== 404) {
    throw new Error(`CF_DELETE_FAILED:${response.status}`);
  }
}

/** Best effort: recordings of a live input are separate videos and outlive
 * the input itself, so delete each one explicitly. */
async function purgeRecordings(
  config: CloudflareStreamConfig,
  fetchImpl: LiveFetch,
  uid: string,
): Promise<void> {
  const list = await fetchImpl(
    `${liveInputsUrl(config)}/${encodeURIComponent(uid)}/videos`,
    { method: "GET", headers: headers(config) },
  );
  if (!list.ok) return;
  const json = (await list.json()) as { result?: Array<{ uid?: unknown }> };
  const videos = Array.isArray(json?.result) ? json.result : [];
  for (const video of videos) {
    const videoUid = asString(video?.uid);
    if (!videoUid) continue;
    await fetchImpl(
      `${API_ROOT}/accounts/${encodeURIComponent(config.accountId)}/stream/${encodeURIComponent(videoUid)}`,
      { method: "DELETE", headers: headers(config) },
    ).catch(() => undefined);
  }
}
