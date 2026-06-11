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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders() });
    }

    if (url.pathname === "/memes.json") {
      const listed = await env.MEMES_BUCKET.list({
        prefix: env.MEMES_PREFIX || "",
        limit: 1000,
      });

      const memes = listed.objects
        .filter((object) => imagePattern.test(object.key))
        .map((object) => ({
          id: object.key,
          key: object.key,
          title: titleFromKey(object.key),
          src: `${url.origin}/memes/${encodeURIComponent(object.key)}`,
          updated: object.uploaded?.toISOString(),
        }));

      return json({ memes });
    }

    if (url.pathname.startsWith("/memes/")) {
      const key = decodeURIComponent(url.pathname.slice("/memes/".length));
      const object = await env.MEMES_BUCKET.get(key);

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
