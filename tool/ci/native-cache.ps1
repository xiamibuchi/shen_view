[CmdletBinding()]
param([ValidateSet('Keys','Build')][string]$Action = 'Build')
. (Join-Path $PSScriptRoot '../paths.ps1')
. (Join-Path $PSScriptRoot '../build/native_cache.ps1')
$ErrorActionPreference = 'Stop'
if ($Action -eq 'Keys') {
  $cmake = Resolve-ShenViewCMake
  $generator = Resolve-ShenViewVisualStudioGenerator
  $hdr = Get-HdrCacheKey $cmake $generator 'x64'
  $ffmpeg = Get-FfmpegCacheKey (Split-Path (Resolve-ShenViewTool gcc.exe))
  if (-not $env:GITHUB_OUTPUT) { throw 'GITHUB_OUTPUT is required for cache keys' }
  @("hdr=windows-x64-hdr-v1-$hdr", "ffmpeg=windows-x64-ffmpeg-v1-$ffmpeg") |
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Encoding UTF8
} else {
  & (Join-Path $PSScriptRoot '../build/build_hdr_codecs.ps1')
  & (Join-Path $PSScriptRoot '../build/build_ffmpeg.ps1')
}
