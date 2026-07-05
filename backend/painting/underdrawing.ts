// -----------------------------------------------------------------------------
// Programmatic underdrawing — derived from the final painting.
//
// Free, deterministic, pixel-perfect aligned (default for the poiesis lane).
// Recipe, in Steiner's spirit: sepia contour lines from the final's edges on
// warm parchment, faint watercolor veils breathing where the final's color
// masses live, and the ember of the light source barely glowing under ash.
// -----------------------------------------------------------------------------

import sharp from "sharp";

const PARCHMENT = { r: 243, g: 233, b: 216 };
const SEPIA_LINE = { r: 92, g: 66, b: 46 };
const VEIL_OPACITY = 0.16; // faint lasur washes
const LINE_OPACITY = 0.62;
const EMBER_OPACITY = 0.28;

export async function deriveUnderdrawing(finalPng: Uint8Array): Promise<Uint8Array> {
  const source = sharp(Buffer.from(finalPng));
  const { width = 1024, height = 1024 } = await source.metadata();

  // 1. Contour lines: blurred Sobel edges of the final, tinted sepia.
  const edges = await sharp(Buffer.from(finalPng))
    .grayscale()
    .blur(0.6)
    .convolve({
      width: 3,
      height: 3,
      kernel: [-1, -1, -1, -1, 8, -1, -1, -1, -1], // Laplacian: gestural lines
    })
    .normalise()
    .blur(0.4)
    .toBuffer();

  // Edge intensity becomes the alpha of a sepia line layer.
  const lineLayer = await sharp(edges)
    .composite([]) // no-op; keeps the pipeline explicit
    .linear(LINE_OPACITY, 0) // scale intensity into line opacity
    .toBuffer();
  const sepiaLines = await sharp({
    create: {
      width,
      height,
      channels: 3,
      background: SEPIA_LINE,
    },
  })
    .joinChannel(lineLayer) // gray edge map as alpha
    .png()
    .toBuffer();

  // 2. Watercolor veils: the final's palette, heavily blurred and desaturated
  //    — auras around the forms, a premonition of the painting.
  const veil = await sharp(Buffer.from(finalPng))
    .resize(Math.max(16, Math.floor(width / 32)), Math.max(16, Math.floor(height / 32)), {
      fit: "fill",
    })
    .blur(4)
    .modulate({ saturation: 0.5, brightness: 1.12 })
    .resize(width, height, { fit: "fill" })
    .ensureAlpha(VEIL_OPACITY)
    .png()
    .toBuffer();

  // 3. The ember: only the final's brightest warm light survives, faintly.
  //    Threshold high luminance, blur wide, warm tint, low opacity.
  const emberMask = await sharp(Buffer.from(finalPng))
    .grayscale()
    .threshold(215)
    .blur(Math.max(6, width / 90))
    .linear(EMBER_OPACITY, 0)
    .toBuffer();
  const ember = await sharp({
    create: {
      width,
      height,
      channels: 3,
      background: { r: 255, g: 196, b: 110 }, // warm ember gold
    },
  })
    .joinChannel(emberMask)
    .png()
    .toBuffer();

  // 4. Compose on parchment, add a whisper of grain so it reads as paper.
  const composed = await sharp({
    create: { width, height, channels: 3, background: PARCHMENT },
  })
    .composite([
      { input: veil, blend: "over" },
      { input: sepiaLines, blend: "over" },
      { input: ember, blend: "over" },
    ])
    .png({ compressionLevel: 9 })
    .toBuffer();

  return new Uint8Array(composed);
}
