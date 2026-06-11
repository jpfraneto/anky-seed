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
- `/memes`
- `/gallery`

Their markdown source lives in `src/legal/`.

## Memes

The memes route reads its image list from:

```txt
https://anky-memes.fairchat.workers.dev/memes.json
```

That Worker lists the Cloudflare R2 bucket named `anky-memes`. Upload new meme
images into that bucket from the Cloudflare dashboard and refresh `/memes`.

To point the frontend at another index URL, set:

```sh
VITE_MEMES_INDEX_URL=https://your-worker.example.workers.dev/memes.json
```

If the remote index is unavailable, the page falls back to
`public/memes/index.json`.

## Gallery

The gallery route reads its image list from:

```txt
https://anky-gallery.fairchat.workers.dev/gallery.json
```

That Worker lists the Cloudflare R2 bucket named `anky-gallery`. Upload images
into that bucket from the Cloudflare dashboard and refresh `/gallery`.
When both original and `.webp` variants exist for the same basename, the Worker
serves the `.webp` entry to the frontend.
