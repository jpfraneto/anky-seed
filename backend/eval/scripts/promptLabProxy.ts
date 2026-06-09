#!/usr/bin/env bun
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { runsRoot } from "./evalLib";

const runDir = join(runsRoot, "2026-06-07T11-46-56-577Z");
const htmlPath = join(runDir, "OPENROUTER_PROMPT_LAB.html");
const port = Number(process.env.ANKY_PROMPT_LAB_PORT ?? 8787);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

Bun.serve({
  port,
  async fetch(request) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/lab")) {
      return new Response(await readFile(htmlPath, "utf8"), {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }

    if (request.method === "POST" && url.pathname === "/openrouter") {
      const authorization = request.headers.get("authorization");
      if (!authorization?.startsWith("Bearer ")) {
        return json({ error: "missing Authorization bearer token" }, 401);
      }

      let body: string;
      try {
        body = await request.text();
        JSON.parse(body);
      } catch {
        return json({ error: "invalid JSON body" }, 400);
      }

      try {
        const upstream = await fetch("https://openrouter.ai/api/v1/chat/completions", {
          method: "POST",
          headers: {
            Authorization: authorization,
            "Content-Type": "application/json",
            "HTTP-Referer": "http://127.0.0.1:8787/lab",
            "X-OpenRouter-Title": "Anky Local Prompt Lab",
          },
          body,
        });
        const text = await upstream.text();
        return new Response(text, {
          status: upstream.status,
          statusText: upstream.statusText,
          headers: {
            ...corsHeaders,
            "Content-Type": upstream.headers.get("content-type") ?? "application/json",
          },
        });
      } catch (error) {
        return json({ error: "proxy_fetch_failed", detail: error instanceof Error ? error.message : String(error) }, 502);
      }
    }

    return json({ error: "not found", routes: ["/lab", "/openrouter"] }, 404);
  },
});

console.log(`Anky prompt lab proxy listening on http://127.0.0.1:${port}/lab`);

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value, null, 2), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
