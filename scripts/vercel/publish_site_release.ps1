param(
  [string]$ProjectDir = "",
  [string]$EnvFile = "",
  [string]$VercelToken = "",
  [switch]$Prod,
  [switch]$Execute,
  [switch]$BindCustomDomain,
  [int]$DeployRetries = 2
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($EnvFile)) {
  $EnvFile = Join-Path $scriptRoot ".env"
}

function Import-EnvFile {
  param([string]$Path)
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
    return
  }
  foreach ($rawLine in Get-Content -LiteralPath $Path) {
    $line = $rawLine.Trim()
    if (-not $line -or $line.StartsWith("#")) {
      continue
    }
    $parts = $line -split "=", 2
    if ($parts.Count -ne 2) {
      continue
    }
    $name = $parts[0].Trim()
    if (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($name, "Process"))) {
      continue
    }
    Set-Item -Path ("Env:{0}" -f $name) -Value $parts[1].Trim()
  }
}

function Invoke-VercelCli {
  param([string[]]$Arguments)
  if (Get-Command vercel -ErrorAction SilentlyContinue) {
    & vercel @Arguments
    return
  }
  if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    throw "Vercel CLI not found and npx is not available. Install Node.js/npm or install Vercel CLI first."
  }
  & npx --yes vercel@54.5.1 @Arguments
}

function Invoke-VercelWithRetry {
  param(
    [string[]]$Arguments,
    [int]$MaxAttempts
  )
  $attempts = [Math]::Max(1, $MaxAttempts)
  $lastOutput = ""
  for ($attempt = 1; $attempt -le $attempts; $attempt += 1) {
    Write-Output ("Running: vercel {0} (attempt {1}/{2})" -f ($Arguments -join " "), $attempt, $attempts)
    $output = Invoke-VercelCli -Arguments $Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $lastOutput = ($output | Out-String).Trim()
    if ($lastOutput) {
      Write-Output $lastOutput
    }
    if ($exitCode -eq 0) {
      return $lastOutput
    }
    if ($attempt -lt $attempts) {
      Start-Sleep -Seconds ([Math]::Min(10, 2 * $attempt))
    }
  }
  throw "Vercel command failed after $attempts attempt(s)."
}

function Get-VercelDeploymentUrl {
  param([string]$DeployOutput)
  if ([string]::IsNullOrWhiteSpace($DeployOutput)) {
    return ""
  }
  $matches = [regex]::Matches($DeployOutput, "https://[^\s]+\.vercel\.app")
  if ($matches.Count -eq 0) {
    return ""
  }
  return $matches[$matches.Count - 1].Value.Trim()
}

function Test-LocalVercelProjectLink {
  param(
    [string]$RootDir,
    [string]$ExpectedProjectName
  )
  $projectJsonPath = Join-Path $RootDir ".vercel\project.json"
  if (-not (Test-Path -LiteralPath $projectJsonPath)) {
    throw "Local Vercel project link was not found. Run scripts\vercel\link_project.cmd first."
  }
  $project = Get-Content -Raw -LiteralPath $projectJsonPath | ConvertFrom-Json
  $actualProjectName = [string]$project.projectName
  if ($ExpectedProjectName -and $actualProjectName -and $actualProjectName -ne $ExpectedProjectName) {
    throw "Local Vercel project link mismatch. VERCEL_PROJECT_NAME='$ExpectedProjectName' but local link is '$actualProjectName'."
  }
}

Import-EnvFile -Path $EnvFile

if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
  $ProjectDir = [System.Environment]::GetEnvironmentVariable("VERCEL_SITE_DIR", "Process")
}
if ([string]::IsNullOrWhiteSpace($ProjectDir)) {
  throw "VERCEL_SITE_DIR is required. Set it in scripts/vercel/.env or pass -ProjectDir."
}
if (-not (Test-Path -LiteralPath $ProjectDir)) {
  throw "Configured VERCEL_SITE_DIR does not exist: $ProjectDir"
}

$projectName = [System.Environment]::GetEnvironmentVariable("VERCEL_PROJECT_NAME", "Process")
if ([string]::IsNullOrWhiteSpace($projectName)) {
  throw "VERCEL_PROJECT_NAME is required. Set it in scripts/vercel/.env."
}

$tokenValue = if ([string]::IsNullOrWhiteSpace($VercelToken)) {
  [System.Environment]::GetEnvironmentVariable("VERCEL_TOKEN", "Process")
} else {
  $VercelToken
}
$scopeValue = [System.Environment]::GetEnvironmentVariable("VERCEL_SCOPE", "Process")
$customDomain = [System.Environment]::GetEnvironmentVariable("VERCEL_CUSTOM_DOMAIN", "Process")
$shouldBindDomain = $BindCustomDomain -or ([System.Environment]::GetEnvironmentVariable("VERCEL_BIND_CUSTOM_DOMAIN", "Process") -eq "true")

$resolvedProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
$projectJsonPath = Join-Path $resolvedProjectDir ".vercel\project.json"
if ($Execute -or (Test-Path -LiteralPath $projectJsonPath)) {
  Test-LocalVercelProjectLink -RootDir $resolvedProjectDir -ExpectedProjectName $projectName
} else {
  Write-Output "Local Vercel project link was not found. Run scripts\vercel\link_project.cmd before deploying."
}

$deployArgs = @("deploy", $resolvedProjectDir, "--yes")
if ($Prod) {
  $deployArgs += "--prod"
}
if ($tokenValue) {
  $deployArgs += @("--token", $tokenValue)
}
if ($scopeValue -and $scopeValue -ne "iunknow588") {
  $deployArgs += @("--scope", $scopeValue)
}

Write-Output "Vercel project: $projectName"
Write-Output "Deploy directory: $resolvedProjectDir"
Write-Output "Custom domain: $customDomain"

if (-not $Execute) {
  Write-Output "Dry run only. Re-run with -Execute to deploy."
  Write-Output ("Command: vercel {0}" -f ($deployArgs -join " "))
  return
}

$deployOutput = Invoke-VercelWithRetry -Arguments $deployArgs -MaxAttempts $DeployRetries
$deploymentUrl = Get-VercelDeploymentUrl -DeployOutput $deployOutput

if ($Prod -and $shouldBindDomain -and $customDomain) {
  if (-not $deploymentUrl) {
    throw "Deployment URL could not be parsed from Vercel output; cannot bind custom domain."
  }
  $aliasArgs = @("alias", "set", $deploymentUrl, $customDomain)
  if ($tokenValue) {
    $aliasArgs += @("--token", $tokenValue)
  }
  if ($scopeValue -and $scopeValue -ne "iunknow588") {
    $aliasArgs += @("--scope", $scopeValue)
  }
  Invoke-VercelWithRetry -Arguments $aliasArgs -MaxAttempts 1
}
