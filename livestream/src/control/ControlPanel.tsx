import { FormEvent, useMemo, useState } from "react";
import { stateApi } from "../state/stateClient";
import { useShowState } from "../state/useShowState";
import type { DeepPartial, ShowState } from "../state/showState";

export function ControlPanel() {
  const { state, connected } = useShowState();
  const [customPatch, setCustomPatch] = useState("");
  const [status, setStatus] = useState("Ready");

  const tickerJson = useMemo(() => JSON.stringify(state.ticker, null, 2), [state.ticker]);

  async function patch(nextPatch: DeepPartial<ShowState>) {
    setStatus("Sending");
    const response = await fetch(stateApi.patchUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(nextPatch),
    });

    setStatus(response.ok ? "Applied" : "Failed");
  }

  async function reset() {
    setStatus("Resetting");
    const response = await fetch(`${stateApi.origin}/reset`, { method: "POST" });
    setStatus(response.ok ? "Reset" : "Failed");
  }

  async function submitCustomPatch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    try {
      await patch(JSON.parse(customPatch) as DeepPartial<ShowState>);
    } catch {
      setStatus("Invalid JSON");
    }
  }

  return (
    <main className="control-page">
      <header className="control-header">
        <div>
          <p className="eyebrow">Today Anky Becomes</p>
          <h1>Broadcast Control</h1>
        </div>
        <div className="control-status">
          <span className={connected ? "online" : ""} />
          {connected ? "Connected" : "Offline"} / {status}
        </div>
      </header>

      <section className="control-grid">
        <form
          className="control-panel"
          onSubmit={(event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            patch({
              live: form.get("live") === "on",
              host: {
                name: String(form.get("hostName")),
                source: form.get("hostSource") as ShowState["host"]["source"],
                src: String(form.get("hostSrc")),
              },
            });
          }}
        >
          <h2>Signal</h2>
          <label className="toggle-row">
            <input name="live" type="checkbox" defaultChecked={state.live} />
            <span>Live</span>
          </label>
          <label>
            Host name
            <input name="hostName" defaultValue={state.host.name} />
          </label>
          <label>
            Host source
            <select name="hostSource" defaultValue={state.host.source}>
              <option value="obs">OBS transparent slot</option>
              <option value="camera">Browser camera</option>
              <option value="video">Video URL</option>
            </select>
          </label>
          <label>
            Host video URL
            <input name="hostSrc" defaultValue={state.host.src ?? ""} />
          </label>
          <button type="submit">Apply Signal</button>
        </form>

        <form
          className="control-panel"
          onSubmit={(event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            patch({
              center: {
                kind: form.get("centerKind") as ShowState["center"]["kind"],
                src: String(form.get("centerSrc")),
                caption: String(form.get("centerCaption")),
              },
              guest: {
                kind: form.get("guestKind") as ShowState["guest"]["kind"],
                src: String(form.get("guestSrc")),
                title: String(form.get("guestTitle")),
              },
            });
          }}
        >
          <h2>Surfaces</h2>
          <label>
            Center kind
            <select name="centerKind" defaultValue={state.center.kind}>
              <option value="image">Image</option>
              <option value="video">Video</option>
            </select>
          </label>
          <label>
            Center source
            <input name="centerSrc" defaultValue={state.center.src} />
          </label>
          <label>
            Center caption
            <input name="centerCaption" defaultValue={state.center.caption} />
          </label>
          <label>
            Guest kind
            <select name="guestKind" defaultValue={state.guest.kind}>
              <option value="image">Image</option>
              <option value="video">Video</option>
            </select>
          </label>
          <label>
            Guest source
            <input name="guestSrc" defaultValue={state.guest.src} />
          </label>
          <label>
            Guest title
            <input name="guestTitle" defaultValue={state.guest.title} />
          </label>
          <button type="submit">Apply Surfaces</button>
        </form>

        <form
          className="control-panel"
          onSubmit={(event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            patch({
              lowerThird: {
                showLogo: form.get("showLogo") === "on",
                headline: {
                  before: String(form.get("headlineBefore")),
                  highlight: String(form.get("headlineHighlight")),
                  after: String(form.get("headlineAfter")),
                },
                quote: {
                  speaker: String(form.get("quoteSpeaker")),
                  text: String(form.get("quoteText")),
                },
                cta: String(form.get("cta")),
              },
            });
          }}
        >
          <h2>Lower Third</h2>
          <label className="toggle-row">
            <input name="showLogo" type="checkbox" defaultChecked={state.lowerThird.showLogo} />
            <span>Logo</span>
          </label>
          <label>
            Headline before
            <input name="headlineBefore" defaultValue={state.lowerThird.headline.before} />
          </label>
          <label>
            Headline highlight
            <input name="headlineHighlight" defaultValue={state.lowerThird.headline.highlight} />
          </label>
          <label>
            Headline after
            <input name="headlineAfter" defaultValue={state.lowerThird.headline.after} />
          </label>
          <label>
            Speaker
            <input name="quoteSpeaker" defaultValue={state.lowerThird.quote.speaker} />
          </label>
          <label>
            Quote
            <textarea name="quoteText" defaultValue={state.lowerThird.quote.text} />
          </label>
          <label>
            CTA
            <input name="cta" defaultValue={state.lowerThird.cta} />
          </label>
          <button type="submit">Apply Caption</button>
        </form>

        <form
          className="control-panel"
          onSubmit={(event) => {
            event.preventDefault();
            const form = new FormData(event.currentTarget);
            try {
              patch({ ticker: JSON.parse(String(form.get("ticker"))) });
            } catch {
              setStatus("Invalid ticker JSON");
            }
          }}
        >
          <h2>Ticker</h2>
          <label>
            Items JSON
            <textarea name="ticker" className="json-input" defaultValue={tickerJson} />
          </label>
          <button type="submit">Apply Ticker</button>
        </form>

        <form className="control-panel custom-patch" onSubmit={submitCustomPatch}>
          <h2>JSON Patch</h2>
          <textarea
            className="json-input"
            value={customPatch}
            onChange={(event) => setCustomPatch(event.target.value)}
            placeholder='{"guest":{"title":"Anky as Satoshi"}}'
          />
          <div className="button-row">
            <button type="submit">Send Patch</button>
            <button type="button" className="secondary-button" onClick={reset}>
              Reset
            </button>
          </div>
        </form>
      </section>
    </main>
  );
}
