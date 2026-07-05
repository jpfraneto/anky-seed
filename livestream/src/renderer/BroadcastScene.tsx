import { BackgroundChrome } from "./components/BackgroundChrome";
import { CenterSlot } from "./components/CenterSlot";
import { Clock } from "./components/Clock";
import { GuestSlot } from "./components/GuestSlot";
import { HostSlot } from "./components/HostSlot";
import { LiveBadge } from "./components/LiveBadge";
import { LowerThird } from "./components/LowerThird";
import { Ticker } from "./components/Ticker";
import { useShowState } from "../state/useShowState";

export function BroadcastScene() {
  const { state, connected } = useShowState();

  return (
    <main className="broadcast-scene" aria-label="Today Anky Becomes broadcast overlay">
      <BackgroundChrome />

      <header className="top-bar">
        <Clock {...state.clocks.left} />
        <LiveBadge live={state.live} connected={connected} />
        <Clock {...state.clocks.right} />
      </header>

      <section className="main-grid" aria-label="Media slots">
        <HostSlot host={state.host} />
        <CenterSlot media={state.center} caption={state.caption} />
        <GuestSlot guest={state.guest} />
      </section>

      <LowerThird data={state.lowerThird} />
      <Ticker items={state.ticker} />
    </main>
  );
}
