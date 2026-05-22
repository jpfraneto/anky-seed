(() => {
  const CLIENT_VERSION = "0.2.0";
  const SKIP_UNTIL_KEY = "anky.browser.skipUntil";

  if (Date.now() < Number(sessionStorage.getItem(SKIP_UNTIL_KEY) || 0)) return;

  if (globalThis.__ankyBrowserClient?.version === CLIENT_VERSION) {
    globalThis.__ankyBrowserClient.activateFromAction();
    return;
  }

  const ACTIVE_CLASS = "anky-x-active";
  const WRITING_MODE_CLASS = "anky-writing-mode";
  const SHELL_ATTR = "data-anky-shell";
  const TEXTBOX_ATTR = "data-anky-textbox";
  const DRAFT_STORAGE_KEY = "anky.browser.activeDraft";
  const LAST_DRAFT_STORAGE_KEY = "anky.browser.lastDraft";
  const STRAIGHT_WRITING_MS = 9000;
  const STRAIGHT_WRITING_IDLE_LIMIT_MS = 1500;

  const state = {
    escaped: false,
    shell: null,
    textbox: null,
    postButton: null,
    startedAt: 0,
    lastAcceptedAt: 0,
    streakStartedAt: 0,
    lines: [],
  };

  function activate() {
    state.escaped = false;
    sessionStorage.removeItem(SKIP_UNTIL_KEY);
    document.documentElement.classList.remove("anky-x-ready");
    document.documentElement.classList.add(ACTIVE_CLASS);
    document.title = "anky";
    ensureShell();
    state.textbox?.focus({ preventScroll: true });
    window.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("beforeinput", onBeforeInput, true);
    window.addEventListener("input", onInput, true);
    window.addEventListener("paste", preventPaste, true);
  }

  function deactivate() {
    state.escaped = true;
    document.documentElement.classList.remove(ACTIVE_CLASS, WRITING_MODE_CLASS);
    state.shell?.remove();
    state.shell = null;
    state.textbox = null;
    state.postButton = null;
    window.removeEventListener("keydown", onKeyDown, true);
    window.removeEventListener("beforeinput", onBeforeInput, true);
    window.removeEventListener("input", onInput, true);
    window.removeEventListener("paste", preventPaste, true);
  }

  function ensureShell() {
    if (state.shell?.isConnected) return;

    const shell = document.createElement("main");
    shell.setAttribute(SHELL_ATTR, "true");
    shell.innerHTML = `
      <section data-anky-composer>
        <div data-anky-row>
          <div data-anky-avatar aria-hidden="true"></div>
          <div>
            <div ${TEXTBOX_ATTR} role="textbox" aria-label="Post text" contenteditable="true" spellcheck="true"></div>
            <div data-anky-actions>
              <button data-anky-post type="button" disabled>Post</button>
            </div>
          </div>
        </div>
      </section>
    `;

    document.body.append(shell);
    state.shell = shell;
    state.textbox = shell.querySelector(`[${TEXTBOX_ATTR}]`);
    state.postButton = shell.querySelector("[data-anky-post]");
    state.postButton.addEventListener("click", postToX);
  }

  function onKeyDown(event) {
    if (event.key !== "Escape") return;
    event.preventDefault();
    event.stopPropagation();
    deactivate();
  }

  function preventPaste(event) {
    if (!isInsideShell(event.target)) return;
    event.preventDefault();
  }

  function onBeforeInput(event) {
    if (state.escaped || !isTextbox(event.target)) return;

    if (event.inputType === "insertParagraph" || event.inputType === "insertLineBreak") {
      event.preventDefault();
      return;
    }

    if (event.inputType && event.inputType.startsWith("delete")) {
      event.preventDefault();
      return;
    }

    if (event.inputType === "insertFromPaste" || event.inputType === "insertReplacementText") {
      event.preventDefault();
      return;
    }

    if (!event.data || !event.inputType || !event.inputType.startsWith("insert")) return;

    const chars = [...event.data].filter((char) => char !== "\n" && char !== "\r" && char !== "\t");
    if (chars.length === 0) {
      event.preventDefault();
      return;
    }

    const now = Date.now();
    for (const char of chars) appendAnkyChar(char, now);
    persistDraft();
  }

  function onInput(event) {
    if (!isTextbox(event.target)) return;
    state.postButton.disabled = getPostText().trim().length === 0;
  }

  function appendAnkyChar(char, now) {
    if (state.lines.length === 0) {
      state.startedAt = now;
      state.streakStartedAt = now;
      state.lines.push(`${now} ${char}`);
    } else {
      const delta = Math.max(0, now - state.lastAcceptedAt);
      const idleMs = now - state.lastAcceptedAt;
      if (idleMs > STRAIGHT_WRITING_IDLE_LIMIT_MS) state.streakStartedAt = now;
      state.lines.push(`${String(delta).padStart(4, "0")} ${char}`);
    }

    state.lastAcceptedAt = now;

    if (now - state.streakStartedAt >= STRAIGHT_WRITING_MS) {
      document.documentElement.classList.add(WRITING_MODE_CLASS);
    }
  }

  function persistDraft() {
    const text = state.lines.join("\n");
    const payload = {
      text,
      reconstructedText: getPostText(),
      updatedAt: Date.now(),
      startedAt: state.startedAt,
      characterCount: state.lines.length,
      host: location.host,
      path: location.pathname,
      isWritingMode: document.documentElement.classList.contains(WRITING_MODE_CLASS),
    };

    if (globalThis.chrome?.storage?.local) {
      chrome.storage.local.set({
        [DRAFT_STORAGE_KEY]: payload,
        [LAST_DRAFT_STORAGE_KEY]: payload,
      });
    } else {
      localStorage.setItem(DRAFT_STORAGE_KEY, JSON.stringify(payload));
      localStorage.setItem(LAST_DRAFT_STORAGE_KEY, JSON.stringify(payload));
    }
  }

  function postToX() {
    const text = getPostText().trim();
    if (!text) return;
    persistDraft();
    sessionStorage.setItem(SKIP_UNTIL_KEY, String(Date.now() + 20000));
    deactivate();
    location.assign(`https://x.com/intent/post?text=${encodeURIComponent(text)}`);
  }

  function getPostText() {
    return state.textbox?.innerText || "";
  }

  function isTextbox(target) {
    return target instanceof Element && target.hasAttribute(TEXTBOX_ATTR);
  }

  function isInsideShell(target) {
    return Boolean(state.shell && target instanceof Node && state.shell.contains(target));
  }

  globalThis.__ankyBrowserClient = {
    version: CLIENT_VERSION,
    activateFromAction: activate,
  };

  activate();
})();
