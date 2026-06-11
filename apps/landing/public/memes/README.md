# Memes

The `/memes` route reads a JSON index from `VITE_MEMES_INDEX_URL`.

Local development falls back to:

```txt
/memes/index.json
```

For Cloudflare R2, deploy `cloudflare/memes-r2-worker.js` with an R2 bucket
binding named `MEMES_BUCKET`, then set:

```sh
VITE_MEMES_INDEX_URL=https://your-worker.example.workers.dev/memes.json
```

After that, upload meme images into the bucket from the Cloudflare dashboard.
The Worker lists image objects and serves them back to the frontend.
