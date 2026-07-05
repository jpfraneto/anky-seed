import { defaultShowState } from "../state/defaultState";
import { deepMerge } from "../state/deepMerge";
import type { ServerWebSocket } from "bun";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { DeepPartial, ShowState, VoiceMask } from "../state/showState";

let showState = structuredClone(defaultShowState);
const clients = new Set<ServerWebSocket<undefined>>();
const voiceOrigin = normalizeOrigin(process.env.VOICE_ENGINE_ORIGIN ?? "https://voice.anky.app");
const publicOrigin = normalizeOrigin(process.env.SHOW_STATE_PUBLIC_ORIGIN ?? "http://localhost:8787");
const voiceSyncEnabled = process.env.VOICE_SYNC_ENABLED !== "0";
const voiceSyncIntervalMs = Number(process.env.VOICE_SYNC_INTERVAL_MS ?? 5000);
const writeToken = process.env.SHOW_STATE_WRITE_TOKEN;
const captionFile =
  process.env.VOICE_CAPTION_FILE === "0"
    ? null
    : (process.env.VOICE_CAPTION_FILE ?? join(process.cwd(), "run", "caption.txt"));
let lastMaskPayload = "";
let lastCaptionText = "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

Bun.serve({
  port: Number(process.env.SHOW_STATE_PORT ?? 8787),

  async fetch(req, server) {
    const url = new URL(req.url);

    if (req.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    if (url.pathname === "/ws") {
      const ok = server.upgrade(req);
      return ok ? undefined : new Response("WebSocket upgrade failed", { status: 400 });
    }

    if (url.pathname === "/state") {
      return Response.json(showState, { headers: corsHeaders });
    }

    if (url.pathname === "/voice/mask") {
      const mask = await fetchVoiceMask();
      return Response.json(mask, { headers: corsHeaders });
    }

    if (url.pathname.startsWith("/voice/mask-image/")) {
      const key = url.pathname.split("/").pop();
      const upstream = await fetch(`${voiceOrigin}/api/mask-image/${key}`);

      if (!upstream.ok) {
        return new Response("Mask image not found", { status: upstream.status, headers: corsHeaders });
      }

      return new Response(upstream.body, {
        headers: {
          ...corsHeaders,
          "Content-Type": upstream.headers.get("Content-Type") ?? "application/octet-stream",
          "Cache-Control": "public, max-age=15",
        },
      });
    }

    if (url.pathname === "/caption") {
      return Response.json(showState.caption, { headers: corsHeaders });
    }

    if (url.pathname === "/voice/sync" && req.method === "POST") {
      const unauthorized = requireWriteAuth(req);
      if (unauthorized) {
        return unauthorized;
      }

      await syncVoiceState({ force: true });
      return Response.json({ ok: true, state: showState }, { headers: corsHeaders });
    }

    if (url.pathname === "/voice/caption" && req.method === "POST") {
      const unauthorized = requireWriteAuth(req);
      if (unauthorized) {
        return unauthorized;
      }

      const body = (await req.json()) as {
        speaker?: string;
        text?: string;
        caption?: string;
      };
      const text = body.text ?? body.caption ?? "";

      if (!text.trim()) {
        return Response.json(
          { ok: false, error: "Missing caption text" },
          { status: 400, headers: corsHeaders },
        );
      }

      const patch: DeepPartial<ShowState> = {
        caption: {
          speaker: body.speaker ?? "live",
          text,
          updatedAt: new Date().toISOString(),
        },
      };
      showState = deepMerge(showState, patch);
      broadcast({ type: "state.patch", patch, state: showState });

      return Response.json({ ok: true, state: showState }, { headers: corsHeaders });
    }

    if (url.pathname === "/voice/event" && req.method === "POST") {
      const unauthorized = requireWriteAuth(req);
      if (unauthorized) {
        return unauthorized;
      }

      const event = (await req.json()) as {
        type?: string;
        mask?: VoiceMask;
        caption?: { speaker?: string; text?: string };
        patch?: DeepPartial<ShowState>;
      };
      let patch: DeepPartial<ShowState> = {};

      if (event.mask) {
        patch = deepMerge(patch, voiceMaskToPatch(event.mask, true));
      }

      if (event.caption?.text) {
        patch = deepMerge(patch, {
          caption: {
            speaker: event.caption.speaker ?? "live",
            text: event.caption.text,
            updatedAt: new Date().toISOString(),
          },
        });
      }

      if (event.patch) {
        patch = deepMerge(patch, event.patch);
      }

      showState = deepMerge(showState, patch);
      broadcast({ type: "state.patch", patch, state: showState });

      return Response.json({ ok: true, state: showState }, { headers: corsHeaders });
    }

    if (url.pathname === "/patch" && req.method === "POST") {
      const unauthorized = requireWriteAuth(req);
      if (unauthorized) {
        return unauthorized;
      }

      const patch = (await req.json()) as DeepPartial<ShowState>;
      showState = deepMerge(showState, patch);
      broadcast({ type: "state.patch", patch, state: showState });

      return Response.json({ ok: true, state: showState }, { headers: corsHeaders });
    }

    if (url.pathname === "/reset" && req.method === "POST") {
      const unauthorized = requireWriteAuth(req);
      if (unauthorized) {
        return unauthorized;
      }

      showState = structuredClone(defaultShowState);
      broadcast({ type: "state.full", state: showState });

      return Response.json({ ok: true, state: showState }, { headers: corsHeaders });
    }

    return new Response("Not found", { status: 404, headers: corsHeaders });
  },

  websocket: {
    open(ws) {
      clients.add(ws);
      ws.send(JSON.stringify({ type: "state.full", state: showState }));
    },

    message() {
      // Renderer clients only receive state. Mutations go through POST /patch.
    },

    close(ws) {
      clients.delete(ws);
    },
  },
});

function broadcast(message: unknown) {
  const payload = JSON.stringify(message);

  for (const client of clients) {
    client.send(payload);
  }
}

function requireWriteAuth(req: Request) {
  if (!writeToken) {
    return null;
  }

  const headerToken =
    req.headers.get("x-show-state-token") ??
    req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");

  if (headerToken === writeToken) {
    return null;
  }

  return Response.json({ ok: false, error: "Unauthorized" }, { status: 401, headers: corsHeaders });
}

async function syncVoiceState({ force = false } = {}) {
  await Promise.all([syncVoiceMask(force), syncCaptionFile(force)]);
}

async function syncVoiceMask(force: boolean) {
  try {
    const mask = await fetchVoiceMask();
    const payload = JSON.stringify(mask);

    if (!force && payload === lastMaskPayload) {
      return;
    }

    lastMaskPayload = payload;
    const patch = voiceMaskToPatch(mask, true);
    showState = deepMerge(showState, patch);
    broadcast({ type: "state.patch", patch, state: showState });
  } catch (error) {
    const patch: DeepPartial<ShowState> = {
      voice: {
        origin: voiceOrigin,
        connected: false,
        lastSyncAt: new Date().toISOString(),
      },
    };
    showState = deepMerge(showState, patch);

    if (force) {
      broadcast({ type: "state.patch", patch, state: showState });
    }

    console.warn("Voice mask sync failed", error);
  }
}

async function fetchVoiceMask(): Promise<VoiceMask> {
  const response = await fetch(`${voiceOrigin}/api/mask`, {
    headers: { Accept: "application/json" },
  });

  if (!response.ok) {
    throw new Error(`GET /api/mask failed: ${response.status}`);
  }

  return (await response.json()) as VoiceMask;
}

function voiceMaskToPatch(mask: VoiceMask, connected: boolean): DeepPartial<ShowState> {
  const label = mask.label || mask.name || mask.key;
  const imagePath = mask.key ? `/voice/mask-image/${encodeURIComponent(mask.key)}` : mask.image;
  const imageSrc = mask.image.startsWith("http") ? mask.image : `${publicOrigin}${imagePath}`;

  return {
    voice: {
      origin: voiceOrigin,
      connected,
      lastSyncAt: new Date().toISOString(),
      mask,
    },
    guest: {
      kind: "image",
      src: imageSrc,
      title: label,
    },
    center: {
      caption: mask.title,
    },
    lowerThird: {
      headline: {
        before: mask.format || "Tonight Anky Becomes",
        highlight: label,
        after: "",
      },
      quote: {
        speaker: mask.name || label,
        text: mask.invocation,
      },
      cta: mask.subtitle,
    },
    caption: {
      speaker: label,
      text: mask.invocation,
      updatedAt: new Date().toISOString(),
    },
  };
}

async function syncCaptionFile(force: boolean) {
  if (!captionFile) {
    return;
  }

  try {
    const text = (await readFile(captionFile, "utf8")).trim();

    if (!text || (!force && text === lastCaptionText)) {
      return;
    }

    lastCaptionText = text;
    const patch: DeepPartial<ShowState> = {
      caption: {
        speaker: "live",
        text,
        updatedAt: new Date().toISOString(),
      },
    };
    showState = deepMerge(showState, patch);
    broadcast({ type: "state.patch", patch, state: showState });
  } catch {
    // The speech engine creates this file only after a live session starts.
  }
}

function normalizeOrigin(origin: string) {
  return origin.replace(/\/$/, "");
}

if (voiceSyncEnabled) {
  syncVoiceState({ force: true });
  setInterval(() => syncVoiceState(), voiceSyncIntervalMs);
}

console.log(`Show state server listening on http://localhost:${process.env.SHOW_STATE_PORT ?? 8787}`);
console.log(`Voice bridge upstream: ${voiceOrigin}`);
console.log(`Voice caption file: ${captionFile ?? "disabled"}`);
console.log(`Write auth: ${writeToken ? "enabled" : "disabled"}`);
