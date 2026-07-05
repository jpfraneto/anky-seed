// -----------------------------------------------------------------------------
// Reveal-order map — painter's order, derived algorithmically.
//
// Output: a grayscale PNG (outputSize²) where pixel value 0-255 encodes when
// that pixel appears (0 = first stroke, 255 = last gold highlight). The iOS
// shader shows `final where revealMap < progress, else underdrawing`.
// -----------------------------------------------------------------------------

import sharp from "sharp";
import { revealTuning as T } from "./revealTuning";

type Features = {
  size: number;
  luminance: Float32Array;
  saturation: Float32Array;
  warmth: Float32Array; // (R - B), 0..1
  hueDeg: Float32Array;
  edges: Float32Array;
  difference: Float32Array; // |final - underdrawing| luminance
};

export type RevealMapResult = {
  revealMapPng: Uint8Array;
  lantern: { centerX: number; centerY: number; detected: boolean };
};

async function rawRgb(png: Uint8Array, size: number): Promise<Uint8Array> {
  const { data } = await sharp(Buffer.from(png))
    .resize(size, size, { fit: "fill" })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return new Uint8Array(data);
}

function computeFeatures(
  finalRgb: Uint8Array,
  underRgb: Uint8Array,
  size: number,
): Features {
  const n = size * size;
  const luminance = new Float32Array(n);
  const saturation = new Float32Array(n);
  const warmth = new Float32Array(n);
  const hueDeg = new Float32Array(n);
  const difference = new Float32Array(n);

  for (let i = 0; i < n; i++) {
    const r = finalRgb[i * 3] / 255;
    const g = finalRgb[i * 3 + 1] / 255;
    const b = finalRgb[i * 3 + 2] / 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    luminance[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    saturation[i] = max === 0 ? 0 : (max - min) / max;
    warmth[i] = Math.max(0, r - b);

    let hue = 0;
    const delta = max - min;
    if (delta > 0) {
      if (max === r) hue = 60 * (((g - b) / delta) % 6);
      else if (max === g) hue = 60 * ((b - r) / delta + 2);
      else hue = 60 * ((r - g) / delta + 4);
    }
    hueDeg[i] = hue < 0 ? hue + 360 : hue;

    const ur = underRgb[i * 3] / 255;
    const ug = underRgb[i * 3 + 1] / 255;
    const ub = underRgb[i * 3 + 2] / 255;
    const underLum = 0.2126 * ur + 0.7152 * ug + 0.0722 * ub;
    difference[i] = Math.abs(luminance[i] - underLum);
  }

  // Sobel edge magnitude on final luminance.
  const edges = new Float32Array(n);
  for (let y = 1; y < size - 1; y++) {
    for (let x = 1; x < size - 1; x++) {
      const i = y * size + x;
      const gx =
        -luminance[i - size - 1] - 2 * luminance[i - 1] - luminance[i + size - 1] +
        luminance[i - size + 1] + 2 * luminance[i + 1] + luminance[i + size + 1];
      const gy =
        -luminance[i - size - 1] - 2 * luminance[i - size] - luminance[i - size + 1] +
        luminance[i + size - 1] + 2 * luminance[i + size] + luminance[i + size + 1];
      edges[i] = Math.min(1, Math.hypot(gx, gy));
    }
  }

  return { size, luminance, saturation, warmth, hueDeg, edges, difference };
}

/** Separable box blur, in place-safe (returns a new array). */
function boxBlur(src: Float32Array, size: number, radius: number): Float32Array {
  if (radius <= 0) return src.slice();
  const tmp = new Float32Array(src.length);
  const out = new Float32Array(src.length);
  const window = radius * 2 + 1;
  // horizontal
  for (let y = 0; y < size; y++) {
    let sum = 0;
    for (let x = -radius; x <= radius; x++) {
      sum += src[y * size + Math.min(size - 1, Math.max(0, x))];
    }
    for (let x = 0; x < size; x++) {
      tmp[y * size + x] = sum / window;
      const outIdx = Math.max(0, x - radius);
      const inIdx = Math.min(size - 1, x + radius + 1);
      sum += src[y * size + inIdx] - src[y * size + outIdx];
    }
  }
  // vertical
  for (let x = 0; x < size; x++) {
    let sum = 0;
    for (let y = -radius; y <= radius; y++) {
      sum += tmp[Math.min(size - 1, Math.max(0, y)) * size + x];
    }
    for (let y = 0; y < size; y++) {
      out[y * size + x] = sum / window;
      const outIdx = Math.max(0, y - radius);
      const inIdx = Math.min(size - 1, y + radius + 1);
      sum += tmp[inIdx * size + x] - tmp[outIdx * size + x];
    }
  }
  return out;
}

/** Deterministic hash noise in [-1, 1] — no Math.random, reproducible. */
function hashNoise(x: number, y: number): number {
  let h = (x * 374761393 + y * 668265263) | 0;
  h = ((h ^ (h >> 13)) * 1274126177) | 0;
  return ((h ^ (h >> 16)) % 1000) / 500 - 1;
}

function findLantern(features: Features): {
  centerX: number;
  centerY: number;
  detected: boolean;
} {
  const { size, luminance, warmth } = features;
  const candidates: Array<{ i: number; score: number }> = [];
  for (let i = 0; i < luminance.length; i++) {
    if (luminance[i] >= T.lantern.minLuminance && warmth[i] >= T.lantern.minWarmth) {
      candidates.push({ i, score: luminance[i] * (0.5 + warmth[i]) });
    }
  }
  if (candidates.length === 0) {
    return {
      centerX: T.lantern.fallbackCenterX,
      centerY: T.lantern.fallbackCenterY,
      detected: false,
    };
  }
  candidates.sort((a, b) => b.score - a.score);
  const top = candidates.slice(
    0,
    Math.max(1, Math.floor(candidates.length * T.lantern.clusterTopFraction)),
  );
  let sumX = 0;
  let sumY = 0;
  for (const { i } of top) {
    sumX += (i % size) / size;
    sumY += Math.floor(i / size) / size;
  }
  return { centerX: sumX / top.length, centerY: sumY / top.length, detected: true };
}

/**
 * Builds the reveal-order map from the final painting and its underdrawing.
 * Deterministic: same inputs, same map.
 */
export async function buildRevealMap(
  finalPng: Uint8Array,
  underdrawingPng: Uint8Array,
): Promise<RevealMapResult> {
  const size = T.analysisSize;
  const [finalRgb, underRgb] = await Promise.all([
    rawRgb(finalPng, size),
    rawRgb(underdrawingPng, size),
  ]);
  const features = computeFeatures(finalRgb, underRgb, size);
  const n = size * size;

  // 1. Base score: higher paints later.
  const edgesRegion = boxBlur(features.edges, size, T.edgeBlurRadius);
  const score = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const x = (i % size) / size;
    const y = Math.floor(i / size) / size;
    const dx = x - 0.5;
    const dy = y - 0.5;
    const centrality = 1 - Math.min(1, Math.hypot(dx, dy) / 0.7071);
    score[i] =
      T.weightEdges * edgesRegion[i] +
      T.weightSaturation * features.saturation[i] +
      T.weightCentrality * centrality +
      T.weightDifference * features.difference[i];
  }

  // 2. Patch-shaped arrival: blur the score field before ranking.
  const smoothed = boxBlur(score, size, T.orderBlurRadius);

  // 3. Percentile rank → full 0..1 coverage regardless of score distribution.
  const order = new Float32Array(n);
  {
    const indices = Array.from({ length: n }, (_, i) => i);
    indices.sort((a, b) => smoothed[a] - smoothed[b]);
    for (let rank = 0; rank < n; rank++) {
      order[indices[rank]] = rank / (n - 1);
    }
  }

  // 4. Region overrides, preserving relative order inside each region.
  const remapRegion = (
    memberOf: (i: number) => boolean,
    bandStart: number,
    bandEnd: number,
  ) => {
    const members: number[] = [];
    for (let i = 0; i < n; i++) {
      if (memberOf(i)) members.push(i);
    }
    if (members.length === 0) return;
    members.sort((a, b) => order[a] - order[b]);
    for (let rank = 0; rank < members.length; rank++) {
      order[members[rank]] =
        bandStart + (bandEnd - bandStart) * (rank / Math.max(1, members.length - 1));
    }
  };

  const inFace = (i: number) => {
    const x = (i % size) / size;
    const y = Math.floor(i / size) / size;
    const fx = (x - T.faceEllipse.centerX) / T.faceEllipse.radiusX;
    const fy = (y - T.faceEllipse.centerY) / T.faceEllipse.radiusY;
    return fx * fx + fy * fy <= 1;
  };
  const inGold = (i: number) =>
    features.hueDeg[i] >= T.gold.hueMinDeg &&
    features.hueDeg[i] <= T.gold.hueMaxDeg &&
    features.saturation[i] >= T.gold.minSaturation &&
    features.luminance[i] >= T.gold.minLuminance;

  remapRegion(inFace, T.faceBandStart, T.faceBandEnd);
  // Gold wins over face: a gold earring inside the face ellipse lands last.
  remapRegion(inGold, T.goldBandStart, T.goldBandEnd);

  // 5. The lantern never waits — but the ember must follow the glow's own
  //    shape, not a stencil. Near the light source, clamp strength scales
  //    with the pixel's actual brightness and fades with distance, so what
  //    shows at 0% is the luminous core, feathering out organically.
  const lantern = findLantern(features);
  for (let i = 0; i < n; i++) {
    const x = (i % size) / size;
    const y = Math.floor(i / size) / size;
    const distance = Math.hypot(x - lantern.centerX, y - lantern.centerY);
    if (distance > T.lantern.featherRadius) continue;
    const falloff =
      distance <= T.lantern.radius
        ? 1
        : 1 -
          (distance - T.lantern.radius) /
            (T.lantern.featherRadius - T.lantern.radius);
    const brightness = Math.max(
      0,
      Math.min(1, (features.luminance[i] - 0.5) / 0.35),
    );
    const strength = falloff * brightness;
    if (strength <= 0) continue;
    const clampLevel =
      T.lantern.hardClampLevel +
      (1 - strength) * (T.lantern.featherClampLevel * 3);
    order[i] = Math.min(order[i], clampLevel / 255);
  }

  // 6. Quantize with deterministic dither so the frontier reads brushy.
  const gray = new Uint8Array(n);
  for (let i = 0; i < n; i++) {
    const x = i % size;
    const y = Math.floor(i / size);
    const dithered = order[i] * 255 + hashNoise(x, y) * T.ditherAmplitude;
    gray[i] = Math.max(0, Math.min(255, Math.round(dithered)));
  }

  const revealMapPng = await sharp(Buffer.from(gray), {
    raw: { width: size, height: size, channels: 1 },
  })
    .resize(T.outputSize, T.outputSize, { fit: "fill", kernel: "mitchell" })
    .png({ compressionLevel: 9 })
    .toBuffer();

  return { revealMapPng: new Uint8Array(revealMapPng), lantern };
}
