import { spawn } from "node:child_process";
import path from "node:path";
import type { Clip } from "../shared";

const W = 1280;
const H = 720;
const FPS = 30;

/** Chain atempo filters to reach speeds outside a single filter's 0.5–2 range. */
function atempoChain(speed: number): string {
  // We clamp speed to 0.5–2 upstream, so a single atempo is enough.
  return `atempo=${speed}`;
}

function videoFilter(clip: Clip, i: number): string {
  const dur = (clip.outPoint - clip.inPoint) / clip.speed;
  const parts = [
    `[${i}:v]trim=start=${clip.inPoint}:end=${clip.outPoint}`,
    `setpts=(PTS-STARTPTS)/${clip.speed}`,
    `scale=${W}:${H}:force_original_aspect_ratio=decrease`,
    `pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2`,
    `fps=${FPS}`,
    `format=yuv420p`,
  ];
  if (clip.filter === "bw") parts.push("hue=s=0");
  if (clip.filter === "sepia")
    parts.push("colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131");
  if (clip.filter === "vivid") parts.push("eq=saturation=1.5:contrast=1.1");
  if (clip.fadeIn > 0) parts.push(`fade=t=in:st=0:d=${clip.fadeIn}`);
  if (clip.fadeOut > 0)
    parts.push(`fade=t=out:st=${Math.max(0, dur - clip.fadeOut)}:d=${clip.fadeOut}`);
  return parts.join(",") + `[v${i}]`;
}

function audioFilter(clip: Clip, i: number): string {
  const dur = (clip.outPoint - clip.inPoint) / clip.speed;
  const parts = [
    `[${i}:a]atrim=start=${clip.inPoint}:end=${clip.outPoint}`,
    `asetpts=PTS-STARTPTS`,
    atempoChain(clip.speed),
    // Normalize so concat doesn't choke on mismatched layouts/rates.
    `aformat=sample_rates=44100:channel_layouts=stereo`,
  ];
  if (clip.fadeIn > 0) parts.push(`afade=t=in:st=0:d=${clip.fadeIn}`);
  if (clip.fadeOut > 0)
    parts.push(`afade=t=out:st=${Math.max(0, dur - clip.fadeOut)}:d=${clip.fadeOut}`);
  return parts.join(",") + `[a${i}]`;
}

export async function renderTimeline(
  clips: Clip[],
  mediaPaths: Map<string, string>,
  outDir: string,
): Promise<string> {
  if (clips.length === 0) throw new Error("Timeline is empty");
  const inputs: string[] = [];
  for (const clip of clips) {
    const p = mediaPaths.get(clip.mediaId);
    if (!p) throw new Error(`Unknown media id: ${clip.mediaId}`);
    inputs.push("-i", p);
  }

  const filters = [
    ...clips.map((c, i) => videoFilter(c, i)),
    ...clips.map((c, i) => audioFilter(c, i)),
    clips.map((_, i) => `[v${i}][a${i}]`).join("") +
      `concat=n=${clips.length}:v=1:a=1[outv][outa]`,
  ].join(";");

  const outPath = path.join(outDir, `anky-cut-${Date.now()}.mp4`);
  const args = [
    ...inputs,
    "-filter_complex",
    filters,
    "-map",
    "[outv]",
    "-map",
    "[outa]",
    "-c:v",
    "libx264",
    "-preset",
    "veryfast",
    "-crf",
    "22",
    "-c:a",
    "aac",
    "-movflags",
    "+faststart",
    "-y",
    outPath,
  ];

  await new Promise<void>((resolve, reject) => {
    const proc = spawn("ffmpeg", args, { stdio: ["ignore", "ignore", "pipe"] });
    let stderr = "";
    proc.stderr.on("data", (d) => (stderr += d.toString()));
    proc.on("error", reject);
    proc.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`ffmpeg exited ${code}:\n${stderr.slice(-2000)}`));
    });
  });

  return outPath;
}
