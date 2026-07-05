import type { ShowState } from "../../state/showState";
import { MediaSlot } from "./MediaSlot";

export function CenterSlot({
  media,
  caption,
}: {
  media: ShowState["center"];
  caption: ShowState["caption"];
}) {
  return (
    <article className="center-card">
      <div className="panel-frame" />
      <MediaSlot kind={media.kind} src={media.src} label={media.caption} />
      {caption.text ? (
        <div className="live-caption-flow">
          <span>{caption.speaker ?? "live"}</span>
          <p>{caption.text}</p>
        </div>
      ) : null}
      <div className="media-caption">{media.caption}</div>
    </article>
  );
}
