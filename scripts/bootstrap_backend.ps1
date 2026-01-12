$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot\.."
$backend = Join-Path $root 'backend'

Set-Location $backend

if (-not (Test-Path '.venv')) {
  python -m venv .venv
}

. .\.venv\Scripts\Activate.ps1

pip install --upgrade pip
pip install -r requirements.txt

if (-not (Test-Path '.env')) {
  Copy-Item .env.example .env
  Write-Host 'Created backend/.env (edit it and set VERIFY_API_KEY)'
}

$port = 8080
try {
  $envFile = Get-Content .env -ErrorAction Stop
  foreach ($line in $envFile) {
    if ($line -match '^PORT=(\d+)$') { $port = [int]$Matches[1] }
  }
} catch {}

Write-Host "Starting backend on http://0.0.0.0:$port (LAN reachable) ..."
uvicorn app.main:app --reload --host 0.0.0.0 --port $port
