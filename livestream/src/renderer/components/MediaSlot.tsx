import type { MediaKind } from "../../state/showState";

type MediaSlotProps = {
  kind: MediaKind;
  src: string;
  className?: string;
  label?: string;
};

export function MediaSlot({ kind, src, className, label }: MediaSlotProps) {
  return (
    <div className={`media-slot ${className ?? ""}`}>
      {kind === "image" ? (
        <img src={src} alt={label ?? ""} />
      ) : (
        <video src={src} autoPlay muted loop playsInline />
      )}
      <div className="slot-light slot-light-a" />
      <div className="slot-light slot-light-b" />
    </div>
  );
}
