# Using NotebookLM MCP with Claude.ai (web & mobile)

By default this MCP runs locally over stdio — Claude Code on your PC talks
to it directly. If you want to use it from **Claude.ai in a browser or on
your phone**, you need to expose the server over HTTPS so Claude.ai can reach
it. This guide walks through the full setup.

---

## How it works

```
Claude.ai  →  HTTPS  →  [Cloudflare Worker]  →  [Quick Tunnel]  →  MCP server on your PC
                         (stable URL, free)       (auto-generated)   (runs in background)
```

- The **MCP server** runs on your PC as normal, in HTTP mode instead of stdio.
- A **Cloudflare quick tunnel** gives it a public HTTPS address — no domain needed.
- An optional **Cloudflare Worker** gives you a *stable* URL that never changes
  even when the tunnel restarts. Claude.ai only needs to be configured once.
- You run one script (`start-remote.ps1` / `start-remote.sh`) whenever you want
  Claude.ai access. Close it when you are done.

---

## Prerequisites

| What | Where |
|------|-------|
| Node.js ≥ 18 | [nodejs.org](https://nodejs.org) |
| This repo installed & authenticated | Follow the main README first |
| `cloudflared` binary | [Download](https://github.com/cloudflare/cloudflared/releases/latest) — grab the right binary for your OS, put it on your PATH |
| A Cloudflare account (free) | [dash.cloudflare.com](https://dash.cloudflare.com) — no credit card, no domain required |

---

## Step 1 — Set up your .env

Copy `.env.example` to `.env` and fill in two values:

```bash
cp .env.example .env
```

Generate a secure API key (do this once):
```bash
node -e "console.log(require('crypto').randomBytes(32).toString('base64url'))"
```

Paste the output as your `NOTEBOOKLM_API_KEY` in `.env`. This token protects
your server — keep it secret.

---

## Step 2 — Deploy the Cloudflare Worker (one-time, gives you a stable URL)

This step creates a permanent `workers.dev` URL so Claude.ai never needs
reconfiguring when your tunnel restarts.

### 2a. Create a KV namespace

In [Cloudflare Dashboard](https://dash.cloudflare.com) → **Workers & Pages → KV**:
- Click **Create namespace**
- Name: `notebooklm-tunnel-url`
- Copy the **Namespace ID** that appears

### 2b. Create a Cloudflare API token

Dashboard → **My Profile → API Tokens → Create Token → Custom Token**:
- Permission: `Workers Scripts: Edit` + `Workers KV Storage: Edit`
- Save the token temporarily — you will use it once in step 2c

### 2c. Deploy the Worker

```bash
node scripts/deploy-worker.js \
  --account-id  YOUR_ACCOUNT_ID \
  --api-token   YOUR_API_TOKEN \
  --kv-ns-id    YOUR_KV_NAMESPACE_ID \
  --api-key     YOUR_NOTEBOOKLM_API_KEY
```

> **Note:** `scripts/deploy-worker.js` is included in this repo. It deploys
> the proxy Worker, sets the secrets, enables the `workers.dev` route, and
> prints your stable URL. You do not need `wrangler` installed.

The script prints something like:
```
✅ Worker deployed
   Stable URL : https://notebooklm-proxy.<your-subdomain>.workers.dev/mcp
   Register this URL once in Claude.ai — it never changes.
```

You can revoke the API token in Cloudflare after this step.

---

## Step 3 — Start the tunnel

**Windows** — run this in a terminal whenever you want Claude.ai access:
```powershell
.\start-remote.ps1
```

**macOS / Linux** — run:
```bash
./start-remote.sh
```

> These scripts are included in the repo. They start the MCP server in HTTP
> mode, launch a Cloudflare quick tunnel, and automatically update the Worker
> so Claude.ai routes to the current tunnel URL.

Leave the terminal open while you are using Claude.ai. Close it (or press
`Ctrl+C`) when you are done — the tunnel closes and your server is no longer
reachable from the internet.

---

## Step 4 — Register in Claude.ai (one-time)

1. Go to **claude.ai → Settings → Connectors → +**
2. Click **Add custom connector**
3. Fill in:
   - **Name:** `NotebookLM MCP`
   - **Remote MCP server URL:** the stable URL from Step 2c (ending in `/mcp`)
4. Click **Add**

Claude.ai will say "not connected" until your tunnel is running — that is expected.
Once you run `start-remote.ps1` it connects automatically, no changes needed.

---

## No stable URL? (simpler setup, manual updates)

If you skip the Worker step, you can still use Claude.ai — you just need to
update the connector URL each time the tunnel restarts:

1. Run `cloudflared tunnel --url http://localhost:3000` in a terminal
2. Copy the `trycloudflare.com` URL it prints
3. Update the connector URL in Claude.ai Settings → Connectors

This is fine for occasional use. The Worker approach is better if you use
Claude.ai regularly.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Claude.ai says "not connected" | Run `start-remote.ps1` / `start-remote.sh` on your PC |
| Claude.ai says "error" after connecting | Your session may have expired — run `re_auth` in Claude Code first |
| Tunnel starts but Worker not updating | Check that `NOTEBOOKLM_API_KEY` in `.env` matches what you set in the Worker secrets |
| `cloudflared: command not found` | Put the binary on your PATH or specify the full path in the start script |

---

## Security notes

- The MCP server is only reachable from the internet while the start script is running.
- `NOTEBOOKLM_API_KEY` is the only thing protecting your server — make it long and random.
- The Worker URL (`workers.dev`) is not advertised anywhere, but it has no additional
  auth layer — anyone who discovers it while your tunnel is up can reach your MCP.
  Keep the URL private.
- Your Google/NotebookLM account is isolated to you. Other people who set up their
  own instance from this repo connect to their own Google account — not yours.
