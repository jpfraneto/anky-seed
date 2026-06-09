#!/usr/bin/env bun
import { readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { privateCasesDir, runsRoot } from "./evalLib";

type LabAnky = {
  id: string;
  language: string;
  risk: string;
  summary: string;
  shouldNotice: string[];
  text: string;
};

const runDir = join(runsRoot, "2026-06-07T11-46-56-577Z");
const outPath = join(runDir, "OPENROUTER_PROMPT_LAB.html");
const ankys = await loadPrivateAnkys();

const defaultPrompt = `Take a look at this stream-of-consciousness journal entry.

Respond with deep insight that feels personal, casual, and alive, not clinical. Be a sharp mirror: part close friend, part mentor, part pattern-recognizer.

Help the writer see the emotional undercurrents, hidden loops, deeper meaning, contradictions, longings, and connections they might be missing.

Comfort what is real. Validate without flattering. Challenge gently where needed. Reframe the surface topic into what the writer may really be seeking underneath.

Do not force introspection for its own sake. Help the writer recognize something true about who they are and move toward a more honest, positive loop in life.

Use vivid metaphors and powerful imagery when they reveal something real. Don't diagnose, don't sound like therapy, and don't give generic advice.

Write in the same language and vibe as the entry.

Reply with pure markdown, and use headings for different sections. At the top of the reply add a max 4 word title.`;

await writeFile(outPath, html({ ankys, defaultPrompt }));
console.log(JSON.stringify({ status: "ok", outPath, ankys: ankys.length, keyEmbedded: false }, null, 2));

async function loadPrivateAnkys(): Promise<LabAnky[]> {
  const files = (await readdir(privateCasesDir)).filter((file) => file.endsWith(".case.json")).sort();
  const items: LabAnky[] = [];
  for (const file of files) {
    const metadata = JSON.parse(await readFile(join(privateCasesDir, file), "utf8")) as {
      id: string;
      expectedLanguage: string;
      riskLevel: string;
      summary: string;
      shouldNotice?: string[];
    };
    const text = await readFile(join(privateCasesDir, file.replace(/\.case\.json$/, ".input.txt")), "utf8");
    items.push({
      id: metadata.id,
      language: metadata.expectedLanguage,
      risk: metadata.riskLevel,
      summary: metadata.summary,
      shouldNotice: metadata.shouldNotice ?? [],
      text,
    });
  }
  return items;
}

function html(input: { ankys: LabAnky[]; defaultPrompt: string }): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Anky OpenRouter Prompt Lab</title>
  <style>
    :root { color-scheme: light; --bg: #f6f5f2; --panel: #fff; --ink: #181817; --muted: #6b6861; --line: #d8d3c9; --accent: #146b5d; --danger: #b84a2f; --code: #f0eee8; }
    * { box-sizing: border-box; }
    body { margin: 0; font: 14px/1.45 ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--ink); }
    button, input, textarea, select { font: inherit; }
    button { border: 1px solid var(--ink); background: var(--ink); color: white; height: 36px; padding: 0 12px; border-radius: 6px; cursor: pointer; }
    button.secondary { background: white; color: var(--ink); border-color: var(--line); }
    button:disabled { opacity: .55; cursor: not-allowed; }
    .app { height: 100vh; display: grid; grid-template-columns: 280px minmax(360px, 520px) minmax(420px, 1fr); gap: 1px; background: var(--line); }
    aside, main, section { background: var(--panel); min-height: 0; }
    aside { display: flex; flex-direction: column; }
    .pane-head { padding: 14px; border-bottom: 1px solid var(--line); display: grid; gap: 10px; }
    h1 { font-size: 18px; margin: 0; letter-spacing: 0; }
    .hint, .status { color: var(--muted); font-size: 12px; }
    .search, input, select, textarea { width: 100%; border: 1px solid var(--line); border-radius: 6px; padding: 9px 10px; background: white; color: var(--ink); }
    .anky-list { overflow: auto; padding: 8px; display: grid; gap: 8px; }
    .anky-card { text-align: left; width: 100%; height: auto; border: 1px solid var(--line); background: white; color: var(--ink); padding: 10px; border-radius: 7px; display: grid; gap: 6px; }
    .anky-card.active { border-color: var(--accent); box-shadow: inset 0 0 0 1px var(--accent); }
    .meta { display: flex; gap: 6px; flex-wrap: wrap; }
    .pill { font-size: 11px; color: var(--muted); background: #f3f1ec; border: 1px solid var(--line); border-radius: 999px; padding: 2px 7px; }
    main { display: grid; grid-template-rows: auto 1fr; min-width: 0; }
    .controls { padding: 14px; border-bottom: 1px solid var(--line); display: grid; gap: 10px; }
    .row { display: grid; gap: 8px; }
    .two { grid-template-columns: 1fr 1fr; }
    label { font-weight: 650; font-size: 12px; color: var(--muted); }
    textarea { resize: none; min-height: 0; line-height: 1.42; }
    .editors { min-height: 0; display: grid; grid-template-rows: 1fr 1fr; gap: 1px; background: var(--line); }
    .editor-wrap { min-height: 0; display: grid; grid-template-rows: auto 1fr; background: white; }
    .editor-label { padding: 8px 12px; border-bottom: 1px solid var(--line); display: flex; align-items: center; justify-content: space-between; }
    .editor-wrap textarea { border: 0; border-radius: 0; height: 100%; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 12px; }
    .output-pane { min-width: 0; display: grid; grid-template-rows: auto 1fr; }
    .output-head { padding: 14px; border-bottom: 1px solid var(--line); display: flex; align-items: center; justify-content: space-between; gap: 10px; }
    .rendered { overflow: auto; padding: 24px; max-width: 860px; width: 100%; }
    .rendered h1 { font-size: 28px; margin: 0 0 14px; }
    .rendered h2 { font-size: 18px; margin: 24px 0 8px; border-top: 1px solid var(--line); padding-top: 18px; }
    .rendered h3 { font-size: 15px; margin: 18px 0 6px; }
    .rendered p { margin: 0 0 12px; }
    .rendered code { background: var(--code); padding: 1px 4px; border-radius: 4px; }
    .rendered pre { background: var(--code); padding: 12px; border-radius: 6px; overflow: auto; }
    .rendered blockquote { margin: 0 0 12px; padding-left: 12px; border-left: 3px solid var(--accent); color: #373530; }
    .error { color: var(--danger); }
    @media (max-width: 980px) { .app { height: auto; min-height: 100vh; grid-template-columns: 1fr; } aside { max-height: 300px; } main { min-height: 720px; } .output-pane { min-height: 560px; } }
  </style>
</head>
<body>
  <div class="app">
    <aside>
      <div class="pane-head">
        <div>
          <h1>Anky Prompt Lab</h1>
          <div class="hint">Raw local HTML. Paste the API key at runtime; it is not stored in this file.</div>
        </div>
        <input id="filter" class="search" placeholder="Filter ankys" />
      </div>
      <div id="ankyList" class="anky-list"></div>
    </aside>
    <main>
      <div class="controls">
        <div class="row">
          <label for="apiKey">OpenRouter API key</label>
          <input id="apiKey" type="text" autocomplete="off" spellcheck="false" placeholder="Paste key for this browser session" />
        </div>
        <div class="row">
          <label for="model">OpenRouter model</label>
          <input id="model" value="anthropic/claude-sonnet-4.6" placeholder="provider/model" />
        </div>
        <div class="row two">
          <button id="runBtn">Run Reflection</button>
          <button id="copyBtn" class="secondary">Copy Output</button>
        </div>
        <div id="status" class="status">Ready.</div>
      </div>
      <div class="editors">
        <div class="editor-wrap">
          <div class="editor-label"><label for="prompt">Prompt</label><span class="hint">The writing is appended below this prompt.</span></div>
          <textarea id="prompt"></textarea>
        </div>
        <div class="editor-wrap">
          <div class="editor-label"><label for="journal">Selected stream of consciousness</label><span id="selectedId" class="hint"></span></div>
          <textarea id="journal"></textarea>
        </div>
      </div>
    </main>
    <section class="output-pane">
      <div class="output-head"><strong>Rendered Output</strong><span id="cost" class="status"></span></div>
      <div id="output" class="rendered"><p class="hint">Run a model to render the reflection here.</p></div>
    </section>
  </div>
  <script>
    const ANKYS = ${JSON.stringify(input.ankys)};
    const DEFAULT_PROMPT = ${JSON.stringify(input.defaultPrompt)};
    let selected = ANKYS[0];
    let lastMarkdown = "";
    const els = {
      list: document.getElementById("ankyList"),
      filter: document.getElementById("filter"),
      apiKey: document.getElementById("apiKey"),
      model: document.getElementById("model"),
      prompt: document.getElementById("prompt"),
      journal: document.getElementById("journal"),
      selectedId: document.getElementById("selectedId"),
      runBtn: document.getElementById("runBtn"),
      copyBtn: document.getElementById("copyBtn"),
      output: document.getElementById("output"),
      status: document.getElementById("status"),
      cost: document.getElementById("cost"),
    };
    els.prompt.value = DEFAULT_PROMPT;
    selectAnky(selected.id);
    renderList();
    els.filter.addEventListener("input", renderList);
    els.runBtn.addEventListener("click", runReflection);
    els.copyBtn.addEventListener("click", async () => {
      if (!lastMarkdown) return;
      await navigator.clipboard.writeText(lastMarkdown);
      setStatus("Copied output markdown.");
    });
    function renderList() {
      const query = els.filter.value.trim().toLowerCase();
      els.list.innerHTML = "";
      for (const item of ANKYS) {
        const haystack = [item.id, item.language, item.risk, item.summary, item.text].join(" ").toLowerCase();
        if (query && !haystack.includes(query)) continue;
        const button = document.createElement("button");
        button.className = "anky-card" + (item.id === selected?.id ? " active" : "");
        button.innerHTML = '<strong>' + escapeHtml(item.id) + '</strong>'
          + '<div class="meta"><span class="pill">' + escapeHtml(item.language) + '</span><span class="pill">' + escapeHtml(item.risk) + '</span></div>'
          + '<div class="hint">' + escapeHtml(item.text.slice(0, 150).replace(/\\s+/g, " ")) + '</div>';
        button.addEventListener("click", () => selectAnky(item.id));
        els.list.appendChild(button);
      }
    }
    function selectAnky(id) {
      selected = ANKYS.find((item) => item.id === id) || ANKYS[0];
      els.journal.value = selected.text;
      els.selectedId.textContent = selected.id;
      renderList();
    }
    async function runReflection() {
      const apiKey = cleanApiKey(els.apiKey.value);
      if (apiKey !== els.apiKey.value) els.apiKey.value = apiKey;
      const model = els.model.value.trim();
      if (!apiKey) return showError("Paste an OpenRouter key first. It stays in this page session only.");
      const invalidKeyCharacters = nonLatin1Characters(apiKey);
      if (invalidKeyCharacters.length) {
        return showError("The API key contains characters that cannot be sent in an HTTP Authorization header: " + invalidKeyCharacters.join(", ") + ". Paste the raw key again as plain text.");
      }
      const prompt = els.prompt.value.trim();
      const journal = els.journal.value.trim();
      if (!prompt || !journal) return showError("Prompt and journal entry are required.");
      const fullPrompt = prompt + "\\n\\nJournal entry:\\n" + journal;
      const endpoint = "https://openrouter.ai/api/v1/chat/completions";
      els.runBtn.disabled = true;
      els.cost.textContent = "";
      setStatus("Calling OpenRouter directly... key length " + apiKey.length + ".");
      try {
        const started = performance.now();
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 120000);
        const response = await fetch(endpoint, {
          method: "POST",
          headers: {
            Authorization: "Bearer " + apiKey,
            "Content-Type": "application/json",
          },
          signal: controller.signal,
          body: JSON.stringify({
            messages: [{ role: "user", content: fullPrompt }],
            usage: { include: true },
            ...(model ? { model } : {}),
          }),
        });
        clearTimeout(timeout);
        const raw = await response.text();
        if (!response.ok) throw new Error("OpenRouter HTTP " + response.status + ": " + raw.slice(0, 700));
        const json = JSON.parse(raw);
        const content = json.choices?.[0]?.message?.content;
        if (!content) throw new Error("No message content returned.");
        lastMarkdown = content;
        els.output.innerHTML = renderMarkdown(content);
        const seconds = ((performance.now() - started) / 1000).toFixed(1);
        const usage = json.usage || {};
        const cost = usage.cost === undefined ? "" : "cost $" + Number(usage.cost).toFixed(6);
        els.cost.textContent = cost;
        setStatus("Done in " + seconds + "s" + (model ? " with " + model : "") + ".");
      } catch (error) {
        showError(explainFetchError(error));
      } finally {
        els.runBtn.disabled = false;
      }
    }
    function setStatus(text) {
      els.status.className = "status";
      els.status.textContent = text;
    }
    function showError(text) {
      els.status.className = "status error";
      els.status.textContent = text;
      els.output.innerHTML = '<p class="error">' + escapeHtml(text) + '</p>';
    }
    function cleanApiKey(value) {
      return value
        .trim()
        .replace(/^Bearer\\s+/i, "");
    }
    function nonLatin1Characters(value) {
      const output = [];
      for (const char of value) {
        if (char.charCodeAt(0) > 255) output.push("U+" + char.charCodeAt(0).toString(16).toUpperCase().padStart(4, "0"));
      }
      return output;
    }
    function explainFetchError(error) {
      const message = error?.message || String(error);
      if (error?.name === "AbortError") {
        return "Request timed out after 120 seconds. The model may be slow, unavailable, or the prompt may be too large.";
      }
      if (/non ISO-8859-1 code point/i.test(message)) {
        return "The browser refused the request because a header contains a non-Latin-1 character. This usually means the API key paste includes an invisible Unicode character. Paste the raw key again as plain text.";
      }
      if (/Failed to fetch|NetworkError|Load failed/i.test(message)) {
        return "Browser network failure while calling OpenRouter directly. This is usually CORS/preflight, file:// origin restrictions, an extension/privacy block, or connectivity. JavaScript cannot read a response body for this class of failure.";
      }
      return message;
    }
    function renderMarkdown(markdown) {
      const lines = markdown.replace(/\\r\\n/g, "\\n").split("\\n");
      let html = "";
      let paragraph = [];
      let list = [];
      let inCode = false;
      let code = [];
      const flushParagraph = () => {
        if (!paragraph.length) return;
        html += "<p>" + inline(paragraph.join(" ")) + "</p>";
        paragraph = [];
      };
      const flushList = () => {
        if (!list.length) return;
        html += "<ul>" + list.map((item) => "<li>" + inline(item) + "</li>").join("") + "</ul>";
        list = [];
      };
      for (const line of lines) {
        if (/^\x60\x60\x60/.test(line)) {
          if (inCode) {
            html += "<pre><code>" + escapeHtml(code.join("\\n")) + "</code></pre>";
            code = [];
            inCode = false;
          } else {
            flushParagraph(); flushList(); inCode = true;
          }
          continue;
        }
        if (inCode) { code.push(line); continue; }
        if (!line.trim()) { flushParagraph(); flushList(); continue; }
        const heading = line.match(/^(#{1,6})\\s+(.+)$/);
        if (heading) {
          flushParagraph(); flushList();
          const level = Math.min(3, heading[1].length);
          html += "<h" + level + ">" + inline(heading[2]) + "</h" + level + ">";
          continue;
        }
        const bullet = line.match(/^[-*]\\s+(.+)$/);
        if (bullet) { flushParagraph(); list.push(bullet[1]); continue; }
        const quote = line.match(/^>\\s?(.+)$/);
        if (quote) { flushParagraph(); flushList(); html += "<blockquote>" + inline(quote[1]) + "</blockquote>"; continue; }
        paragraph.push(line.trim());
      }
      flushParagraph(); flushList();
      if (inCode) html += "<pre><code>" + escapeHtml(code.join("\\n")) + "</code></pre>";
      return html;
    }
    function inline(value) {
      return escapeHtml(value)
        .replace(/\`([^\`]+)\`/g, "<code>$1</code>")
        .replace(/\\*\\*([^*]+)\\*\\*/g, "<strong>$1</strong>")
        .replace(/\\*([^*]+)\\*/g, "<em>$1</em>");
    }
    function escapeHtml(value) {
      return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char] || char));
    }
  </script>
</body>
</html>`;
}
