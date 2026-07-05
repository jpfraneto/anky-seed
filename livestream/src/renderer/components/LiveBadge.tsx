export function LiveBadge({ live, connected }: { live: boolean; connected: boolean }) {
  return (
    <div className={`live-badge ${live ? "is-live" : ""}`}>
      <span className="live-dot" />
      <span>{live ? "LIVE" : "STANDBY"}</span>
      <span className={`signal-dot ${connected ? "connected" : ""}`} />
    </div>
  );
}
