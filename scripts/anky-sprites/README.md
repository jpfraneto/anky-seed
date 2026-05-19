# Anky Sprite Preprocessing

This is a preprocessing-only pipeline for raw Anky sprite strips. It does not modify raw assets, wire anything into Swift, change Swift UI, or associate animations with app states.

Run from the repo root:

```sh
npx tsx scripts/anky-sprites/preprocess.ts
```

Inputs:

```text
apps/ios/Assets/AnkySprites/raw/
scripts/anky-sprites/config.json
```

Outputs:

```text
apps/ios/Assets/AnkySprites/processed/frames/{animation}/000.png
apps/ios/Assets/AnkySprites/processed/metadata/anky_animations.json
apps/ios/Assets/AnkySprites/processed/preview/index.html
apps/ios/Assets/AnkySprites/processed/preview/gifs/{animation}.gif
```

## Config-First Contract

Every raw PNG must have explicit config:

```json
{
  "animations": {
    "anky_example": {
      "file": "anky_example.png",
      "frameCount": 8,
      "fps": 8,
      "loop": true,
      "splitMode": "equal_width",
      "anchor": "bottom_center",
      "cropMode": "none",
      "backgroundMode": "light_checkerboard"
    }
  }
}
```

The script fails if a raw PNG is missing from config or config references a missing raw PNG.

## Splitting

The default and currently supported splitter is:

```json
"splitMode": "equal_width"
```

Before splitting, the script normalizes each strip to an integer-safe width:

```text
targetFrameWidth = ceil(sourceWidth / frameCount)
normalizedWidth = targetFrameWidth * frameCount
```

It creates a transparent `normalizedWidth x sourceHeight` canvas, copies the raw strip onto it with left alignment, saves it to `processed/normalized/{animation}.png`, then splits the normalized strip into exactly `frameCount` integer columns. It does not infer transparent gaps and does not crop before splitting.

## Background Cleanup

The current mode is:

```json
"backgroundMode": "light_checkerboard"
```

Cleanup runs after splitting, per frame. It flood-fills only light neutral checkerboard-like pixels connected to the frame border and turns them transparent. This is intentionally strict so colored glows, particles, portals, mirrors, sigils, and soft effects are preserved.

## Cropping

Available modes:

- `none`: preserve the full equal-width frame canvas.
- `trim_to_content`: trim transparent pixels to the visible content bounds.
- `character_anchor`: trim transparent pixels, then recenter around the bottom-center anchor while preserving detached effects inside the visible bounds.

All current animations are configured with:

```json
"cropMode": "none"
```

## Preview

The generated preview page includes:

- Static frames.
- A JavaScript looping animation preview for each animation.
- Animated GIF previews.
- Normalized strip previews.
- Per-animation FPS controls.
- CSS checkerboard preview backgrounds.
- Frame number overlay toggle.

## Validation

The script reports:

- Original strip size.
- Normalized strip size.
- Per-frame column size.
- Whether the strip was padded.
- Whether checkerboard cleanup removed pixels.
- Whether visible pixels touch frame edges.

It warns if:

- Source strips were padded during normalization.
- Fake light checkerboard-like pixels may remain.
- Visible pixels touch a frame edge.
