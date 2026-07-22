import { useCallback, useRef, useState } from "react";
import { applyOps, type Clip, type EditOp, type Timeline } from "../shared";
import { AnkyPanel } from "./components/AnkyPanel";
import { EffectsPanel } from "./components/EffectsPanel";
import { Preview } from "./components/Preview";

let clipCounter = 0;

export function App() {
  const [timeline, setTimeline] = useState<Timeline>({ clips: [] });
  const [selectedId, setSelectedId] = useState<string | null>(null);
  // Local object URLs for preview, keyed by mediaId.
  const urlsRef = useRef(new Map<string, string>());
  const [rendering, setRendering] = useState(false);
  const [renderUrl, setRenderUrl] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  const importFiles = useCallback(async (files: FileList) => {
    for (const file of Array.from(files)) {
      const form = new FormData();
      form.append("file", file);
      const res = await fetch("/api/upload", { method: "POST", body: form });
      if (!res.ok) continue;
      const { mediaId, duration } = (await res.json()) as { mediaId: string; duration: number };
      urlsRef.current.set(mediaId, URL.createObjectURL(file));
      const clip: Clip = {
        id: `clip-${++clipCounter}`,
        mediaId,
        name: file.name,
        duration,
        inPoint: 0,
        outPoint: duration,
        speed: 1,
        fadeIn: 0,
        fadeOut: 0,
        filter: "none",
      };
      setTimeline((t) => ({ clips: [...t.clips, clip] }));
      setSelectedId(clip.id);
    }
  }, []);

  const updateClip = useCallback((id: string, patch: Partial<Clip>) => {
    setTimeline((t) => ({
      clips: t.clips.map((c) => (c.id === id ? { ...c, ...patch } : c)),
    }));
  }, []);

  const handleOps = useCallback((ops: EditOp[]) => {
    if (ops.length) setTimeline((t) => applyOps(t, ops));
  }, []);

  const render = useCallback(async () => {
    setRendering(true);
    setRenderUrl(null);
    try {
      const res = await fetch("/api/render", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ clips: timeline.clips }),
      });
      const data = await res.json();
      if (data.url) setRenderUrl(data.url);
      else alert(data.error ?? "render failed");
    } finally {
      setRendering(false);
    }
  }, [timeline]);

  const selected = timeline.clips.find((c) => c.id === selectedId) ?? null;

  return (
    <div className="app">
      <div className="stage">
        <Preview clips={timeline.clips} urls={urlsRef.current} />
        <div className="transport">
          <button onClick={() => fileInput.current?.click()}>+ Add clips</button>
          <input
            ref={fileInput}
            type="file"
            accept="video/*"
            multiple
            hidden
            onChange={(e) => e.target.files && importFiles(e.target.files)}
          />
          <button
            className="primary"
            disabled={rendering || timeline.clips.length === 0}
            onClick={render}
          >
            {rendering ? "Rendering…" : "Export MP4"}
          </button>
          {renderUrl && (
            <a href={renderUrl} download style={{ color: "var(--accent)" }}>
              download render
            </a>
          )}
        </div>
      </div>

      <div className="side">
        <h2>Clip</h2>
        <EffectsPanel clip={selected} onChange={updateClip} />
        <AnkyPanel timeline={timeline} onOps={handleOps} />
      </div>

      <div className="timeline">
        <div className="clips">
          {timeline.clips.length === 0 && (
            <span className="dim">Add clips to start stitching.</span>
          )}
          {timeline.clips.map((clip, i) => (
            <div
              key={clip.id}
              className={"clip" + (clip.id === selectedId ? " selected" : "")}
              onClick={() => setSelectedId(clip.id)}
            >
              <div className="name">{i + 1}. {clip.name}</div>
              <div className="meta">
                {(clip.outPoint - clip.inPoint).toFixed(1)}s
                {clip.speed !== 1 && ` · ${clip.speed}x`}
                {clip.filter !== "none" && ` · ${clip.filter}`}
              </div>
              <div className="meta">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleOps([{ op: "move", clipIndex: i, toIndex: i - 1 }]);
                  }}
                  disabled={i === 0}
                >
                  ←
                </button>{" "}
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleOps([{ op: "move", clipIndex: i, toIndex: i + 1 }]);
                  }}
                  disabled={i === timeline.clips.length - 1}
                >
                  →
                </button>{" "}
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleOps([{ op: "remove", clipIndex: i }]);
                  }}
                >
                  ✕
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
