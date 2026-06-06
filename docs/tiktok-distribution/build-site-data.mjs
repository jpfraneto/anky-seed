import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const csvPath = join(here, "watchlist.csv");
const outPath = join(here, "site", "data.js");

function parseCsv(input) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];
    const next = input[index + 1];

    if (quoted) {
      if (char === '"' && next === '"') {
        field += '"';
        index += 1;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
      continue;
    }

    if (char === '"') quoted = true;
    else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (char !== "\r") {
      field += char;
    }
  }

  if (field.length || row.length) {
    row.push(field);
    rows.push(row);
  }

  return rows;
}

const csv = await readFile(csvPath, "utf8");
const [header, ...rows] = parseCsv(csv);
const entryTypeIndex = header.indexOf("entry_type");

const videos = rows
  .filter((row) => row.length === header.length && row[entryTypeIndex] === "video")
  .map((row) => Object.fromEntries(header.map((key, index) => [key, row[index]])))
  .filter((row) => /^https:\/\/www\.tiktok\.com\/@[^/]+\/video\/\d+$/.test(row.source_url))
  .map((row) => ({
    status: row.status,
    ring: row.ring,
    pillar: row.pillar,
    priority: Number(row.priority),
    source_url: row.source_url,
    search_query: row.search_query,
    creator_handle: row.creator_handle,
    creator_name: row.creator_name,
    visible_hook: row.visible_hook,
    why_it_fits: row.why_it_fits,
    watch_action: row.watch_action,
    comment_direction: row.comment_direction,
    risk_notes: row.risk_notes,
    added_on: row.added_on,
  }));

const uniqueUrls = new Set(videos.map((video) => video.source_url));
if (videos.length !== 888 || uniqueUrls.size !== 888) {
  throw new Error(`Expected 888 unique videos, found ${videos.length} rows and ${uniqueUrls.size} unique URLs.`);
}

const stats = {
  videoCount: videos.length,
  ringCount: new Set(videos.map((video) => video.ring)).size,
  pillarCount: new Set(videos.map((video) => video.pillar)).size,
  sourceCsv: "../watchlist.csv",
  generatedAt: new Date().toISOString(),
};

await writeFile(
  outPath,
  `window.ANKY_TIKTOK_STATS = ${JSON.stringify(stats, null, 2)};\nwindow.ANKY_TIKTOK_VIDEOS = ${JSON.stringify(
    videos,
    null,
    2,
  )};\n`,
);

console.log(`Generated ${outPath} with ${videos.length} videos.`);
