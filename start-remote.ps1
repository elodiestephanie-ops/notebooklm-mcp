# NotebookLM MCP — remote startup script
# Starts the MCP server in HTTP mode and the Cloudflare Tunnel together.
# Run this whenever you want Claude.ai / mobile access.
#
# Usage: .\start-remote.ps1

$ErrorActionPreference = "Stop"
$projectDir = $PSScriptRoot

# Load .env
$envFile = Join-Path $projectDir ".env"
if (Test-Path $envFile) {
  Get-Content $envFile | Where-Object { $_ -match "^\s*[^#]" } | ForEach-Object {
    $parts = $_ -split "=", 2
    if ($parts.Count -eq 2) {
      [System.Environment]::SetEnvironmentVariable($parts[0].Trim(), $parts[1].Trim(), "Process")
    }
  }
}

$apiKey      = $env:NOTEBOOKLM_API_KEY
$cfToken     = $env:CLOUDFLARE_TUNNEL_TOKEN
$workerToken = $env:CLAUDE_AI_WORKER_TOKEN   # stable Worker proxy auth token
$port        = 3000
$workerUrl   = "https://notebooklm-proxy.elodiestephanie.workers.dev"

if (-not $apiKey -or -not $cfToken) {
  Write-Error "Missing NOTEBOOKLM_API_KEY or CLOUDFLARE_TUNNEL_TOKEN in .env"
  exit 1
}

Write-Host ""
Write-Host "Starting NotebookLM MCP (remote mode)" -ForegroundColor Cyan
Write-Host "  MCP server : http://localhost:$port/mcp"
Write-Host "  Stable URL : $workerUrl/mcp  (register this once in Claude.ai)"
Write-Host ""

# Start MCP server in HTTP mode (background job)
$mcpJob = Start-Job -ScriptBlock {
  param($dir, $port, $key)
  $env:NOTEBOOKLM_API_KEY = $key
  $env:NOTEBOOKLM_TRANSPORT = "http"
  $env:NOTEBOOKLM_PORT = $port
  Set-Location $dir
  node dist/index.js
} -ArgumentList $projectDir, $port, $apiKey

Write-Host "MCP server starting (job $($mcpJob.Id))..." -ForegroundColor Gray
Start-Sleep -Seconds 3

# Start Cloudflare quick tunnel and capture the public URL
# Use a blank temp config so cloudflared ignores ~/.cloudflared/config.yml (named tunnel)
# and creates a fresh trycloudflare.com quick tunnel instead.
Write-Host "Cloudflare Tunnel connecting..." -ForegroundColor Gray
$cfOut       = "$env:TEMP\cf-tunnel.txt"
$cfTempCfg   = "$env:TEMP\cf-quick.yml"
"" | Out-File -FilePath $cfTempCfg -Encoding utf8   # empty config = no named tunnel

$cf = Start-Process -FilePath "C:\Users\elodi\bin\cloudflared.exe" `
  -ArgumentList "tunnel","--config",$cfTempCfg,"--url","http://localhost:$port" `
  -PassThru -NoNewWindow -RedirectStandardError $cfOut

# Wait for the public URL to appear
$url = $null
for ($i = 0; $i -lt 30; $i++) {
  Start-Sleep -Seconds 1
  $match = Get-Content $cfOut -ErrorAction SilentlyContinue |
             Select-String "trycloudflare\.com" |
             Select-Object -First 1
  if ($match) {
    # Extract just the https://... URL from the log line (MatchInfo.Line is the plain text)
    if ($match.Line -match "(https://[^\s|]+trycloudflare\.com)") {
      $url = $matches[1].Trim()
      break
    }
  }
}

if ($url) {
  Write-Host ""
  Write-Host "TUNNEL IS LIVE" -ForegroundColor Green
  Write-Host "  Tunnel URL : $url" -ForegroundColor Gray

  # Push new tunnel URL to Cloudflare Worker KV so Claude.ai stable URL auto-updates
  Write-Host "Updating Worker proxy with new tunnel URL..." -ForegroundColor Gray
  try {
    $updateBody = "{`"tunnel_url`":`"$url`"}"
    $updateHeaders = @{
      "Authorization" = "Bearer $apiKey"   # UPDATE_SECRET == NOTEBOOKLM_API_KEY
      "Content-Type"  = "application/json"
    }
    $updateResp = Invoke-RestMethod `
      -Uri "$workerUrl/update-tunnel" `
      -Method Post `
      -Headers $updateHeaders `
      -Body $updateBody
    Write-Host "Worker updated: $($updateResp.stored)" -ForegroundColor Green
  } catch {
    Write-Host "Warning: Could not update Worker KV: $_" -ForegroundColor Yellow
    Write-Host "Claude.ai may still be pointing to the previous tunnel." -ForegroundColor Yellow
  }

  Write-Host ""
  Write-Host "============================================" -ForegroundColor Green
  Write-Host "Claude.ai stable integration URL (register once, never changes):" -ForegroundColor Yellow
  Write-Host "  URL   : $workerUrl/mcp" -ForegroundColor Green
  if ($workerToken) {
    Write-Host "  Token : $workerToken" -ForegroundColor Green
  }
  Write-Host "============================================" -ForegroundColor Green
  Write-Host ""
} else {
  Write-Host "Could not detect tunnel URL - check $cfOut" -ForegroundColor Red
}

# Keep tunnel running (Ctrl+C stops everything)
try {
  Wait-Process -Id $cf.Id
} finally {
  Write-Host "Stopping MCP server..." -ForegroundColor Gray
  Stop-Job $mcpJob -ErrorAction SilentlyContinue
  Remove-Job $mcpJob -ErrorAction SilentlyContinue
}
