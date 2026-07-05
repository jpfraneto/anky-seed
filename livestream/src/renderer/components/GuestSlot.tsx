import type { ShowState } from "../../state/showState";
import { MediaSlot } from "./MediaSlot";

export function GuestSlot({ guest }: { guest: ShowState["guest"] }) {
  return (
    <article className="guest-card">
      <div className="panel-frame" />
      <MediaSlot kind={guest.kind} src={guest.src} label={guest.title} />
      <div className="slot-name">{guest.title}</div>
    </article>
  );
}
