const X_HOME_URL = "https://x.com/home";
const X_ORIGINS = new Set(["https://x.com", "https://twitter.com"]);

chrome.action.onClicked.addListener(async (tab) => {
  const url = safeUrl(tab.url);

  if (!tab.id || !url || !X_ORIGINS.has(url.origin)) {
    await chrome.tabs.create({ url: X_HOME_URL });
    return;
  }

  await chrome.scripting.insertCSS({
    target: { tabId: tab.id },
    files: ["content.css"],
  });

  await chrome.scripting.executeScript({
    target: { tabId: tab.id },
    files: ["content.js"],
  });
});

function safeUrl(value) {
  try {
    return value ? new URL(value) : null;
  } catch {
    return null;
  }
}
