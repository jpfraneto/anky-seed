// -----------------------------------------------------------------------------
// Generation QA — cheap sanity checks before a painting is packaged.
// A failure triggers exactly one pipeline retry; a second failure surfaces.
// -----------------------------------------------------------------------------

import sharp from "sharp";
import { revealTuning as T } from "./revealTuning";
import { paletteHasWarmSwatch } from "./palette";

export type QaResult = {
  ok: boolean;
  reasons: string[];
};

export async function qaPainting(
  png: Uint8Array,
  palette: string[],
): Promise<QaResult> {
  const reasons: string[] = [];

  let width = 0;
  let height = 0;
  try {
    const metadata = await sharp(Buffer.from(png)).metadata();
    width = metadata.width ?? 0;
    height = metadata.height ?? 0;
  } catch {
    return { ok: false, reasons: ["UNDECODABLE"] };
  }

  if (width < 512 || height < 512) reasons.push("TOO_SMALL");
  if (
    height === 0 ||
    Math.abs(width / height - 1) > T.qaAspectTolerance
  ) {
    reasons.push("NOT_SQUARE");
  }

  // Flat/empty detection: luminance standard deviation.
  const { data } = await sharp(Buffer.from(png))
    .resize(64, 64, { fit: "fill" })
    .grayscale()
    .raw()
    .toBuffer({ resolveWithObject: true });
  let sum = 0;
  for (let i = 0; i < data.length; i++) sum += data[i] / 255;
  const mean = sum / data.length;
  let variance = 0;
  for (let i = 0; i < data.length; i++) {
    variance += (data[i] / 255 - mean) ** 2;
  }
  const stdDev = Math.sqrt(variance / data.length);
  if (stdDev < T.qaMinLuminanceStdDev) reasons.push("FLAT_IMAGE");

  if (palette.length < T.qaMinDistinctSwatches) reasons.push("MONOCHROME_PALETTE");
  if (!paletteHasWarmSwatch(palette)) reasons.push("NO_WARM_SWATCH");

  return { ok: reasons.length === 0, reasons };
}
