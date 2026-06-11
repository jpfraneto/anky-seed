const STORAGE_KEY = "anky:tiktok-warmup:tapped";
const videos = window.ANKY_TIKTOK_VIDEOS || [];

const list = document.querySelector("#links");
const remainingCount = document.querySelector("#remaining-count");
const reset = document.querySelector("#reset");

function loadTapped() {
  try {
    return new Set(JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]"));
  } catch {
    return new Set();
  }
}

function saveTapped(tapped) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify([...tapped]));
}

function titleFor(video) {
  return video.visible_hook || video.source_url;
}

function metaFor(video) {
  const creator = video.creator_handle ? `@${video.creator_handle}` : "TikTok";
  const pillar = video.pillar ? video.pillar.replaceAll("_", " ") : "";
  return [creator, pillar].filter(Boolean).join(" · ");
}

function render() {
  const tapped = loadTapped();
  const remaining = videos.filter((video) => !tapped.has(video.source_url));

  remainingCount.textContent = `${remaining.length} left`;
  list.innerHTML = "";

  if (remaining.length === 0) {
    const empty = document.createElement("li");
    empty.className = "empty";
    empty.textContent = "All videos have been opened.";
    list.append(empty);
    return;
  }

  const fragment = document.createDocumentFragment();
  remaining.forEach((video, index) => {
    const item = document.createElement("li");
    const link = document.createElement("a");
    const number = document.createElement("span");
    const body = document.createElement("span");
    const title = document.createElement("span");
    const meta = document.createElement("span");

    link.href = video.source_url;
    link.target = "_blank";
    link.rel = "noreferrer";
    number.className = "number";
    number.textContent = String(index + 1).padStart(3, "0");
    title.className = "title";
    title.textContent = titleFor(video);
    meta.className = "meta";
    meta.textContent = metaFor(video);

    body.append(title, meta);
    link.append(number, body);
    link.addEventListener("click", () => {
      const nextTapped = loadTapped();
      nextTapped.add(video.source_url);
      saveTapped(nextTapped);
      window.setTimeout(render, 80);
    });

    item.append(link);
    fragment.append(item);
  });
  list.append(fragment);
}

reset.addEventListener("click", () => {
  localStorage.removeItem(STORAGE_KEY);
  render();
});

render();
