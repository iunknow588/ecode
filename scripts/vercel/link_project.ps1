$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envPath = Join-Path $scriptDir '.env'
$exampleEnvPath = Join-Path $scriptDir '.env.example'

function Import-EnvFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }
  foreach ($rawLine in Get-Content -LiteralPath $Path) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith('#')) {
      continue
    }
    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) {
      continue
    }
    if (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($parts[0].Trim(), 'Process'))) {
      continue
    }
    Set-Item -Path ("Env:{0}" -f $parts[0].Trim()) -Value $parts[1].Trim()
  }
}

Import-EnvFile -Path $envPath
Import-EnvFile -Path $exampleEnvPath

$repoRoot = if ($env:VERCEL_SITE_DIR) {
  Resolve-Path -LiteralPath $env:VERCEL_SITE_DIR
} else {
  Resolve-Path (Join-Path $scriptDir '..\..')
}

if (-not $env:VERCEL_PROJECT_NAME) {
  throw 'VERCEL_PROJECT_NAME is required. Set it in scripts/vercel/.env'
}
if (-not $env:VERCEL_SCOPE) {
  throw 'VERCEL_SCOPE is required. ecode production should use VERCEL_SCOPE=iunknow588, not the LUCKEE team scope.'
}

function Invoke-VercelCli {
  param([string[]]$Arguments)
  if (Get-Command vercel -ErrorAction SilentlyContinue) {
    & vercel @Arguments
    return
  }
  if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    throw 'Vercel CLI not found and npx is not available. Install Node.js/npm or install Vercel CLI first.'
  }
  Write-Host "[WARN] Vercel CLI not found. Falling back to npx --yes vercel@54.5.1" -ForegroundColor Yellow
  & npx --yes vercel@54.5.1 @Arguments
}

Push-Location $repoRoot
try {
  $args = @('link', '--project', $env:VERCEL_PROJECT_NAME, '--yes')
  if ($env:VERCEL_SCOPE -and $env:VERCEL_SCOPE -ne 'iunknow588') {
    $args += @('--scope', $env:VERCEL_SCOPE)
  }
  if ($env:VERCEL_TOKEN) {
    $args += @('--token', $env:VERCEL_TOKEN)
  }
  Write-Host "[INFO] Linking Vercel project $($env:VERCEL_PROJECT_NAME) under scope $($env:VERCEL_SCOPE)" -ForegroundColor Green
  Invoke-VercelCli -Arguments $args
} finally {
  Pop-Location
}
