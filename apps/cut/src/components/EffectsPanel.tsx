import type { Clip } from "../../shared";

export function EffectsPanel({
  clip,
  onChange,
}: {
  clip: Clip | null;
  onChange: (id: string, patch: Partial<Clip>) => void;
}) {
  if (!clip) {
    return <div className="effects dim" style={{ paddingBottom: 12 }}>Select a clip to edit it.</div>;
  }
  const set = (patch: Partial<Clip>) => onChange(clip.id, patch);
  return (
    <div className="effects">
      <label>
        Trim in — {clip.inPoint.toFixed(1)}s
        <input
          type="range"
          min={0}
          max={clip.duration}
          step={0.1}
          value={clip.inPoint}
          onChange={(e) => set({ inPoint: Math.min(+e.target.value, clip.outPoint - 0.1) })}
        />
      </label>
      <label>
        Trim out — {clip.outPoint.toFixed(1)}s
        <input
          type="range"
          min={0}
          max={clip.duration}
          step={0.1}
          value={clip.outPoint}
          onChange={(e) => set({ outPoint: Math.max(+e.target.value, clip.inPoint + 0.1) })}
        />
      </label>
      <label>
        Speed — {clip.speed.toFixed(2)}x
        <input
          type="range"
          min={0.5}
          max={2}
          step={0.05}
          value={clip.speed}
          onChange={(e) => set({ speed: +e.target.value })}
        />
      </label>
      <label>
        Fade in (s)
        <input
          type="number"
          min={0}
          max={5}
          step={0.5}
          value={clip.fadeIn}
          onChange={(e) => set({ fadeIn: +e.target.value })}
        />
      </label>
      <label>
        Fade out (s)
        <input
          type="number"
          min={0}
          max={5}
          step={0.5}
          value={clip.fadeOut}
          onChange={(e) => set({ fadeOut: +e.target.value })}
        />
      </label>
      <label>
        Filter
        <select value={clip.filter} onChange={(e) => set({ filter: e.target.value as Clip["filter"] })}>
          <option value="none">none</option>
          <option value="bw">black & white</option>
          <option value="sepia">sepia</option>
          <option value="vivid">vivid</option>
        </select>
      </label>
    </div>
  );
}
