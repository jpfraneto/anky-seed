# Anky Prompt Tester

Small local prompt-testing server for OpenRouter.

## Setup

Add your OpenRouter key to `.env`:

```sh
OPENROUTER_API_KEY=sk-or-...
PORT=3000
```

Install and run:

```sh
bun install
bun run dev
```

Open `http://localhost:3000`.

## Notes

- Default model: `anthropic/claude-sonnet-4.6`
- Streaming is enabled by default in the UI.
- Each successful run is written as JSON under `data/`.
- `data/*.json` is ignored by git so local prompt history stays local.
