// itch.io API CORS proxy — Cloudflare Worker (ES module).
//
// itch.io's API sends NO Access-Control-Allow-Origin header on any response
// (verified on 200/400/403/404), so browser builds cannot call it directly.
// This worker is a minimal pass-through that adds the CORS header so the
// game's web build can validate itch OAuth tokens via GET /profile.
//
// Deploy:
//   1. Cloudflare dashboard -> Workers & Pages -> Create -> Worker
//   2. Paste this file's contents, Deploy
//   3. Set the game's Project Setting identity/itch_api_proxy_url to the
//      worker URL (https://<worker-name>.<account>.workers.dev)
//   4. Rebuild the web export
//
// Security: the worker only forwards the Authorization header and only
// targets api.itch.io/profile — it does not read, store, or log tokens.

const TARGET = "https://api.itch.io/profile";

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Accept, Content-Type",
    "Access-Control-Max-Age": "86400",
  };
}

export default {
  async fetch(request) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }
    if (request.method !== "GET") {
      return new Response("method not allowed", { status: 405, headers: corsHeaders() });
    }
    // Forward only the Authorization header — nothing else leaves the game.
    const auth = request.headers.get("Authorization");
    if (!auth) {
      return new Response("missing Authorization header", { status: 400, headers: corsHeaders() });
    }
    const headers = new Headers({ Authorization: auth, Accept: "application/json" });
    const upstream = await fetch(TARGET, { method: "GET", headers });
    const body = await upstream.arrayBuffer();
    return new Response(body, {
      status: upstream.status,
      headers: {
        ...corsHeaders(),
        "Content-Type": upstream.headers.get("Content-Type") || "application/json",
      },
    });
  },
};