[CmdletBinding()]
param(
  [ValidateSet('Keys','Build','Verify')][string]$Action = 'Build',
  [ValidateSet('All','Hdr','Ffmpeg')][string]$Component = 'All'
)
. (Join-Path $PSScriptRoot '../paths.ps1')
. (Join-Path $PSScriptRoot '../build/native_cache.ps1')
$ErrorActionPreference = 'Stop'
foreach ($name in @('Hdr','Ffmpeg')) {
  if ($Component -ne 'All' -and $Component -ne $name) { continue }
  if ($Action -eq 'Build') {
    $script = if ($name -eq 'Hdr') { 'build_hdr_codecs.ps1' } else { 'build_ffmpeg.ps1' }
    & (Join-Path $PSScriptRoot "../build/$script")
    continue
  }
  if ($name -eq 'Hdr') {
    $key = Get-HdrCacheKey (Resolve-ShenViewCMake) (Resolve-ShenViewVisualStudioGenerator) 'x64'
    $root = Join-Path $NativeBuildRoot 'hdr-codecs'
    $directories = $HdrCacheDirectories
    $required = $HdrCacheRequired
  } else {
    $key = Get-FfmpegCacheKey (Split-Path (Resolve-ShenViewTool gcc.exe))
    $root = Join-Path $NativeBuildRoot 'ffmpeg/windows-x64'
    $directories = $FfmpegCacheDirectories
    $required = $FfmpegCacheRequired
  }
  if ($Action -eq 'Keys') {
    if (-not $env:GITHUB_OUTPUT) { throw 'GITHUB_OUTPUT is required for cache keys' }
    $label = $name.ToLowerInvariant()
    "$label=windows-x64-$label-v1-$key" | Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding UTF8
  } elseif (-not (Test-NativeCacheManifest $root $key $directories $required)) {
    throw "Invalid $name artifact: missing files, mismatched inputs or corrupt outputs"
  } else {
    Write-Host "$name artifact matches the current source, toolchain and file hashes."
  }
}
