import * as fs from "node:fs/promises";
import * as path from "node:path";
import { deflateSync, inflateSync } from "node:zlib";

type SplitMode = "equal_width";
type CropMode = "none" | "trim_to_content" | "character_anchor";
type BackgroundMode = "none" | "light_checkerboard";
type Anchor = "bottom_center";

type PngImage = {
  width: number;
  height: number;
  data: Uint8Array;
};

type Bounds = {
  left: number;
  top: number;
  right: number;
  bottom: number;
};

type AnimationConfig = {
  file: string;
  frameCount: number;
  fps: number;
  loop: boolean;
  splitMode: SplitMode;
  anchor: Anchor;
  cropMode: CropMode;
  backgroundMode: BackgroundMode;
};

type Config = {
  rawDir?: string;
  outputDir?: string;
  gifPreviews?: boolean;
  animations: Record<string, AnimationConfig>;
};

type FrameOutput = {
  index: number;
  sourceRect: Bounds;
  sourceColumnWidth: number;
  image: PngImage;
  cleanup: CleanupResult;
  edgeClipping: EdgeClipping;
};

type CleanupResult = {
  removedPixels: number;
  remainingLightCheckerPixels: number;
};

type EdgeClipping = {
  left: number;
  right: number;
  top: number;
  bottom: number;
};

type AnimationMetadata = {
  name: string;
  file: string;
  sourceFile: string;
  normalizedPath: string;
  sourceWidth: number;
  sourceHeight: number;
  normalizedWidth: number;
  normalizedHeight: number;
  targetFrameWidth: number;
  sourceSize: { width: number; height: number };
  frameCount: number;
  fps: number;
  loop: boolean;
  splitMode: SplitMode;
  cropMode: CropMode;
  backgroundMode: BackgroundMode;
  anchor: Anchor;
  wasPadded: boolean;
  columnSize: { width: number; height: number };
  outputFrameSize: { width: number; height: number };
  checkerboardCleanup: {
    removedPixels: number;
    remainingLightCheckerPixels: number;
    happened: boolean;
  };
  edgeClippingDetected: boolean;
  gifPath?: string;
  frames: Array<{
    index: number;
    path: string;
    width: number;
    height: number;
    sourceRect: Bounds;
    sourceColumnWidth: number;
    cleanup: CleanupResult;
    edgeClipping: EdgeClipping;
  }>;
  warnings: string[];
};

const repoRoot = process.cwd();
const configPath = path.join(repoRoot, "scripts", "anky-sprites", "config.json");
const pngSignature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const crcTable = makeCrcTable();

async function main() {
  const config = await readConfig();
  const rawDir = path.resolve(repoRoot, config.rawDir ?? "apps/ios/Assets/AnkySprites/raw");
  const outputDir = path.resolve(repoRoot, config.outputDir ?? "apps/ios/Assets/AnkySprites/processed");
  const framesDir = path.join(outputDir, "frames");
  const normalizedDir = path.join(outputDir, "normalized");
  const metadataDir = path.join(outputDir, "metadata");
  const previewDir = path.join(outputDir, "preview");
  const gifsDir = path.join(previewDir, "gifs");

  const rawFiles = (await fs.readdir(rawDir))
    .filter((file) => file.toLowerCase().endsWith(".png"))
    .sort();
  validateConfigCoversRawFiles(rawFiles, config);

  await fs.rm(framesDir, { recursive: true, force: true });
  await fs.rm(normalizedDir, { recursive: true, force: true });
  await fs.rm(metadataDir, { recursive: true, force: true });
  await fs.rm(previewDir, { recursive: true, force: true });
  await fs.mkdir(framesDir, { recursive: true });
  await fs.mkdir(normalizedDir, { recursive: true });
  await fs.mkdir(metadataDir, { recursive: true });
  await fs.mkdir(gifsDir, { recursive: true });

  const animations: AnimationMetadata[] = [];
  const globalWarnings: string[] = [];

  for (const [name, animationConfig] of Object.entries(config.animations).sort(([a], [b]) => a.localeCompare(b))) {
    validateAnimationConfig(name, animationConfig);

    const sourcePath = path.join(rawDir, animationConfig.file);
    const source = decodePng(await fs.readFile(sourcePath));
    const warnings: string[] = [];
    const targetFrameWidth = Math.ceil(source.width / animationConfig.frameCount);
    const normalized = normalizeStrip(source, animationConfig.frameCount, targetFrameWidth);
    const normalizedPath = path.join(normalizedDir, `${name}.png`);
    const wasPadded = normalized.width !== source.width || normalized.height !== source.height;
    await fs.writeFile(normalizedPath, encodePng(normalized));

    if (wasPadded) {
      warnings.push(
        `Source width ${source.width} was padded to normalized width ${normalized.width} for ${animationConfig.frameCount} integer columns.`
      );
    }

    const frames = splitEqualWidth(normalized, animationConfig, targetFrameWidth);
    const outputFrames = frames.map((frame) => processFrame(frame, animationConfig));
    const animationFramesDir = path.join(framesDir, name);
    await fs.mkdir(animationFramesDir, { recursive: true });

    const frameMetadata: AnimationMetadata["frames"] = [];
    for (const frame of outputFrames) {
      const fileName = `${String(frame.index).padStart(3, "0")}.png`;
      const framePath = path.join(animationFramesDir, fileName);
      await fs.writeFile(framePath, encodePng(frame.image));
      frameMetadata.push({
        index: frame.index,
        path: slash(path.relative(outputDir, framePath)),
        width: frame.image.width,
        height: frame.image.height,
        sourceRect: frame.sourceRect,
        sourceColumnWidth: frame.sourceColumnWidth,
        cleanup: frame.cleanup,
        edgeClipping: frame.edgeClipping
      });
    }

    const cleanupTotals = outputFrames.reduce(
      (totals, frame) => ({
        removedPixels: totals.removedPixels + frame.cleanup.removedPixels,
        remainingLightCheckerPixels: totals.remainingLightCheckerPixels + frame.cleanup.remainingLightCheckerPixels
      }),
      { removedPixels: 0, remainingLightCheckerPixels: 0 }
    );
    const edgeClippingDetected = outputFrames.some((frame) =>
      frame.edgeClipping.left > 0 ||
      frame.edgeClipping.right > 0 ||
      frame.edgeClipping.top > 0 ||
      frame.edgeClipping.bottom > 0
    );

    if (cleanupTotals.remainingLightCheckerPixels > 0) {
      warnings.push(`Fake light checkerboard may remain (${cleanupTotals.remainingLightCheckerPixels} pixels).`);
    }
    if (edgeClippingDetected) {
      warnings.push("Visible pixels touch at least one frame edge; inspect for possible cut-off art.");
    }

    let gifPath: string | undefined;
    if (config.gifPreviews !== false) {
      try {
        const gifFilePath = path.join(gifsDir, `${name}.gif`);
        await fs.writeFile(gifFilePath, encodeGif(outputFrames.map((frame) => frame.image), animationConfig.fps, animationConfig.loop));
        gifPath = slash(path.relative(outputDir, gifFilePath));
      } catch (error) {
        warnings.push(`GIF preview was not generated: ${String(error)}`);
      }
    }

    const firstOutput = outputFrames[0]?.image;
    if (!firstOutput) {
      throw new Error(`${name}: no frames were produced.`);
    }

    const metadata: AnimationMetadata = {
      name,
      file: animationConfig.file,
      sourceFile: slash(path.relative(repoRoot, sourcePath)),
      normalizedPath: slash(path.relative(outputDir, normalizedPath)),
      sourceWidth: source.width,
      sourceHeight: source.height,
      normalizedWidth: normalized.width,
      normalizedHeight: normalized.height,
      targetFrameWidth,
      sourceSize: { width: source.width, height: source.height },
      frameCount: animationConfig.frameCount,
      fps: animationConfig.fps,
      loop: animationConfig.loop,
      splitMode: animationConfig.splitMode,
      cropMode: animationConfig.cropMode,
      backgroundMode: animationConfig.backgroundMode,
      anchor: animationConfig.anchor,
      wasPadded,
      columnSize: { width: targetFrameWidth, height: normalized.height },
      outputFrameSize: { width: firstOutput.width, height: firstOutput.height },
      checkerboardCleanup: {
        ...cleanupTotals,
        happened: cleanupTotals.removedPixels > 0
      },
      edgeClippingDetected,
      gifPath,
      frames: frameMetadata,
      warnings
    };

    animations.push(metadata);
    for (const warning of warnings) {
      globalWarnings.push(`${name}: ${warning}`);
    }
  }

  const metadata = {
    generatedAt: new Date().toISOString(),
    rawDir: slash(path.relative(repoRoot, rawDir)),
    outputDir: slash(path.relative(repoRoot, outputDir)),
    animationCount: animations.length,
    frameCount: animations.reduce((sum, animation) => sum + animation.frameCount, 0),
    warnings: globalWarnings,
    animations
  };

  await fs.writeFile(path.join(metadataDir, "anky_animations.json"), `${JSON.stringify(metadata, null, 2)}\n`);
  await fs.writeFile(path.join(previewDir, "index.html"), renderPreview(metadata));

  printSummary(metadata);
}

async function readConfig(): Promise<Config> {
  try {
    return JSON.parse(await fs.readFile(configPath, "utf8")) as Config;
  } catch (error) {
    throw new Error(`Unable to read ${path.relative(repoRoot, configPath)}: ${String(error)}`);
  }
}

function validateConfigCoversRawFiles(rawFiles: string[], config: Config) {
  const configuredFiles = new Map<string, string>();
  for (const [name, animation] of Object.entries(config.animations ?? {})) {
    if (animation.file) {
      configuredFiles.set(animation.file, name);
    }
  }

  const missing = rawFiles.filter((file) => !configuredFiles.has(file));
  if (missing.length > 0) {
    throw new Error(`Missing explicit animation config for raw PNG(s): ${missing.join(", ")}`);
  }

  const extra = [...configuredFiles.keys()].filter((file) => !rawFiles.includes(file));
  if (extra.length > 0) {
    throw new Error(`Config references missing raw PNG(s): ${extra.join(", ")}`);
  }
}

function validateAnimationConfig(name: string, animation: AnimationConfig) {
  const required: Array<keyof AnimationConfig> = [
    "file",
    "frameCount",
    "fps",
    "loop",
    "splitMode",
    "anchor",
    "cropMode",
    "backgroundMode"
  ];

  for (const key of required) {
    if (animation[key] === undefined) {
      throw new Error(`${name}: missing required config field "${key}".`);
    }
  }
  if (animation.splitMode !== "equal_width") {
    throw new Error(`${name}: unsupported splitMode "${animation.splitMode}". Use "equal_width".`);
  }
  if (!["none", "trim_to_content", "character_anchor"].includes(animation.cropMode)) {
    throw new Error(`${name}: unsupported cropMode "${animation.cropMode}".`);
  }
  if (!["none", "light_checkerboard"].includes(animation.backgroundMode)) {
    throw new Error(`${name}: unsupported backgroundMode "${animation.backgroundMode}".`);
  }
  if (animation.anchor !== "bottom_center") {
    throw new Error(`${name}: unsupported anchor "${animation.anchor}". Use "bottom_center".`);
  }
  if (!Number.isInteger(animation.frameCount) || animation.frameCount < 1) {
    throw new Error(`${name}: frameCount must be a positive integer.`);
  }
  if (!Number.isFinite(animation.fps) || animation.fps <= 0) {
    throw new Error(`${name}: fps must be greater than zero.`);
  }
}

function normalizeStrip(source: PngImage, frameCount: number, targetFrameWidth: number): PngImage {
  const normalizedWidth = targetFrameWidth * frameCount;
  const normalized = {
    width: normalizedWidth,
    height: source.height,
    data: new Uint8Array(normalizedWidth * source.height * 4)
  };

  for (let y = 0; y < source.height; y += 1) {
    for (let x = 0; x < source.width; x += 1) {
      const src = (y * source.width + x) * 4;
      const dst = (y * normalized.width + x) * 4;
      normalized.data[dst] = source.data[src];
      normalized.data[dst + 1] = source.data[src + 1];
      normalized.data[dst + 2] = source.data[src + 2];
      normalized.data[dst + 3] = source.data[src + 3];
    }
  }

  return normalized;
}

function splitEqualWidth(source: PngImage, config: AnimationConfig, targetFrameWidth: number): FrameOutput[] {
  const frames: FrameOutput[] = [];

  for (let index = 0; index < config.frameCount; index += 1) {
    const left = index * targetFrameWidth;
    const right = (index + 1) * targetFrameWidth;
    const sourceRect = { left, top: 0, right, bottom: source.height };
    const image = {
      width: targetFrameWidth,
      height: source.height,
      data: new Uint8Array(targetFrameWidth * source.height * 4)
    };

    for (let y = 0; y < source.height; y += 1) {
      for (let x = 0; x < targetFrameWidth; x += 1) {
        const src = (y * source.width + left + x) * 4;
        const dst = (y * image.width + x) * 4;
        image.data[dst] = source.data[src];
        image.data[dst + 1] = source.data[src + 1];
        image.data[dst + 2] = source.data[src + 2];
        image.data[dst + 3] = source.data[src + 3];
      }
    }

    frames.push({
      index,
      sourceRect,
      sourceColumnWidth: targetFrameWidth,
      image,
      cleanup: { removedPixels: 0, remainingLightCheckerPixels: 0 },
      edgeClipping: { left: 0, right: 0, top: 0, bottom: 0 }
    });
  }

  return frames;
}

function processFrame(frame: FrameOutput, config: AnimationConfig): FrameOutput {
  const cleaned = cloneImage(frame.image);
  const cleanup = config.backgroundMode === "light_checkerboard"
    ? removeLightCheckerboard(cleaned)
    : { removedPixels: 0, remainingLightCheckerPixels: 0 };
  const cropped = applyCropMode(cleaned, config.cropMode, config.anchor);
  const edgeClipping = detectEdgeClipping(cleaned);

  return {
    ...frame,
    image: cropped,
    cleanup,
    edgeClipping
  };
}

function removeLightCheckerboard(image: PngImage): CleanupResult {
  const visited = new Uint8Array(image.width * image.height);
  const queue: number[] = [];
  let removedPixels = 0;

  const enqueue = (x: number, y: number) => {
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
      return;
    }
    const pixel = y * image.width + x;
    if (visited[pixel]) {
      return;
    }
    const offset = pixel * 4;
    if (image.data[offset + 3] === 0 || isLightCheckerboardPixel(image.data, offset)) {
      visited[pixel] = 1;
      queue.push(pixel);
    }
  };

  for (let x = 0; x < image.width; x += 1) {
    enqueue(x, 0);
    enqueue(x, image.height - 1);
  }
  for (let y = 0; y < image.height; y += 1) {
    enqueue(0, y);
    enqueue(image.width - 1, y);
  }

  for (let head = 0; head < queue.length; head += 1) {
    const pixel = queue[head];
    const x = pixel % image.width;
    const y = Math.floor(pixel / image.width);
    const offset = pixel * 4;
    if (image.data[offset + 3] !== 0) {
      image.data[offset] = 0;
      image.data[offset + 1] = 0;
      image.data[offset + 2] = 0;
      image.data[offset + 3] = 0;
      removedPixels += 1;
    }
    enqueue(x + 1, y);
    enqueue(x - 1, y);
    enqueue(x, y + 1);
    enqueue(x, y - 1);
  }

  clearHiddenRgb(image);

  const remainingLightCheckerPixels = countBorderReachableLightCheckerboard(image);

  return { removedPixels, remainingLightCheckerPixels };
}

function isLightCheckerboardPixel(data: Uint8Array, offset: number) {
  const r = data[offset];
  const g = data[offset + 1];
  const b = data[offset + 2];
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const brightness = (r + g + b) / 3;

  return brightness >= 226 && max - min <= 14;
}

function countBorderReachableLightCheckerboard(image: PngImage) {
  const visited = new Uint8Array(image.width * image.height);
  const queue: number[] = [];
  let count = 0;

  const enqueue = (x: number, y: number) => {
    if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
      return;
    }
    const pixel = y * image.width + x;
    if (visited[pixel]) {
      return;
    }
    const offset = pixel * 4;
    if (image.data[offset + 3] !== 0 && isLightCheckerboardPixel(image.data, offset)) {
      visited[pixel] = 1;
      queue.push(pixel);
    }
  };

  for (let x = 0; x < image.width; x += 1) {
    enqueue(x, 0);
    enqueue(x, image.height - 1);
  }
  for (let y = 0; y < image.height; y += 1) {
    enqueue(0, y);
    enqueue(image.width - 1, y);
  }

  for (let head = 0; head < queue.length; head += 1) {
    const pixel = queue[head];
    const x = pixel % image.width;
    const y = Math.floor(pixel / image.width);
    count += 1;
    enqueue(x + 1, y);
    enqueue(x - 1, y);
    enqueue(x, y + 1);
    enqueue(x, y - 1);
  }

  return count;
}

function applyCropMode(image: PngImage, cropMode: CropMode, anchor: Anchor): PngImage {
  if (cropMode === "none") {
    return image;
  }

  const bounds = findOpaqueBounds(image);
  if (!bounds) {
    return image;
  }

  const trimmedWidth = bounds.right - bounds.left;
  const trimmedHeight = bounds.bottom - bounds.top;
  const trimmed = new Uint8Array(trimmedWidth * trimmedHeight * 4);
  for (let y = 0; y < trimmedHeight; y += 1) {
    for (let x = 0; x < trimmedWidth; x += 1) {
      const src = ((bounds.top + y) * image.width + bounds.left + x) * 4;
      const dst = (y * trimmedWidth + x) * 4;
      trimmed[dst] = image.data[src];
      trimmed[dst + 1] = image.data[src + 1];
      trimmed[dst + 2] = image.data[src + 2];
      trimmed[dst + 3] = image.data[src + 3];
    }
  }

  if (cropMode === "trim_to_content") {
    return { width: trimmedWidth, height: trimmedHeight, data: trimmed };
  }

  const anchorXInTrimmed = image.width / 2 - bounds.left;
  const anchorYInTrimmed = image.height - bounds.top;
  const leftRoom = Math.ceil(anchorXInTrimmed);
  const rightRoom = Math.ceil(trimmedWidth - anchorXInTrimmed);
  const topRoom = Math.ceil(anchorYInTrimmed);
  const bottomRoom = Math.ceil(trimmedHeight - anchorYInTrimmed);
  const canvas = {
    width: Math.max(leftRoom, rightRoom) * 2,
    height: topRoom + bottomRoom,
    data: new Uint8Array(Math.max(leftRoom, rightRoom) * 2 * (topRoom + bottomRoom) * 4)
  };
  const anchorX = anchor === "bottom_center" ? canvas.width / 2 : canvas.width / 2;
  const anchorY = canvas.height;
  const destLeft = Math.round(anchorX - anchorXInTrimmed);
  const destTop = Math.round(anchorY - anchorYInTrimmed);

  for (let y = 0; y < trimmedHeight; y += 1) {
    for (let x = 0; x < trimmedWidth; x += 1) {
      const src = (y * trimmedWidth + x) * 4;
      const dst = ((destTop + y) * canvas.width + destLeft + x) * 4;
      canvas.data[dst] = trimmed[src];
      canvas.data[dst + 1] = trimmed[src + 1];
      canvas.data[dst + 2] = trimmed[src + 2];
      canvas.data[dst + 3] = trimmed[src + 3];
    }
  }

  return canvas;
}

function detectEdgeClipping(image: PngImage): EdgeClipping {
  let left = 0;
  let right = 0;
  let top = 0;
  let bottom = 0;

  for (let y = 0; y < image.height; y += 1) {
    if (image.data[(y * image.width) * 4 + 3] > 0) {
      left += 1;
    }
    if (image.data[(y * image.width + image.width - 1) * 4 + 3] > 0) {
      right += 1;
    }
  }
  for (let x = 0; x < image.width; x += 1) {
    if (image.data[x * 4 + 3] > 0) {
      top += 1;
    }
    if (image.data[((image.height - 1) * image.width + x) * 4 + 3] > 0) {
      bottom += 1;
    }
  }

  return { left, right, top, bottom };
}

function findOpaqueBounds(image: PngImage): Bounds | undefined {
  let left = image.width;
  let right = 0;
  let top = image.height;
  let bottom = 0;

  for (let y = 0; y < image.height; y += 1) {
    for (let x = 0; x < image.width; x += 1) {
      if (image.data[(y * image.width + x) * 4 + 3] > 0) {
        left = Math.min(left, x);
        right = Math.max(right, x + 1);
        top = Math.min(top, y);
        bottom = Math.max(bottom, y + 1);
      }
    }
  }

  return right > left && bottom > top ? { left, top, right, bottom } : undefined;
}

function cloneImage(image: PngImage): PngImage {
  return {
    width: image.width,
    height: image.height,
    data: new Uint8Array(image.data)
  };
}

function clearHiddenRgb(image: PngImage) {
  for (let offset = 0; offset < image.data.length; offset += 4) {
    if (image.data[offset + 3] === 0) {
      image.data[offset] = 0;
      image.data[offset + 1] = 0;
      image.data[offset + 2] = 0;
    }
  }
}

function decodePng(buffer: Buffer): PngImage {
  if (!buffer.subarray(0, 8).equals(pngSignature)) {
    throw new Error("Invalid PNG signature.");
  }

  let offset = 8;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  const idatChunks: Buffer[] = [];

  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const data = buffer.subarray(offset + 8, offset + 8 + length);
    offset += 12 + length;

    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      if (data[10] !== 0 || data[11] !== 0 || data[12] !== 0) {
        throw new Error("Only non-interlaced PNGs with standard compression/filter are supported.");
      }
    } else if (type === "IDAT") {
      idatChunks.push(Buffer.from(data));
    } else if (type === "IEND") {
      break;
    }
  }

  if (width <= 0 || height <= 0) {
    throw new Error("PNG is missing a valid IHDR chunk.");
  }
  if (bitDepth !== 8 || ![0, 2, 6].includes(colorType)) {
    throw new Error(`Unsupported PNG format: bitDepth=${bitDepth}, colorType=${colorType}.`);
  }

  const channels = colorType === 6 ? 4 : colorType === 2 ? 3 : 1;
  const stride = width * channels;
  const inflated = inflateSync(Buffer.concat(idatChunks));
  const data = new Uint8Array(width * height * 4);
  const previous = new Uint8Array(stride);
  const current = new Uint8Array(stride);
  let inputOffset = 0;

  for (let y = 0; y < height; y += 1) {
    const filterType = inflated[inputOffset];
    inputOffset += 1;
    current.set(inflated.subarray(inputOffset, inputOffset + stride));
    inputOffset += stride;
    unfilterScanline(current, previous, channels, filterType);

    for (let x = 0; x < width; x += 1) {
      const src = x * channels;
      const dst = (y * width + x) * 4;
      if (colorType === 0) {
        data[dst] = current[src];
        data[dst + 1] = current[src];
        data[dst + 2] = current[src];
        data[dst + 3] = 255;
      } else if (colorType === 2) {
        data[dst] = current[src];
        data[dst + 1] = current[src + 1];
        data[dst + 2] = current[src + 2];
        data[dst + 3] = 255;
      } else {
        data[dst] = current[src];
        data[dst + 1] = current[src + 1];
        data[dst + 2] = current[src + 2];
        data[dst + 3] = current[src + 3];
      }
    }

    previous.set(current);
  }

  return { width, height, data };
}

function unfilterScanline(current: Uint8Array, previous: Uint8Array, bpp: number, filterType: number) {
  for (let i = 0; i < current.length; i += 1) {
    const left = i >= bpp ? current[i - bpp] : 0;
    const up = previous[i] ?? 0;
    const upLeft = i >= bpp ? previous[i - bpp] : 0;

    if (filterType === 0) {
      continue;
    } else if (filterType === 1) {
      current[i] = (current[i] + left) & 255;
    } else if (filterType === 2) {
      current[i] = (current[i] + up) & 255;
    } else if (filterType === 3) {
      current[i] = (current[i] + Math.floor((left + up) / 2)) & 255;
    } else if (filterType === 4) {
      current[i] = (current[i] + paeth(left, up, upLeft)) & 255;
    } else {
      throw new Error(`Unsupported PNG filter type ${filterType}.`);
    }
  }
}

function encodePng(image: PngImage): Buffer {
  const raw = Buffer.alloc((image.width * 4 + 1) * image.height);
  let rawOffset = 0;
  for (let y = 0; y < image.height; y += 1) {
    raw[rawOffset] = 0;
    rawOffset += 1;
    const rowStart = y * image.width * 4;
    raw.set(image.data.subarray(rowStart, rowStart + image.width * 4), rawOffset);
    rawOffset += image.width * 4;
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(image.width, 0);
  ihdr.writeUInt32BE(image.height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  return Buffer.concat([
    pngSignature,
    writeChunk("IHDR", ihdr),
    writeChunk("IDAT", deflateSync(raw)),
    writeChunk("IEND", Buffer.alloc(0))
  ]);
}

function encodeGif(frames: PngImage[], fps: number, loop: boolean): Buffer {
  if (frames.length === 0) {
    throw new Error("no frames");
  }
  const width = frames[0].width;
  const height = frames[0].height;
  if (!frames.every((frame) => frame.width === width && frame.height === height)) {
    throw new Error("all GIF frames must share dimensions");
  }

  const header = Buffer.from("GIF89a", "ascii");
  const logicalScreen = Buffer.alloc(7);
  logicalScreen.writeUInt16LE(width, 0);
  logicalScreen.writeUInt16LE(height, 2);
  logicalScreen[4] = 0xf7;
  logicalScreen[5] = 0;
  logicalScreen[6] = 0;

  const palette = buildGifPalette();
  const chunks = [header, logicalScreen, palette];

  if (loop) {
    chunks.push(Buffer.from([0x21, 0xff, 0x0b]));
    chunks.push(Buffer.from("NETSCAPE2.0", "ascii"));
    chunks.push(Buffer.from([0x03, 0x01, 0x00, 0x00, 0x00]));
  }

  const delay = Math.max(1, Math.round(100 / fps));
  for (const frame of frames) {
    const gce = Buffer.from([0x21, 0xf9, 0x04, 0x09, delay & 255, (delay >> 8) & 255, 0x00, 0x00]);
    const descriptor = Buffer.alloc(10);
    descriptor[0] = 0x2c;
    descriptor.writeUInt16LE(0, 1);
    descriptor.writeUInt16LE(0, 3);
    descriptor.writeUInt16LE(width, 5);
    descriptor.writeUInt16LE(height, 7);
    descriptor[9] = 0;
    chunks.push(gce, descriptor, Buffer.from([0x08]), gifSubBlocks(lzwLiteralEncode(rgbaToGifIndices(frame))));
  }

  chunks.push(Buffer.from([0x3b]));
  return Buffer.concat(chunks);
}

function buildGifPalette() {
  const palette = Buffer.alloc(256 * 3);
  for (let i = 1; i < 256; i += 1) {
    const r = (i >> 5) & 7;
    const g = (i >> 2) & 7;
    const b = i & 3;
    palette[i * 3] = Math.round((r / 7) * 255);
    palette[i * 3 + 1] = Math.round((g / 7) * 255);
    palette[i * 3 + 2] = Math.round((b / 3) * 255);
  }
  return palette;
}

function rgbaToGifIndices(frame: PngImage) {
  const indices = new Uint8Array(frame.width * frame.height);
  for (let pixel = 0; pixel < indices.length; pixel += 1) {
    const offset = pixel * 4;
    if (frame.data[offset + 3] < 128) {
      indices[pixel] = 0;
      continue;
    }
    const r = frame.data[offset] >> 5;
    const g = frame.data[offset + 1] >> 5;
    const b = frame.data[offset + 2] >> 6;
    indices[pixel] = Math.max(1, (r << 5) | (g << 2) | b);
  }
  return indices;
}

function lzwLiteralEncode(indices: Uint8Array) {
  const minCodeSize = 8;
  const clearCode = 1 << minCodeSize;
  const endCode = clearCode + 1;
  const codes: number[] = [clearCode];
  let sinceClear = 0;

  for (const index of indices) {
    if (sinceClear >= 250) {
      codes.push(clearCode);
      sinceClear = 0;
    }
    codes.push(index);
    sinceClear += 1;
  }
  codes.push(endCode);

  const bytes: number[] = [];
  let bitBuffer = 0;
  let bitCount = 0;
  for (const code of codes) {
    bitBuffer |= code << bitCount;
    bitCount += 9;
    while (bitCount >= 8) {
      bytes.push(bitBuffer & 255);
      bitBuffer >>= 8;
      bitCount -= 8;
    }
  }
  if (bitCount > 0) {
    bytes.push(bitBuffer & 255);
  }
  return Buffer.from(bytes);
}

function gifSubBlocks(data: Buffer) {
  const blocks: Buffer[] = [];
  for (let offset = 0; offset < data.length; offset += 255) {
    const block = data.subarray(offset, Math.min(offset + 255, data.length));
    blocks.push(Buffer.from([block.length]), block);
  }
  blocks.push(Buffer.from([0]));
  return Buffer.concat(blocks);
}

function renderPreview(metadata: {
  generatedAt: string;
  rawDir: string;
  outputDir: string;
  animationCount: number;
  frameCount: number;
  warnings: string[];
  animations: AnimationMetadata[];
}) {
  const warnings = metadata.warnings.length > 0
    ? `<section><h2>Warnings</h2><ul>${metadata.warnings.map((warning) => `<li>${escapeHtml(warning)}</li>`).join("")}</ul></section>`
    : "";

  const animations = metadata.animations.map((animation) => {
    const frameImages = animation.frames.map((frame) =>
      `<figure class="frame" data-frame="${frame.index}"><img src="../${escapeHtml(frame.path)}" alt="${escapeHtml(animation.name)} frame ${frame.index}"><figcaption>${String(frame.index).padStart(3, "0")}</figcaption></figure>`
    ).join("");
    const framesJson = JSON.stringify(animation.frames.map((frame) => `../${frame.path}`));
    const gif = animation.gifPath ? `<img class="gif" src="../${escapeHtml(animation.gifPath)}" alt="${escapeHtml(animation.name)} GIF preview">` : `<p>GIF preview unavailable.</p>`;
    const paddedWarning = animation.wasPadded
      ? `<p class="pad-warning">Source was padded from ${animation.sourceWidth}x${animation.sourceHeight} to ${animation.normalizedWidth}x${animation.normalizedHeight}.</p>`
      : "";

    return `<section class="animation" data-animation="${escapeHtml(animation.name)}" data-fps="${animation.fps}" data-frames='${escapeHtml(framesJson)}'>
  <header>
    <h2>${escapeHtml(animation.name)}</h2>
    <p>${animation.frameCount} frames, source ${animation.sourceWidth}x${animation.sourceHeight}, normalized ${animation.normalizedWidth}x${animation.normalizedHeight}, frame ${animation.targetFrameWidth}x${animation.normalizedHeight}</p>
    ${paddedWarning}
  </header>
  <div class="preview-row">
    <div>
      <h3>Animated GIF</h3>
      <div class="gif-wrap checker">${gif}</div>
    </div>
    <div>
      <h3>Interactive Preview</h3>
      <div class="player checker"><img class="player-frame" alt="${escapeHtml(animation.name)} animation preview"><span class="frame-number">000</span></div>
      <label class="fps">FPS <input type="range" min="1" max="24" step="1" value="${animation.fps}"><output>${animation.fps}</output></label>
    </div>
  </div>
  <h3>Normalized Strip</h3>
  <div class="strip checker"><img src="../${escapeHtml(animation.normalizedPath)}" alt="${escapeHtml(animation.name)} normalized strip"></div>
  <h3>Frames</h3>
  <div class="frames checker">${frameImages}</div>
</section>`;
  }).join("\n");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Anky Sprite Previews</title>
  <style>
    :root { color-scheme: light dark; font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; padding: 24px; background: Canvas; color: CanvasText; }
    h1 { margin: 0 0 8px; font-size: 24px; }
    h2 { margin: 0 0 8px; font-size: 18px; }
    h3 { margin: 0 0 8px; font-size: 13px; text-transform: uppercase; letter-spacing: 0; color: color-mix(in srgb, CanvasText 70%, transparent); }
    p { margin: 0 0 12px; color: color-mix(in srgb, CanvasText 72%, transparent); }
    section { margin: 0 0 28px; }
    .animation { border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding-top: 18px; }
    .pad-warning { color: #a15c00; font-weight: 600; }
    .checker {
      background-color: #fff;
      background-image:
        linear-gradient(45deg, #d9d9d9 25%, transparent 25%),
        linear-gradient(-45deg, #d9d9d9 25%, transparent 25%),
        linear-gradient(45deg, transparent 75%, #d9d9d9 75%),
        linear-gradient(-45deg, transparent 75%, #d9d9d9 75%);
      background-size: 18px 18px;
      background-position: 0 0, 0 9px, 9px -9px, -9px 0;
    }
    .toolbar { display: flex; align-items: center; gap: 12px; margin: 18px 0 24px; }
    .preview-row { display: flex; flex-wrap: wrap; align-items: flex-start; gap: 16px; margin-bottom: 16px; }
    .player, .gif-wrap { position: relative; display: grid; place-items: center; min-width: 160px; min-height: 160px; padding: 12px; border: 1px solid color-mix(in srgb, CanvasText 16%, transparent); border-radius: 6px; }
    img { display: block; image-rendering: pixelated; image-rendering: crisp-edges; max-width: 180px; height: auto; }
    .strip { overflow-x: auto; padding: 12px; border-radius: 6px; margin-bottom: 16px; }
    .strip img { max-width: none; height: 160px; }
    .frame-number { position: absolute; top: 6px; right: 6px; padding: 2px 5px; background: rgba(0,0,0,.72); color: #fff; border-radius: 4px; font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; }
    body.hide-numbers .frame-number, body.hide-numbers figcaption { display: none; }
    .fps { display: flex; align-items: center; gap: 8px; min-height: 34px; margin-top: 8px; }
    .frames { display: flex; flex-wrap: wrap; gap: 12px; align-items: flex-end; padding: 12px; border-radius: 6px; }
    figure { position: relative; margin: 0; padding: 8px; border: 1px solid color-mix(in srgb, CanvasText 14%, transparent); border-radius: 6px; background: rgba(255,255,255,.28); }
    figcaption { margin-top: 6px; font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; text-align: center; color: #111; }
    ul { color: #a15c00; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  </style>
</head>
<body>
  <header>
    <h1>Anky Sprite Previews</h1>
    <p>${metadata.animationCount} animations, ${metadata.frameCount} frames. Generated ${escapeHtml(metadata.generatedAt)}.</p>
    <p><code>${escapeHtml(metadata.rawDir)}</code> -> <code>${escapeHtml(metadata.outputDir)}</code></p>
    <label class="toolbar"><input id="toggle-numbers" type="checkbox" checked> Show frame numbers</label>
  </header>
  ${warnings}
  ${animations}
  <script>
    const toggle = document.getElementById("toggle-numbers");
    toggle.addEventListener("change", () => document.body.classList.toggle("hide-numbers", !toggle.checked));

    for (const section of document.querySelectorAll(".animation")) {
      const frames = JSON.parse(section.dataset.frames);
      const img = section.querySelector(".player-frame");
      const number = section.querySelector(".frame-number");
      const fpsInput = section.querySelector("input[type=range]");
      const fpsOutput = section.querySelector("output");
      let frame = 0;
      let last = 0;

      img.src = frames[0];
      function tick(now) {
        const fps = Number(fpsInput.value);
        if (now - last >= 1000 / fps) {
          frame = (frame + 1) % frames.length;
          img.src = frames[frame];
          number.textContent = String(frame).padStart(3, "0");
          last = now;
        }
        requestAnimationFrame(tick);
      }
      fpsInput.addEventListener("input", () => { fpsOutput.textContent = fpsInput.value; });
      requestAnimationFrame(tick);
    }
  </script>
</body>
</html>
`;
}

function printSummary(metadata: {
  animationCount: number;
  frameCount: number;
  warnings: string[];
  animations: AnimationMetadata[];
}) {
  console.log(`Processed ${metadata.animationCount} animations (${metadata.frameCount} frames).`);
  for (const animation of metadata.animations) {
    console.log(
      `- ${animation.name}: source ${animation.sourceWidth}x${animation.sourceHeight}, ` +
      `normalized ${animation.normalizedWidth}x${animation.normalizedHeight}, ` +
      `frame ${animation.targetFrameWidth}x${animation.normalizedHeight}, ` +
      `padded ${animation.wasPadded ? "yes" : "no"}, ` +
      `cleanup ${animation.checkerboardCleanup.happened ? "yes" : "no"}, ` +
      `edge clipping ${animation.edgeClippingDetected ? "yes" : "no"}`
    );
    for (const warning of animation.warnings) {
      console.log(`  warning: ${warning}`);
    }
  }
  console.log("Wrote apps/ios/Assets/AnkySprites/processed/normalized/{animation}.png");
  console.log("Wrote apps/ios/Assets/AnkySprites/processed/metadata/anky_animations.json");
  console.log("Wrote apps/ios/Assets/AnkySprites/processed/preview/index.html");
}

function paeth(left: number, up: number, upLeft: number) {
  const p = left + up - upLeft;
  const pa = Math.abs(p - left);
  const pb = Math.abs(p - up);
  const pc = Math.abs(p - upLeft);
  if (pa <= pb && pa <= pc) {
    return left;
  }
  return pb <= pc ? up : upLeft;
}

function writeChunk(type: string, data: Buffer) {
  const typeBuffer = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 0);
  return Buffer.concat([length, typeBuffer, data, crc]);
}

function makeCrcTable() {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c >>> 0;
  }
  return table;
}

function crc32(buffer: Buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) {
    c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatNumber(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(2);
}

function slash(value: string) {
  return value.split(path.sep).join("/");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
