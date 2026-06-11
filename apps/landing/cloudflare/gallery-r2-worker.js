const imagePattern = /\.(avif|gif|jpe?g|png|webp)$/i;

function corsHeaders() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-allow-headers": "content-type",
  };
}

function json(data, init = {}) {
  return new Response(JSON.stringify(data), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...corsHeaders(),
      ...init.headers,
    },
  });
}

function titleFromKey(key) {
  const filename = key.split("/").filter(Boolean).at(-1) || key;
  return filename
    .replace(/\.[a-z0-9]+$/i, "")
    .replace(/[-_]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function extensionFromKey(key) {
  return key.split("?")[0].split(".").pop()?.toLowerCase() || "";
}

function basenameFromKey(key) {
  return key.replace(/\.[a-z0-9]+$/i, "");
}

function extensionRank(key) {
  const extension = extensionFromKey(key);

  if (extension === "webp") {
    return 0;
  }

  if (extension === "avif") {
    return 1;
  }

  return 2;
}

function naturalCompare(left, right) {
  return left.localeCompare(right, undefined, {
    numeric: true,
    sensitivity: "base",
  });
}

function objectUrl(origin, key) {
  return `${origin}/gallery/${key
    .split("/")
    .map((part) => encodeURIComponent(part))
    .join("/")}`;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders() });
    }

    if (url.pathname === "/gallery.json") {
      const listed = await env.GALLERY_BUCKET.list({
        prefix: env.GALLERY_PREFIX || "",
        limit: 1000,
      });

      const preferredObjects = new Map();

      listed.objects
        .filter((object) => imagePattern.test(object.key))
        .sort((left, right) => {
          const rankDelta = extensionRank(left.key) - extensionRank(right.key);

          if (rankDelta !== 0) {
            return rankDelta;
          }

          return naturalCompare(left.key, right.key);
        })
        .forEach((object) => {
          const basename = basenameFromKey(object.key);

          if (!preferredObjects.has(basename)) {
            preferredObjects.set(basename, object);
          }
        });

      const images = [...preferredObjects.values()].map((object) => ({
          id: object.key,
          key: object.key,
          title: titleFromKey(object.key),
          src: objectUrl(url.origin, object.key),
          updated: object.uploaded?.toISOString(),
        }));

      return json({ images });
    }

    if (url.pathname.startsWith("/gallery/")) {
      const key = decodeURIComponent(url.pathname.slice("/gallery/".length));
      const object = await env.GALLERY_BUCKET.get(key);

      if (!object) {
        return new Response("Not found", { status: 404, headers: corsHeaders() });
      }

      return new Response(object.body, {
        headers: {
          ...corsHeaders(),
          "cache-control": "public, max-age=31536000, immutable",
          "content-type":
            object.httpMetadata?.contentType || "application/octet-stream",
          etag: object.httpEtag,
        },
      });
    }

    return json({ error: "Not found" }, { status: 404 });
  },
};
