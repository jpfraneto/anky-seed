import { useEffect, useMemo, useState } from "react";
import type { ClockState } from "../../state/showState";

export function Clock({ label, timeZone }: ClockState) {
  const [now, setNow] = useState(new Date());

  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(id);
  }, []);

  const time = useMemo(() => {
    return new Intl.DateTimeFormat("en-US", {
      timeZone,
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    }).format(now);
  }, [now, timeZone]);

  return (
    <div className="clock">
      <div className="clock-label">{label}</div>
      <div className="clock-time">{time}</div>
    </div>
  );
}
