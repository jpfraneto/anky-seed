# Anky Cut

A small CapCut-style web editor where Anky lives inside the editor. Stitch clips, trim, speed, fade, filter — and talk to Anky, who wears different model masks and applies edits for you.

## Run

Two processes:

```sh
cd apps/cut
bun install

# 1. server (ffmpeg renders + AI lane), port 4319
bun run server

# 2. web app, port 4318 (proxies /api to the server)
bun run dev
```

Requires `ffmpeg`/`ffprobe` on PATH and `OPENROUTER_API_KEY` in the environment (same key the Anky backend uses).

## How it works

- **Frontend** (`src/`): Vite + React. Clips preview locally via object URLs — trims/speed/filters are approximated in the browser (seek + `playbackRate` + CSS filters). The timeline is plain JSON (`shared.ts`).
- **Server** (`server/`): Bun + Hono.
  - `POST /api/upload` stores media, probes duration with ffprobe.
  - `POST /api/render` builds an ffmpeg `filter_complex` (trim → setpts/atempo → scale/pad 1280×720\@30 → fades/filters → concat) and returns an MP4.
  - `POST /api/anky/chat` is the AI lane: OpenRouter chat completions with an `apply_edits` tool. The model returns edit ops; the frontend applies them to the timeline. System prompt carries the current timeline JSON.
- **Masks** (`server/masks.ts`): Anky is one character, many faces. Everything routes through OpenRouter, so all five masks are live: Opus 4.8, Fable 5, Haiku 4.5, Kimi 2.6, GPT-5.6 Sol. Adding a mask is one entry with an OpenRouter slug.

## Voice (ElevenLabs realtime)

`GET /api/voice/signed-url` returns a signed Conversational-AI URL when `ELEVENLABS_API_KEY` and `ELEVENLABS_AGENT_ID` are set. To go realtime voice:

1. Create a Conversational AI agent in the ElevenLabs dashboard.
2. Add `@elevenlabs/client` in the frontend and start a conversation with the signed URL.
3. Register `apply_edits` as a **client tool** on the agent so the voice conversation can drive the timeline the same way the text lane does.

## Known limitations (MVP)

- Clips without an audio track will fail the render (the concat expects audio). Workaround: add audio or extend `render.ts` with an `anullsrc` fallback.
- Preview is an approximation; the ffmpeg export is the source of truth.
- Uploads/renders live on disk under `server/uploads` and `server/renders`; media map is rebuilt from the uploads dir on restart.
