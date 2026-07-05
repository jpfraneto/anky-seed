# Today Anky Becomes Broadcast Engine

State-driven 16:9 browser scene for OBS.

## Run

```sh
bun install
bun run dev
```

Open:

- OBS Browser Source: `http://localhost:5173/overlay`
- Control dashboard: `http://localhost:5173/control`
- State API: `http://localhost:8787/state`
- Voice mask bridge: `http://localhost:8787/voice/mask`

Use a 1920x1080 OBS browser source. The default host slot is `obs`, so OBS can place the camera source underneath the browser scene. Switch `host.source` to `camera` if you want the browser itself to request a webcam.

## Voice Backend Bridge

The voice backend and OBS overlay may run on different machines. In that setup, do not rely on `127.0.0.1` or `run/caption.txt` across machines.

By default the scene state server pulls active mask metadata from:

```sh
https://voice.anky.app/api/mask
```

The mask metadata is mapped into the broadcast scene:

- `guest`: active mask image and label
- `center.caption`: active episode title
- `lowerThird.headline`: format plus mask label
- `lowerThird.quote`: mask name plus invocation line
- `lowerThird.cta`: mask subtitle
- `caption`: invocation line until live captions arrive

When this engine runs beside the speech backend, it also polls `run/caption.txt` and pushes the latest live caption into the center subtitle surface. Override paths/origin with:
This is only useful when both processes are on the same machine.

```sh
VOICE_ENGINE_ORIGIN=http://127.0.0.1:3011
VOICE_CAPTION_FILE=/Users/kithkui/anky/livestream/run/caption.txt
SHOW_STATE_PUBLIC_ORIGIN=http://localhost:8787
```

For different machines, use a network bridge:

1. Run this engine on the OBS machine.
2. Expose the state server port `8787` with a tunnel or deploy it somewhere reachable by the voice machine.
3. Set `SHOW_STATE_PUBLIC_ORIGIN` to that reachable URL.
4. Have the voice backend `POST` captions/events to the reachable URL.

Recommended when exposing writes publicly:

```sh
SHOW_STATE_WRITE_TOKEN=replace-with-a-long-secret bun run dev
```

Push a live caption from the voice machine:

```sh
curl -X POST "$SHOW_STATE_PUBLIC_ORIGIN/voice/caption" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SHOW_STATE_WRITE_TOKEN" \
  -d '{
    "speaker": "JP",
    "text": "Albert, what did humans misunderstand about intelligence?"
  }'
```

Push a combined voice event:

```sh
curl -X POST "$SHOW_STATE_PUBLIC_ORIGIN/voice/event" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SHOW_STATE_WRITE_TOKEN" \
  -d '{
    "caption": {
      "speaker": "EINSTEIN",
      "text": "they mistook calculation for judgment."
    }
  }'
```

Force a sync:

```sh
curl -X POST http://localhost:8787/voice/sync
```

## Patch State

```sh
curl -X POST http://localhost:8787/patch \
  -H "Content-Type: application/json" \
  -d '{
    "guest": {
      "kind": "image",
      "src": "/assets/anky-einstein.svg",
      "title": "Anky as Satoshi"
    },
    "lowerThird": {
      "headline": {
        "before": "What is Bitcoin",
        "highlight": "teaching us?",
        "after": ""
      },
      "quote": {
        "speaker": "Satoshi",
        "text": "A network can become a clock for truth"
      }
    }
  }'
```

Reset the in-memory state:

```sh
curl -X POST http://localhost:8787/reset
```

## Shape

- `src/renderer`: OBS scene renderer
- `src/control`: local private dashboard
- `src/state`: shared types, defaults, merge logic, browser hook
- `src/server`: Bun WebSocket and patch server
- `public/assets`: show images and video files
- `public/tokens`: ticker icons
