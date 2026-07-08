// -----------------------------------------------------------------------------
// Publishes webp versions of the seeded default paintings (levels 2–8) to the
// public R2 bucket the app's locked gallery tiles load from.
//
// For each level: download final.png + underdrawing.png from the admin debug
// asset route, upload the original png, convert to webp with sharp and upload
// that too — via wrangler to
//   anky-gallery/paintings/defaults/level-<N>/{final,underdrawing}.{png,webp}
// served publicly at
//   https://anky-gallery.fairchat.workers.dev/gallery/paintings/defaults/...
// The app's locked tiles load the webp; the png is the full-quality original.
//
// Usage: ANKY_ADMIN_KEY=... bun scripts/publish-default-paintings-webp.ts [--level N]
// -----------------------------------------------------------------------------

import sharp from "sharp";
import { mkdirSync } from "node:fs";
import { tmpdir } from "node:os";

const BASE_URL = process.env.ANKY_BASE_URL ?? "https://mirror-production-a23c.up.railway.app";
const ADMIN_KEY = process.env.ANKY_ADMIN_KEY ?? "";
const BUCKET = "anky-gallery";
const FILES = ["final.png", "underdrawing.png"] as const;

if (!ADMIN_KEY) {
  console.error("ANKY_ADMIN_KEY is required");
  process.exit(1);
}

const levelFlag = process.argv.indexOf("--level");
const levels =
  levelFlag !== -1 && process.argv[levelFlag + 1]
    ? [Number(process.argv[levelFlag + 1])]
    : [2, 3, 4, 5, 6, 7, 8];

const workDir = `${tmpdir()}/anky-default-webp`;
mkdirSync(workDir, { recursive: true });

for (const level of levels) {
  for (const file of FILES) {
    const res = await fetch(
      `${BASE_URL}/debug/default-painting-asset?level=${level}&file=${file}`,
      { headers: { Authorization: `Bearer ${ADMIN_KEY}` } },
    );
    if (!res.ok) {
      console.error(`level ${level} ${file}: HTTP ${res.status} — is the level seeded?`);
      process.exit(1);
    }
    const png = new Uint8Array(await res.arrayBuffer());
    const webp = await sharp(png).webp({ quality: 86 }).toBuffer();

    const variants: Array<{ name: string; bytes: Uint8Array; contentType: string }> = [
      { name: file, bytes: png, contentType: "image/png" },
      { name: file.replace(".png", ".webp"), bytes: new Uint8Array(webp), contentType: "image/webp" },
    ];
    for (const variant of variants) {
      const local = `${workDir}/level-${level}-${variant.name}`;
      await Bun.write(local, variant.bytes);
      const key = `paintings/defaults/level-${level}/${variant.name}`;
      const put = Bun.spawnSync([
        "wrangler", "r2", "object", "put", `${BUCKET}/${key}`,
        "--file", local, "--content-type", variant.contentType, "--remote",
      ]);
      if (put.exitCode !== 0) {
        console.error(`upload failed for ${key}:\n${put.stderr.toString()}`);
        process.exit(1);
      }
      console.log(
        `level ${level} ${variant.name}: ${(variant.bytes.byteLength / 1024).toFixed(0)}KB → r2:${key}`,
      );
    }
  }
}
