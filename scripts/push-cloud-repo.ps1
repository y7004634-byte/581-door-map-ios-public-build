param(
  [Parameter(Mandatory = $true)]
  [string]$RemoteUrl
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

git diff --check
if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed' }

if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { throw 'RemoteUrl is empty' }

# Prove remote reachability/auth before mutating local origin.
git ls-remote $RemoteUrl *> $null
if ($LASTEXITCODE -ne 0) {
  throw 'GitHub remote/auth preflight failed; local origin was not modified.'
}

$hasOrigin = @((git remote)) -contains 'origin'
if ($hasOrigin) {
  git remote set-url origin $RemoteUrl
} else {
  git remote add origin $RemoteUrl
}

git push -u origin main
if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
Write-Output 'PUSH PASS; GitHub Actions should start automatically on main.'
