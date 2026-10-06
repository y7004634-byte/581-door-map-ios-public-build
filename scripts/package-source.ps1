param(
  [string]$OutputZip = 'C:\Users\cxz30\Downloads\581_DoorMap_Native_iOS_Hybrid_v0.1.0_SOURCE_R3_NO_MAC_CLOUD_BUILD.zip'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $root 'artifacts\package-stage-current'
$baseZip = Join-Path $root 'artifacts\package-base.zip'
$verify = Join-Path $root 'artifacts\package-verify-current'

Set-Location $root
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $verify) { Remove-Item $verify -Recurse -Force }
New-Item -ItemType Directory -Force (Split-Path $baseZip -Parent) | Out-Null
if (Test-Path $baseZip) { Remove-Item $baseZip -Force }
if (Test-Path $OutputZip) { Remove-Item $OutputZip -Force }

git archive --format=zip --output=$baseZip HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
Expand-Archive -LiteralPath $baseZip -DestinationPath $stage -Force

$manifestPath = Join-Path $stage 'SOURCE_MANIFEST_SHA256.txt'
if (Test-Path $manifestPath) { Remove-Item $manifestPath -Force }
$lines = [System.Collections.Generic.List[string]]::new()
$files = Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName
foreach ($file in $files) {
  $rel = $file.FullName.Substring($stage.Length).TrimStart('\').Replace('\','/')
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
  $lines.Add("$hash  $rel")
}
[System.IO.File]::WriteAllLines($manifestPath, $lines, [System.Text.UTF8Encoding]::new($false))

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory(
  $stage,
  $OutputZip,
  [System.IO.Compression.CompressionLevel]::Optimal,
  $false
)

Expand-Archive -LiteralPath $OutputZip -DestinationPath $verify -Force
$verifyManifest = Join-Path $verify 'SOURCE_MANIFEST_SHA256.txt'
$bad = [System.Collections.Generic.List[string]]::new()
foreach ($line in [System.IO.File]::ReadAllLines($verifyManifest)) {
  if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { $bad.Add("FORMAT $line"); continue }
  $expected = $matches[1]
  $rel = $matches[2]
  $path = Join-Path $verify ($rel.Replace('/','\'))
  if (-not (Test-Path -LiteralPath $path)) { $bad.Add("MISSING $rel"); continue }
  $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
  if ($got -ne $expected) { $bad.Add("HASH $rel") }
}
if ($bad.Count -gt 0) {
  $bad | ForEach-Object { Write-Output $_ }
  throw "package verification failed: $($bad.Count)"
}

$zipSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputZip).Hash.ToLowerInvariant()
$manifestSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $verifyManifest).Hash.ToLowerInvariant()
$result = Join-Path $root 'artifacts\package-latest.result.txt'
@(
  'status=PASS',
  "zip=$OutputZip",
  "zip_sha256=$zipSha",
  "manifest_sha256=$manifestSha",
  "manifest_entries=$($lines.Count)",
  "git_head=$(git rev-parse HEAD)"
) | Set-Content -LiteralPath $result -Encoding UTF8

Write-Output "RESULT PASS"
Write-Output "ZIP=$OutputZip"
Write-Output "ZIP_SHA256=$zipSha"
Write-Output "MANIFEST_SHA256=$manifestSha"
Write-Output "MANIFEST_ENTRIES=$($lines.Count)"
