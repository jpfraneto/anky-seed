import { useEffect, useRef, useState } from "react";
import type { ChatMessage, EditOp, Mask, Timeline } from "../../shared";

interface AnkyMsg extends ChatMessage {
  opsApplied?: number;
}

export function AnkyPanel({
  timeline,
  onOps,
}: {
  timeline: Timeline;
  onOps: (ops: EditOp[]) => void;
}) {
  const [masks, setMasks] = useState<Mask[]>([]);
  const [maskId, setMaskId] = useState("opus-4.8");
  const [messages, setMessages] = useState<AnkyMsg[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const chatRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetch("/api/masks")
      .then((r) => r.json())
      .then(setMasks)
      .catch(() => {});
  }, []);

  useEffect(() => {
    chatRef.current?.scrollTo({ top: chatRef.current.scrollHeight });
  }, [messages]);

  const send = async () => {
    const text = input.trim();
    if (!text || busy) return;
    setInput("");
    const history: ChatMessage[] = [...messages.map(({ role, text }) => ({ role, text })), { role: "user", text }];
    setMessages((m) => [...m, { role: "user", text }]);
    setBusy(true);
    try {
      const res = await fetch("/api/anky/chat", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ maskId, messages: history, timeline }),
      });
      const data = await res.json();
      if (data.error) {
        setMessages((m) => [...m, { role: "assistant", text: `⚠ ${data.error}` }]);
      } else {
        if (data.ops?.length) onOps(data.ops);
        setMessages((m) => [
          ...m,
          { role: "assistant", text: data.text, opsApplied: data.ops?.length || 0 },
        ]);
      }
    } catch (err) {
      setMessages((m) => [...m, { role: "assistant", text: `⚠ ${String(err)}` }]);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="anky">
      <h2>Anky</h2>
      <div className="anky-head">
        <span className="dim">mask</span>
        <select value={maskId} onChange={(e) => setMaskId(e.target.value)}>
          {masks.map((m) => (
            <option key={m.id} value={m.id} disabled={!m.available}>
              {m.label}
              {!m.available ? ` (${m.note ?? "soon"})` : ""}
            </option>
          ))}
        </select>
      </div>
      <div className="chat" ref={chatRef}>
        {messages.length === 0 && (
          <span className="dim">
            Talk to Anky about your cut — “trim the first 3 seconds”, “make clip 2 black and
            white”, “speed everything up”.
          </span>
        )}
        {messages.map((m, i) => (
          <div key={i} className={"msg " + (m.role === "user" ? "user" : "anky")}>
            {m.text}
            {m.opsApplied ? <div className="ops">✦ {m.opsApplied} edit{m.opsApplied > 1 ? "s" : ""} applied</div> : null}
          </div>
        ))}
        {busy && <div className="msg anky dim">…</div>}
      </div>
      <div className="composer">
        <input
          value={input}
          placeholder="talk to anky"
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && send()}
        />
        <button onClick={send} disabled={busy}>
          send
        </button>
      </div>
    </div>
  );
}
