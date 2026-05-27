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

$apiKey   = $env:NOTEBOOKLM_API_KEY
$cfToken  = $env:CLOUDFLARE_TUNNEL_TOKEN
$port     = 3000
$tunnelUrl = "https://aecf99a5-5392-45a6-8a8b-eb44670236e1.cfargotunnel.com"

if (-not $apiKey -or -not $cfToken) {
  Write-Error "Missing NOTEBOOKLM_API_KEY or CLOUDFLARE_TUNNEL_TOKEN in .env"
  exit 1
}

Write-Host ""
Write-Host "Starting NotebookLM MCP (remote mode)" -ForegroundColor Cyan
Write-Host "  MCP server : http://localhost:$port/mcp"
Write-Host "  Public URL : $tunnelUrl/mcp"
Write-Host ""
Write-Host "Register this in Claude.ai Settings > Integrations:" -ForegroundColor Yellow
Write-Host "  URL   : $tunnelUrl/mcp" -ForegroundColor Green
Write-Host "  Token : $apiKey" -ForegroundColor Green
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
Write-Host "Cloudflare Tunnel connecting..." -ForegroundColor Gray
$cfOut = "$env:TEMP\cf-tunnel.txt"
$cf = Start-Process -FilePath "C:\Users\elodi\bin\cloudflared.exe" `
  -ArgumentList "tunnel","--url","http://localhost:$port" `
  -PassThru -NoNewWindow -RedirectStandardError $cfOut

# Wait for the public URL to appear
$url = $null
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Seconds 1
  $line = Get-Content $cfOut -ErrorAction SilentlyContinue | Select-String "trycloudflare.com"
  if ($line) {
    $url = ($line -split "https://")[1] -split " " | Select-Object -First 1
    $url = "https://$url".Trim()
    break
  }
}

if ($url) {
  Write-Host ""
  Write-Host "TUNNEL IS LIVE" -ForegroundColor Green
  Write-Host "============================================" -ForegroundColor Green
  Write-Host "Register this in Claude.ai Settings > Integrations:" -ForegroundColor Yellow
  Write-Host "  URL   : $url/mcp" -ForegroundColor Green
  Write-Host "  Token : $apiKey" -ForegroundColor Green
  Write-Host "============================================" -ForegroundColor Green
  Write-Host ""
  Write-Host "Note: This URL changes on each restart. Update Claude.ai when you restart." -ForegroundColor Gray
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
