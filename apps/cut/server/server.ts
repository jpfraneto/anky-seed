import { Hono } from "hono";
import path from "node:path";
import fs from "node:fs";
import { spawnSync } from "node:child_process";
import { MASKS } from "./masks";
import { chat } from "./anky";
import { renderTimeline } from "./render";
import type { ChatMessage, Clip, Timeline } from "../shared";

const ROOT = path.dirname(new URL(import.meta.url).pathname);
const UPLOADS = path.join(ROOT, "uploads");
const RENDERS = path.join(ROOT, "renders");
fs.mkdirSync(UPLOADS, { recursive: true });
fs.mkdirSync(RENDERS, { recursive: true });

// mediaId -> absolute path on disk
const media = new Map<string, string>();
// Re-hydrate uploads from previous runs so a server restart doesn't orphan clips.
for (const f of fs.readdirSync(UPLOADS)) {
  media.set(f.split(".")[0], path.join(UPLOADS, f));
}

const app = new Hono();

app.get("/api/health", (c) => c.json({ ok: true }));

app.get("/api/masks", (c) => c.json(MASKS));

app.post("/api/upload", async (c) => {
  const form = await c.req.formData();
  const file = form.get("file");
  if (!(file instanceof File)) return c.json({ error: "no file" }, 400);
  const id = crypto.randomUUID();
  const ext = path.extname(file.name) || ".mp4";
  const dest = path.join(UPLOADS, `${id}${ext}`);
  await Bun.write(dest, file);
  media.set(id, dest);

  // Probe duration server-side so the timeline has an authoritative value.
  const probe = spawnSync("ffprobe", [
    "-v", "error",
    "-show_entries", "format=duration",
    "-of", "default=noprint_wrappers=1:nokey=1",
    dest,
  ]);
  const duration = parseFloat(probe.stdout?.toString().trim() ?? "0") || 0;

  return c.json({ mediaId: id, duration });
});

app.post("/api/render", async (c) => {
  const { clips } = (await c.req.json()) as { clips: Clip[] };
  try {
    const outPath = await renderTimeline(clips, media, RENDERS);
    return c.json({ url: `/api/renders/${path.basename(outPath)}` });
  } catch (err) {
    return c.json({ error: String(err) }, 500);
  }
});

app.get("/api/renders/:name", (c) => {
  const name = path.basename(c.req.param("name"));
  const p = path.join(RENDERS, name);
  if (!fs.existsSync(p)) return c.notFound();
  return new Response(Bun.file(p), {
    headers: { "content-type": "video/mp4" },
  });
});

app.post("/api/anky/chat", async (c) => {
  const body = (await c.req.json()) as {
    maskId: string;
    messages: ChatMessage[];
    timeline: Timeline;
  };
  try {
    const reply = await chat(body.maskId, body.messages, body.timeline);
    return c.json(reply);
  } catch (err) {
    console.error(err);
    return c.json({ error: String(err) }, 500);
  }
});

// ElevenLabs realtime voice: hands the browser a signed conversation URL for
// the configured Conversational AI agent. Needs ELEVENLABS_API_KEY and
// ELEVENLABS_AGENT_ID in the environment.
app.get("/api/voice/signed-url", async (c) => {
  const key = process.env.ELEVENLABS_API_KEY;
  const agentId = process.env.ELEVENLABS_AGENT_ID;
  if (!key || !agentId) {
    return c.json({ error: "Set ELEVENLABS_API_KEY and ELEVENLABS_AGENT_ID to enable voice." }, 501);
  }
  const res = await fetch(
    `https://api.elevenlabs.io/v1/convai/conversation/get-signed-url?agent_id=${agentId}`,
    { headers: { "xi-api-key": key } },
  );
  if (!res.ok) return c.json({ error: `elevenlabs: ${res.status}` }, 502);
  return c.json(await res.json());
});

const port = 4319;
console.log(`anky cut server on http://localhost:${port}`);
export default { port, fetch: app.fetch, idleTimeout: 120 };
