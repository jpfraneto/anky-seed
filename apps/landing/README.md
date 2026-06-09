# Anky Landing

Standalone React + Vite + TypeScript landing page for Anky.

## Run

```sh
bun install
bun run dev
```

From the repo root:

```sh
bun run --cwd apps/landing dev
```

## Checks

```sh
bun run lint
bun run build
```

## Assets

The landing page reuses safe public-facing iOS assets copied into `public/anky-assets/`:

- `anky-sigil.png`
- `anky-avatar.png`
- `cosmos.png`
- `app-icon.png`
- `frames/` Anky companion sprite frames from the iOS app

Store links are placeholders until the real App Store and Google Play URLs are available.

## Local Pages

The legal/protocol documents are rendered inside the Vite app at:

- `/protocol`
- `/privacy`
- `/terms`

Their markdown source lives in `src/legal/`.
