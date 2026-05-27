#!/usr/bin/env node
/**
 * deploy-worker.js
 * Deploys the NotebookLM MCP Cloudflare Worker proxy in one command.
 * No wrangler required — uses the Cloudflare REST API directly.
 *
 * Usage:
 *   node scripts/deploy-worker.js \
 *     --account-id  <CF_ACCOUNT_ID> \
 *     --api-token   <CF_API_TOKEN> \
 *     --kv-ns-id    <KV_NAMESPACE_ID> \
 *     --api-key     <NOTEBOOKLM_API_KEY>
 *
 * Options:
 *   --script-name   Worker script name (default: notebooklm-proxy)
 *   --subdomain     workers.dev subdomain to claim (default: auto-generated from email)
 */

import https from "https";
import { parseArgs } from "util";

const { values: args } = parseArgs({
  options: {
    "account-id": { type: "string" },
    "api-token":  { type: "string" },
    "kv-ns-id":   { type: "string" },
    "api-key":    { type: "string" },
    "script-name":{ type: "string", default: "notebooklm-proxy" },
    "subdomain":  { type: "string" },
  },
});

const required = ["account-id", "api-token", "kv-ns-id", "api-key"];
for (const r of required) {
  if (!args[r]) {
    console.error(`Missing required argument: --${r}`);
    console.error("Run with --help for usage.");
    process.exit(1);
  }
}

const ACCOUNT_ID  = args["account-id"];
const API_TOKEN   = args["api-token"];
const KV_NS_ID    = args["kv-ns-id"];
const API_KEY     = args["api-key"];
const SCRIPT_NAME = args["script-name"];

// ── Worker source ────────────────────────────────────────────────────────────
const WORKER_JS = `
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Update endpoint — called by start-remote script on each tunnel restart
    if (request.method === "POST" && url.pathname === "/update-tunnel") {
      const auth = request.headers.get("Authorization") || "";
      const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
      if (token !== env.UPDATE_SECRET) return new Response("Unauthorized", { status: 401 });
      let body;
      try { body = await request.json(); } catch { return new Response("Bad JSON", { status: 400 }); }
      if (!body.tunnel_url?.startsWith("https://")) return new Response("tunnel_url required", { status: 400 });
      await env.TUNNEL_KV.put("tunnel_url", body.tunnel_url);
      return new Response(JSON.stringify({ ok: true, stored: body.tunnel_url }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Health check (no auth required)
    if (url.pathname === "/healthz") {
      const tunnelUrl = await env.TUNNEL_KV.get("tunnel_url");
      return new Response(JSON.stringify({ ok: true, tunnel_url: tunnelUrl || null }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // MCP proxy — forward to current tunnel URL
    const tunnelUrl = await env.TUNNEL_KV.get("tunnel_url");
    if (!tunnelUrl) {
      return new Response(
        JSON.stringify({ error: "Tunnel not running. Start start-remote on your PC first." }),
        { status: 503, headers: { "Content-Type": "application/json" } }
      );
    }
    const targetUrl = tunnelUrl.replace(/\\/$/, "") + url.pathname + url.search;
    const headers = new Headers(request.headers);
    headers.set("Authorization", \`Bearer \${env.NOTEBOOKLM_API_KEY}\`);
    headers.delete("Host");
    try {
      const response = await fetch(targetUrl, {
        method: request.method,
        headers,
        body: ["GET", "HEAD"].includes(request.method) ? undefined : request.body,
      });
      return new Response(response.body, { status: response.status, statusText: response.statusText, headers: response.headers });
    } catch (e) {
      return new Response(JSON.stringify({ error: "Tunnel unreachable", detail: String(e) }),
        { status: 502, headers: { "Content-Type": "application/json" } });
    }
  },
};
`.trim();

// ── Helpers ──────────────────────────────────────────────────────────────────
function cfRequest(method, path, body, contentType = "application/json") {
  return new Promise((resolve, reject) => {
    const bodyStr = typeof body === "string" ? body : body ? JSON.stringify(body) : undefined;
    const req = https.request(
      { hostname: "api.cloudflare.com", path: `/client/v4${path}`, method,
        headers: { Authorization: `Bearer ${API_TOKEN}`, "Content-Type": contentType,
                   ...(bodyStr ? { "Content-Length": Buffer.byteLength(bodyStr) } : {}) } },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          try { resolve(JSON.parse(data)); }
          catch { resolve({ raw: data }); }
        });
      }
    );
    req.on("error", reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

function multipartRequest(path, scriptName, workerJs, metadata) {
  return new Promise((resolve, reject) => {
    const boundary = "boundary" + Math.random().toString(36).slice(2);
    const CRLF = "\r\n";
    const metaStr = JSON.stringify(metadata);
    let body = "";
    body += `--${boundary}${CRLF}`;
    body += `Content-Disposition: form-data; name="metadata"${CRLF}`;
    body += `Content-Type: application/json${CRLF}${CRLF}`;
    body += `${metaStr}${CRLF}`;
    body += `--${boundary}${CRLF}`;
    body += `Content-Disposition: form-data; name="index.js"; filename="index.js"${CRLF}`;
    body += `Content-Type: application/javascript+module${CRLF}${CRLF}`;
    body += `${workerJs}${CRLF}`;
    body += `--${boundary}--`;

    const req = https.request(
      { hostname: "api.cloudflare.com", path: `/client/v4${path}`, method: "PUT",
        headers: { Authorization: `Bearer ${API_TOKEN}`,
                   "Content-Type": `multipart/form-data; boundary=${boundary}`,
                   "Content-Length": Buffer.byteLength(body) } },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          try { resolve(JSON.parse(data)); } catch { resolve({ raw: data }); }
        });
      }
    );
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log("Deploying NotebookLM MCP Worker...\n");

  // 1. Claim workers.dev subdomain (skip if already claimed)
  if (args["subdomain"]) {
    const sub = await cfRequest("PUT", `/accounts/${ACCOUNT_ID}/workers/subdomain`,
      { subdomain: args["subdomain"] });
    if (sub.success) console.log(`✓ Subdomain: ${sub.result.subdomain}.workers.dev`);
    else console.warn("  Subdomain claim skipped (may already exist):", sub.errors?.[0]?.message);
  }

  // 2. Get current subdomain
  const subInfo = await cfRequest("GET", `/accounts/${ACCOUNT_ID}/workers/subdomain`);
  const subdomain = subInfo.result?.subdomain;

  // 3. Deploy Worker script
  const metadata = {
    main_module: "index.js",
    compatibility_date: "2024-09-23",
    bindings: [{ type: "kv_namespace", name: "TUNNEL_KV", namespace_id: KV_NS_ID }],
  };
  const deploy = await multipartRequest(
    `/accounts/${ACCOUNT_ID}/workers/scripts/${SCRIPT_NAME}`,
    SCRIPT_NAME, WORKER_JS, metadata
  );
  if (!deploy.success) {
    console.error("Deploy failed:", deploy.errors);
    process.exit(1);
  }
  console.log(`✓ Worker script deployed: ${SCRIPT_NAME}`);

  // 4. Set secrets
  const secrets = {
    NOTEBOOKLM_API_KEY: API_KEY,
    UPDATE_SECRET: API_KEY,
  };
  for (const [name, text] of Object.entries(secrets)) {
    const r = await cfRequest("PUT",
      `/accounts/${ACCOUNT_ID}/workers/scripts/${SCRIPT_NAME}/secrets`,
      { name, text, type: "secret_text" });
    if (r.success) console.log(`✓ Secret set: ${name}`);
    else console.warn(`  Warning setting ${name}:`, r.errors?.[0]?.message);
  }

  // 5. Enable workers.dev route
  const route = await cfRequest("POST",
    `/accounts/${ACCOUNT_ID}/workers/scripts/${SCRIPT_NAME}/subdomain`,
    { enabled: true });
  if (route.success) console.log(`✓ workers.dev route enabled`);

  // 6. Print result
  const workerUrl = subdomain
    ? `https://${SCRIPT_NAME}.${subdomain}.workers.dev`
    : `https://${SCRIPT_NAME}.<your-subdomain>.workers.dev`;

  console.log(`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ✅ Worker deployed successfully

  Stable URL : ${workerUrl}/mcp

  Register this URL once in Claude.ai:
    Settings → Connectors → Add custom connector
    Name: NotebookLM MCP
    URL:  ${workerUrl}/mcp

  Then run start-remote.ps1 (Windows) or
  start-remote.sh (Mac/Linux) whenever you
  want Claude.ai access.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
`);
}

main().catch((e) => { console.error(e); process.exit(1); });
