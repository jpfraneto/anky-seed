// -----------------------------------------------------------------------------
// Underdrawing ↔ final alignment.
//
// Model-generated underdrawings drift. Small drift is fine (the reveal is
// stroke-shaped, not a morph); measurable drift gets a translate-warp; poor
// correlation triggers one regeneration upstream. Programmatic underdrawings
// are pixel-perfect by construction and skip all of this.
// -----------------------------------------------------------------------------

import sharp from "sharp";
import { revealTuning as T } from "./revealTuning";

export type AlignmentResult = {
  offsetX: number; // at alignSize resolution
  offsetY: number;
  correlation: number; // best normalized cross-correlation, -1..1
  needsWarp: boolean;
  needsRegeneration: boolean;
};

async function grayAt(png: Uint8Array, size: number): Promise<Float32Array> {
  const { data } = await sharp(Buffer.from(png))
    .resize(size, size, { fit: "fill" })
    .grayscale()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const out = new Float32Array(size * size);
  for (let i = 0; i < out.length; i++) out[i] = data[i] / 255;
  return out;
}

function ncc(
  a: Float32Array,
  b: Float32Array,
  size: number,
  dx: number,
  dy: number,
): number {
  let sumA = 0;
  let sumB = 0;
  let count = 0;
  for (let y = 0; y < size; y++) {
    const by = y + dy;
    if (by < 0 || by >= size) continue;
    for (let x = 0; x < size; x++) {
      const bx = x + dx;
      if (bx < 0 || bx >= size) continue;
      sumA += a[y * size + x];
      sumB += b[by * size + bx];
      count++;
    }
  }
  if (count === 0) return -1;
  const meanA = sumA / count;
  const meanB = sumB / count;
  let numerator = 0;
  let denomA = 0;
  let denomB = 0;
  for (let y = 0; y < size; y++) {
    const by = y + dy;
    if (by < 0 || by >= size) continue;
    for (let x = 0; x < size; x++) {
      const bx = x + dx;
      if (bx < 0 || bx >= size) continue;
      const da = a[y * size + x] - meanA;
      const db = b[by * size + bx] - meanB;
      numerator += da * db;
      denomA += da * da;
      denomB += db * db;
    }
  }
  const denominator = Math.sqrt(denomA * denomB);
  return denominator === 0 ? 0 : numerator / denominator;
}

export async function measureAlignment(
  finalPng: Uint8Array,
  underdrawingPng: Uint8Array,
): Promise<AlignmentResult> {
  const size = T.alignSize;
  const [finalGray, underGray] = await Promise.all([
    grayAt(finalPng, size),
    grayAt(underdrawingPng, size),
  ]);

  let best = { dx: 0, dy: 0, correlation: -1 };
  for (let dy = -T.alignMaxOffsetPx; dy <= T.alignMaxOffsetPx; dy++) {
    for (let dx = -T.alignMaxOffsetPx; dx <= T.alignMaxOffsetPx; dx++) {
      const correlation = ncc(finalGray, underGray, size, dx, dy);
      if (correlation > best.correlation) {
        best = { dx, dy, correlation };
      }
    }
  }

  const offsetMagnitude = Math.max(Math.abs(best.dx), Math.abs(best.dy));
  return {
    offsetX: best.dx,
    offsetY: best.dy,
    correlation: best.correlation,
    needsWarp:
      offsetMagnitude > T.alignWarpThresholdPx &&
      best.correlation >= T.alignMinCorrelation,
    needsRegeneration: best.correlation < T.alignMinCorrelation,
  };
}

/** Translates the underdrawing by the measured offset (edge-extended). */
export async function warpUnderdrawing(
  underdrawingPng: Uint8Array,
  alignment: AlignmentResult,
): Promise<Uint8Array> {
  const image = sharp(Buffer.from(underdrawingPng));
  const { width = 0, height = 0 } = await image.metadata();
  if (width === 0 || height === 0) return underdrawingPng;

  const scale = width / T.alignSize;
  const shiftX = Math.round(alignment.offsetX * scale);
  const shiftY = Math.round(alignment.offsetY * scale);
  if (shiftX === 0 && shiftY === 0) return underdrawingPng;

  // The measured offset says under(x + dx) matches final(x): shift the
  // underdrawing by (dx, dy) so the two align.
  const extended = await image
    .extend({
      top: Math.max(0, shiftY),
      bottom: Math.max(0, -shiftY),
      left: Math.max(0, shiftX),
      right: Math.max(0, -shiftX),
      background: { r: 243, g: 233, b: 216 }, // parchment, never black
    })
    .toBuffer();

  const shifted = await sharp(extended)
    .extract({
      left: Math.max(0, -shiftX),
      top: Math.max(0, -shiftY),
      width,
      height,
    })
    .png()
    .toBuffer();
  return new Uint8Array(shifted);
}
