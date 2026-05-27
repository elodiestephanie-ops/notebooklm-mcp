#!/usr/bin/env bash
# NotebookLM MCP — remote startup script (Mac / Linux)
# Starts the MCP server in HTTP mode and a Cloudflare quick tunnel.
# Run this whenever you want Claude.ai / mobile access.
# Usage: ./start-remote.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
  set +a
fi

: "${NOTEBOOKLM_API_KEY:?Missing NOTEBOOKLM_API_KEY in .env}"
: "${CLOUDFLARE_TUNNEL_TOKEN:=}"   # optional for quick tunnel

PORT=3000
WORKER_URL="https://notebooklm-proxy.elodiestephanie.workers.dev"
CF_OUT="/tmp/cf-tunnel.txt"

echo ""
echo "Starting NotebookLM MCP (remote mode)"
echo "  MCP server : http://localhost:$PORT/mcp"
echo "  Stable URL : $WORKER_URL/mcp  (register this once in Claude.ai)"
echo ""

# Start MCP server in HTTP mode
NOTEBOOKLM_API_KEY="$NOTEBOOKLM_API_KEY" \
NOTEBOOKLM_TRANSPORT=http \
NOTEBOOKLM_PORT="$PORT" \
  node "$SCRIPT_DIR/dist/index.js" &
MCP_PID=$!
echo "MCP server starting (pid $MCP_PID)..."
sleep 3

# Start Cloudflare quick tunnel
# Uses a blank temp config so cloudflared ignores any local named-tunnel config
CF_TMP_CFG="$(mktemp /tmp/cf-quick-XXXX.yml)"
echo "" > "$CF_TMP_CFG"
echo "Cloudflare Tunnel connecting..."
cloudflared tunnel --config "$CF_TMP_CFG" --url "http://localhost:$PORT" \
  2>"$CF_OUT" &
CF_PID=$!

# Wait for the trycloudflare.com URL to appear
TUNNEL_URL=""
for i in $(seq 1 30); do
  sleep 1
  if TUNNEL_URL=$(grep -oP 'https://[^\s|]+trycloudflare\.com' "$CF_OUT" 2>/dev/null | head -1); then
    [[ -n "$TUNNEL_URL" ]] && break
  fi
done

if [[ -n "$TUNNEL_URL" ]]; then
  echo ""
  echo "TUNNEL IS LIVE"
  echo "  Tunnel URL : $TUNNEL_URL"

  # Push new tunnel URL to Cloudflare Worker KV
  echo "Updating Worker proxy with new tunnel URL..."
  if curl -sf -X POST "$WORKER_URL/update-tunnel" \
    -H "Authorization: Bearer $NOTEBOOKLM_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"tunnel_url\":\"$TUNNEL_URL\"}" | grep -q '"ok":true'; then
    echo "Worker updated: $TUNNEL_URL"
  else
    echo "Warning: Could not update Worker KV — Claude.ai may use the previous tunnel URL."
  fi

  echo ""
  echo "============================================"
  echo "Claude.ai stable URL (register once, never changes):"
  echo "  URL : $WORKER_URL/mcp"
  echo "============================================"
  echo ""
else
  echo "Could not detect tunnel URL — check $CF_OUT"
fi

# Cleanup on exit
cleanup() {
  echo "Stopping MCP server and tunnel..."
  kill "$MCP_PID" 2>/dev/null || true
  kill "$CF_PID" 2>/dev/null || true
  rm -f "$CF_TMP_CFG"
}
trap cleanup EXIT INT TERM

# Keep running until Ctrl+C
wait "$CF_PID"
