const systemPrompt = document.querySelector("#systemPrompt");
const userPrompt = document.querySelector("#userPrompt");
const model = document.querySelector("#model");
const streamToggle = document.querySelector("#streamToggle");
const runButton = document.querySelector("#runButton");
const clearButton = document.querySelector("#clearButton");
const outputText = document.querySelector("#outputText");
const status = document.querySelector("#status");

let streaming = true;

function setStatus(message, isError = false) {
  status.textContent = message;
  status.classList.toggle("is-error", isError);
}

function setStreaming(value) {
  streaming = value;
  streamToggle.classList.toggle("is-on", streaming);
  streamToggle.setAttribute("aria-pressed", String(streaming));
  streamToggle.querySelector(".toggle-copy").textContent = streaming ? "On" : "Off";
}

async function runPrompt() {
  const userPromptValue = userPrompt.value.trim();
  if (!userPromptValue) {
    setStatus("User prompt is required.", true);
    userPrompt.focus();
    return;
  }

  runButton.disabled = true;
  outputText.textContent = "";
  setStatus(streaming ? "Streaming response..." : "Waiting for response...");

  try {
    const response = await fetch("/api/run", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        systemPrompt: systemPrompt.value,
        userPrompt: userPromptValue,
        model: model.value,
        stream: streaming,
      }),
    });

    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      throw new Error(payload.error || payload.detail || `Request failed with ${response.status}`);
    }

    if (!streaming) {
      const payload = await response.json();
      outputText.textContent = payload.assistantResponse || "";
      setStatus(`Saved to ${payload.historyPath}`);
      return;
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;

      outputText.textContent += decoder.decode(value, { stream: true });
      outputText.scrollTop = outputText.scrollHeight;
    }

    setStatus("Complete. Conversation saved in data/.");
  } catch (error) {
    setStatus(error instanceof Error ? error.message : "Unknown error", true);
  } finally {
    runButton.disabled = false;
  }
}

streamToggle.addEventListener("click", () => setStreaming(!streaming));
runButton.addEventListener("click", runPrompt);
clearButton.addEventListener("click", () => {
  outputText.textContent = "";
  setStatus("Ready");
});

userPrompt.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    runPrompt();
  }
});

setStreaming(true);
