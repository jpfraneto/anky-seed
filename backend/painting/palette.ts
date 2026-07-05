// -----------------------------------------------------------------------------
// Palette extraction — 4-6 dominant swatches for meta.json.
// The iOS LevelTheme derives the whole app's tint from these.
// -----------------------------------------------------------------------------

import sharp from "sharp";

const SAMPLE_SIZE = 64;
const K = 6;
const ITERATIONS = 12;

export async function extractPalette(png: Uint8Array): Promise<string[]> {
  const { data } = await sharp(Buffer.from(png))
    .resize(SAMPLE_SIZE, SAMPLE_SIZE, { fit: "fill" })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const pixels: Array<[number, number, number]> = [];
  for (let i = 0; i < data.length; i += 3) {
    pixels.push([data[i], data[i + 1], data[i + 2]]);
  }

  // Deterministic k-means: seed centroids from evenly spaced luminance ranks.
  const byLuminance = [...pixels].sort(
    (a, b) => luminance(a) - luminance(b),
  );
  let centroids: Array<[number, number, number]> = Array.from(
    { length: K },
    (_, k) => byLuminance[Math.floor(((k + 0.5) / K) * (byLuminance.length - 1))],
  );

  for (let iteration = 0; iteration < ITERATIONS; iteration++) {
    const sums = Array.from({ length: K }, () => [0, 0, 0, 0]);
    for (const pixel of pixels) {
      let best = 0;
      let bestDistance = Infinity;
      for (let k = 0; k < K; k++) {
        const d = distanceSq(pixel, centroids[k]);
        if (d < bestDistance) {
          bestDistance = d;
          best = k;
        }
      }
      sums[best][0] += pixel[0];
      sums[best][1] += pixel[1];
      sums[best][2] += pixel[2];
      sums[best][3] += 1;
    }
    centroids = centroids.map((centroid, k) => {
      const [r, g, b, count] = sums[k];
      if (count === 0) return centroid;
      return [r / count, g / count, b / count];
    });
  }

  // Drop near-duplicate centroids, sort dark → light, emit hex.
  const distinct: Array<[number, number, number]> = [];
  for (const centroid of centroids.sort((a, b) => luminance(a) - luminance(b))) {
    if (distinct.every((existing) => distanceSq(centroid, existing) > 400)) {
      distinct.push(centroid);
    }
  }
  return distinct.map(hex);
}

function luminance([r, g, b]: [number, number, number] | number[]): number {
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function distanceSq(
  a: [number, number, number] | number[],
  b: [number, number, number] | number[],
): number {
  return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2;
}

function hex([r, g, b]: [number, number, number] | number[]): string {
  const channel = (v: number) =>
    Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0");
  return `#${channel(r)}${channel(g)}${channel(b)}`;
}

/** True if any swatch is warm (reads as gold/ember/parchment). */
export function paletteHasWarmSwatch(palette: string[]): boolean {
  return palette.some((swatch) => {
    const r = parseInt(swatch.slice(1, 3), 16);
    const b = parseInt(swatch.slice(5, 7), 16);
    return r - b > 16;
  });
}
