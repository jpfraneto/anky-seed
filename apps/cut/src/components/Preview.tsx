import { useCallback, useEffect, useRef, useState } from "react";
import type { Clip } from "../../shared";

const CSS_FILTERS: Record<Clip["filter"], string> = {
  none: "none",
  bw: "grayscale(1)",
  sepia: "sepia(0.8)",
  vivid: "saturate(1.5) contrast(1.1)",
};

/**
 * Plays the timeline clip-by-clip. This is an approximation of the real
 * render: trims via seek + timeupdate, speed via playbackRate, filters via
 * CSS. The ffmpeg export is the source of truth.
 */
export function Preview({ clips, urls }: { clips: Clip[]; urls: Map<string, string> }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(false);

  const clip = clips[index] ?? clips[0];

  const startClip = useCallback(
    (i: number) => {
      const v = videoRef.current;
      const c = clips[i];
      if (!v || !c) return;
      setIndex(i);
      const src = urls.get(c.mediaId);
      if (src && v.src !== src) v.src = src;
      v.currentTime = c.inPoint;
      v.playbackRate = c.speed;
      v.play();
    },
    [clips, urls],
  );

  const play = useCallback(() => {
    setPlaying(true);
    startClip(index < clips.length ? index : 0);
  }, [index, clips.length, startClip]);

  const stop = useCallback(() => {
    setPlaying(false);
    videoRef.current?.pause();
  }, []);

  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    const onTime = () => {
      const c = clips[index];
      if (!c || !playing) return;
      if (v.currentTime >= c.outPoint || v.ended) {
        if (index + 1 < clips.length) startClip(index + 1);
        else {
          setPlaying(false);
          v.pause();
          setIndex(0);
        }
      }
    };
    v.addEventListener("timeupdate", onTime);
    v.addEventListener("ended", onTime);
    return () => {
      v.removeEventListener("timeupdate", onTime);
      v.removeEventListener("ended", onTime);
    };
  }, [clips, index, playing, startClip]);

  // Keep the visible frame in sync when the selection/list changes while paused.
  useEffect(() => {
    const v = videoRef.current;
    const c = clips[index] ?? clips[0];
    if (!v || !c || playing) return;
    const src = urls.get(c.mediaId);
    if (src && v.src !== src) {
      v.src = src;
      v.currentTime = c.inPoint;
    }
  }, [clips, index, playing, urls]);

  return (
    <>
      <div className="preview">
        {clip ? (
          <video ref={videoRef} style={{ filter: CSS_FILTERS[clip.filter] }} playsInline />
        ) : (
          <span className="empty">no clips yet</span>
        )}
      </div>
      <div className="transport">
        <button onClick={playing ? stop : play} disabled={clips.length === 0}>
          {playing ? "◼ Stop" : "▶ Play"}
        </button>
        <span className="dim">
          {clips.length > 0 && `clip ${Math.min(index + 1, clips.length)} / ${clips.length}`}
          {" · preview approximates fades/filters — export for the real thing"}
        </span>
      </div>
    </>
  );
}
