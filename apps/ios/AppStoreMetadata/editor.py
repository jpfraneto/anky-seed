#!/usr/bin/env python3
"""A local page for editing the App Store listing copy in this folder.

    ./editor.py        # serves http://127.0.0.1:4747 and opens it

Every field is one of the .txt files next to this script; the page saves to
them as you type. Nothing leaves the machine.
"""
import json
import os
import sys
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = 4747
LOCALES = ["en-US", "es-MX", "fr-FR", "de-DE", "hi", "zh-Hans"]
# field -> (label, limit, rows, where it shows)
FIELDS = {
    "name": ("Name", 30, 1, "The app's name on the store."),
    "subtitle": ("Subtitle", 30, 1, "The line under the name."),
    "promotional_text": ("Promotional text", 170, 3, "Above the description. Can change without a new build."),
    "keywords": ("Keywords", 100, 2, "Comma-separated, no spaces after commas. Never shown; used for search."),
    "description": ("Description", 4000, 26, "The full store description."),
    "release_notes": ("What's new", 4000, 10, "Shown to people updating to this version."),
}


def path_for(locale, field):
    if locale not in LOCALES or field not in FIELDS:
        return None
    return os.path.join(ROOT, locale, field + ".txt")


def load_all():
    data = {}
    for locale in LOCALES:
        data[locale] = {}
        for field in FIELDS:
            try:
                with open(path_for(locale, field), encoding="utf-8") as handle:
                    data[locale][field] = handle.read().strip("\n")
            except FileNotFoundError:
                data[locale][field] = ""
    return data


PAGE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Anky listing</title>
<style>
  :root { --paper:#f6efe4; --plate:#efe4d7; --ink:#3d374f; --soft:#655e79; --line:rgba(61,55,79,.12); --bad:#b3534d; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--paper); color:var(--ink); font:16px/1.5 Georgia, "Times New Roman", serif; }
  main { max-width: 760px; margin: 0 auto; padding: 40px 20px 120px; }
  h1 { font-weight: normal; font-size: 34px; margin: 0 0 4px; }
  .sub { color: var(--soft); margin: 0 0 28px; font-size: 15px; }
  nav { display:flex; gap:8px; flex-wrap:wrap; position:sticky; top:0; background:var(--paper); padding:12px 0; z-index:2; border-bottom:1px solid var(--line); }
  nav button { font:inherit; font-size:15px; border:1px solid var(--line); background:transparent; color:var(--ink); padding:8px 14px; border-radius:12px; cursor:pointer; }
  nav button[aria-pressed="true"] { background:var(--ink); color:var(--paper); border-color:var(--ink); }
  nav button.over::after { content:" •"; color:var(--bad); }
  nav button[aria-pressed="true"].over::after { color:#f3b6b0; }
  #status { margin-left:auto; align-self:center; color:var(--soft); font-size:14px; }
  section { background:var(--plate); border-radius:18px; padding:16px 18px 18px; margin-top:20px; }
  .head { display:flex; align-items:baseline; gap:12px; }
  label { font-size:19px; }
  .count { margin-left:auto; color:var(--soft); font-size:14px; font-variant-numeric: tabular-nums; }
  .count.over { color:var(--bad); font-weight:bold; }
  .hint { color:var(--soft); font-size:13px; margin:2px 0 10px; }
  textarea { width:100%; font:15px/1.5 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; color:var(--ink); background:var(--paper); border:1px solid var(--line); border-radius:12px; padding:10px 12px; resize:vertical; }
  textarea:focus { outline:2px solid var(--ink); outline-offset:1px; }
  .warn { color:var(--bad); font-size:13px; margin-top:6px; min-height:1em; }
</style>
</head>
<body>
<main>
  <h1>Anky listing</h1>
  <p class="sub">Edits save to <code>AppStoreMetadata/</code> as you type. Nothing is sent to Apple from here.</p>
  <nav id="tabs"></nav>
  <div id="fields"></div>
</main>
<script>
const LOCALES = __LOCALES__, FIELDS = __FIELDS__;
let data = __DATA__, current = LOCALES[0], timers = {};
const count = s => Array.from(s.trim()).length;
const status = () => document.getElementById('status');

function problems(field, value) {
  const out = [], n = count(value), limit = FIELDS[field][1];
  if (!value.trim()) out.push('Empty.');
  if (n > limit) out.push(`${n - limit} over the limit.`);
  if (field === 'keywords') {
    if (value.includes(', ')) out.push('Remove the spaces after commas.');
    const seen = {}, dup = [];
    value.split(',').map(k => k.trim()).forEach(k => { if (seen[k] && !dup.includes(k)) dup.push(k); seen[k] = 1; });
    if (dup.length) out.push('Repeated: ' + dup.join(', ') + '.');
  }
  return out;
}

function renderTabs() {
  const nav = document.getElementById('tabs');
  nav.innerHTML = '';
  LOCALES.forEach(locale => {
    const b = document.createElement('button');
    b.textContent = locale;
    b.setAttribute('aria-pressed', locale === current);
    if (Object.keys(FIELDS).some(f => problems(f, data[locale][f]).length)) b.className = 'over';
    b.onclick = () => { current = locale; render(); };
    nav.appendChild(b);
  });
  const s = document.createElement('span'); s.id = 'status'; s.textContent = 'Saved'; nav.appendChild(s);
}

function render() {
  renderTabs();
  const root = document.getElementById('fields');
  root.innerHTML = '';
  Object.entries(FIELDS).forEach(([field, [label, limit, rows, hint]]) => {
    const sec = document.createElement('section');
    sec.innerHTML = `<div class="head"><label for="${field}">${label}</label><span class="count"></span></div>
      <div class="hint">${hint}</div><textarea id="${field}" rows="${rows}" spellcheck="true"></textarea><div class="warn"></div>`;
    const ta = sec.querySelector('textarea'), c = sec.querySelector('.count'), w = sec.querySelector('.warn');
    ta.value = data[current][field];
    const refresh = () => {
      const n = count(ta.value);
      c.textContent = `${n} / ${limit}`;
      c.classList.toggle('over', n > limit);
      w.textContent = problems(field, ta.value).join(' ');
    };
    ta.oninput = () => {
      data[current][field] = ta.value; refresh();
      status().textContent = 'Saving…';
      const key = current + '/' + field, locale = current;
      clearTimeout(timers[key]);
      timers[key] = setTimeout(() => save(locale, field), 400);
    };
    refresh();
    root.appendChild(sec);
  });
}

async function save(locale, field) {
  try {
    const r = await fetch('/save', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ locale, field, value: data[locale][field] }) });
    if (!r.ok) throw new Error(await r.text());
    status().textContent = 'Saved';
    document.querySelectorAll('#tabs button').forEach((b, i) => {
      const locale = LOCALES[i];
      if (locale) b.classList.toggle('over', Object.keys(FIELDS).some(f => problems(f, data[locale][f]).length));
    });
  } catch (e) { status().textContent = 'Not saved: ' + e.message; }
}
render();
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path != "/":
            self.send_error(404)
            return
        page = (
            PAGE.replace("__LOCALES__", json.dumps(LOCALES))
            .replace("__FIELDS__", json.dumps(FIELDS))
            .replace("__DATA__", json.dumps(load_all()).replace("</", "<\\/"))
        )
        body = page.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        # Only this page, on this machine, may write.
        origin = self.headers.get("Origin", "")
        if self.path != "/save" or origin not in ("http://127.0.0.1:%d" % PORT, "http://localhost:%d" % PORT):
            self.send_error(403)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length))
            target = path_for(payload["locale"], payload["field"])
            value = payload["value"]
            if target is None or not isinstance(value, str) or len(value) > 20000:
                raise ValueError("bad field")
        except (ValueError, KeyError):
            self.send_error(400)
            return
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(value.strip("\n") + "\n")
        self.send_response(204)
        self.end_headers()


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = "http://127.0.0.1:%d" % PORT
    print("Editing the listing at", url)
    if "--no-open" not in sys.argv:
        webbrowser.open(url)
    server.serve_forever()
