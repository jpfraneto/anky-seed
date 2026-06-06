const videos = window.ANKY_TIKTOK_VIDEOS || [];
const stats = window.ANKY_TIKTOK_STATS || {};

const searchInput = document.querySelector("#search");
const ringFilter = document.querySelector("#ring-filter");
const pillarFilter = document.querySelector("#pillar-filter");
const statusFilter = document.querySelector("#status-filter");
const priorityFilter = document.querySelector("#priority-filter");
const list = document.querySelector("#video-list");
const template = document.querySelector("#video-template");
const resultCount = document.querySelector("#result-count");
const copyVisible = document.querySelector("#copy-visible");

let visibleVideos = [];

document.querySelector("#stat-videos").textContent = stats.videoCount || videos.length;
document.querySelector("#stat-rings").textContent = stats.ringCount || "";
document.querySelector("#stat-pillars").textContent = stats.pillarCount || "";

function labelize(value) {
  return value.replaceAll("_", " ");
}

function fillSelect(select, values, label) {
  select.innerHTML = "";
  select.append(new Option(`All ${label}`, "all"));
  values.forEach((value) => select.append(new Option(labelize(value), value)));
}

function unique(field) {
  return [...new Set(videos.map((video) => video[field]).filter(Boolean))].sort();
}

fillSelect(ringFilter, unique("ring"), "rings");
fillSelect(pillarFilter, unique("pillar"), "pillars");
fillSelect(statusFilter, unique("status"), "statuses");
fillSelect(priorityFilter, unique("priority").map(String), "priorities");

function matchesSelect(video, field, value) {
  return value === "all" || String(video[field]) === value;
}

function searchableText(video) {
  return [
    video.creator_handle,
    video.creator_name,
    video.visible_hook,
    video.why_it_fits,
    video.comment_direction,
    video.ring,
    video.pillar,
    video.status,
    video.search_query,
  ]
    .join(" ")
    .toLowerCase();
}

function applyFilters() {
  const query = searchInput.value.trim().toLowerCase();
  visibleVideos = videos.filter((video) => {
    return (
      matchesSelect(video, "ring", ringFilter.value) &&
      matchesSelect(video, "pillar", pillarFilter.value) &&
      matchesSelect(video, "status", statusFilter.value) &&
      matchesSelect(video, "priority", priorityFilter.value) &&
      (!query || searchableText(video).includes(query))
    );
  });
  render();
}

function render() {
  list.innerHTML = "";
  resultCount.textContent =
    visibleVideos.length === videos.length
      ? `Showing all ${videos.length} videos`
      : `Showing ${visibleVideos.length} of ${videos.length} videos`;

  const fragment = document.createDocumentFragment();
  visibleVideos.forEach((video) => {
    const node = template.content.cloneNode(true);
    const card = node.querySelector(".video-card");
    const creator = video.creator_name || video.creator_handle || "Unknown creator";
    card.querySelector(".creator").textContent = `@${video.creator_handle || "unknown"} · ${creator}`;
    card.querySelector("h2").textContent = video.visible_hook || "Untitled TikTok video";
    card.querySelector(".priority").textContent = `P${video.priority}`;
    card.querySelector(".why").textContent = video.why_it_fits || "Accepted into the warmup queue.";
    card.querySelector(".comment").textContent = video.comment_direction
      ? `Comment seed: ${video.comment_direction}`
      : "Comment seed: watch first, then write the precise sentence.";

    const meta = card.querySelector(".meta");
    [video.ring, video.pillar, video.status, video.watch_action].filter(Boolean).forEach((value) => {
      const chip = document.createElement("span");
      chip.className = `chip ${value}`;
      chip.textContent = labelize(value);
      meta.append(chip);
    });

    const watch = card.querySelector(".watch");
    watch.href = video.source_url;
    const copy = card.querySelector(".copy-one");
    copy.addEventListener("click", async () => {
      await navigator.clipboard.writeText(video.source_url);
      copy.textContent = "Copied";
      setTimeout(() => {
        copy.textContent = "Copy link";
      }, 1200);
    });

    fragment.append(node);
  });
  list.append(fragment);
}

[searchInput, ringFilter, pillarFilter, statusFilter, priorityFilter].forEach((control) => {
  control.addEventListener("input", applyFilters);
});

copyVisible.addEventListener("click", async () => {
  await navigator.clipboard.writeText(visibleVideos.map((video) => video.source_url).join("\n"));
  copyVisible.textContent = "Copied visible links";
  setTimeout(() => {
    copyVisible.textContent = "Copy visible links";
  }, 1400);
});

applyFilters();
