param(
  [string]$CMake = 'cmake',
  [string]$Generator = '',
  [string]$Architecture = 'x64'
)
. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
$root = $RepositoryRoot
$build = Join-Path $root 'build/hdr-codecs'
$CMake = Resolve-ShenViewCMake $CMake
$Generator = Resolve-ShenViewVisualStudioGenerator $Generator
. (Join-Path $PSScriptRoot 'native_cache.ps1')
$key = Get-HdrCacheKey $CMake $Generator $Architecture
$required = @('bin/viewer_gainmap.exe','bin/viewer_heif_gainmap.exe','bin/viewer_raw.exe','bin/viewer_avif_animation.exe',
  'licenses/hdr/LibRaw-LICENSE.CDDL','licenses/hdr/libavif-LICENSE','licenses/hdr/lcms2-LICENSE',
  'licenses/hdr/libaom-LICENSE','licenses/hdr/libaom-PATENTS','licenses/hdr/libultrahdr-LICENSE',
  'licenses/hdr/Adobe-Gain-Map-NOTICE','licenses/hdr/libjpeg-turbo-LICENSE.md')
if (Test-NativeCacheManifest $build $key @('bin','licenses') $required) {
  Write-Host 'HDR native cache validated; compilation not needed.'
  return
}
$absoluteBuild = [IO.Path]::GetFullPath($build)
$allowedBuild = [IO.Path]::GetFullPath((Join-Path $root 'build')).TrimEnd('/','\') + [IO.Path]::DirectorySeparatorChar
if (-not $absoluteBuild.StartsWith($allowedBuild,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $absoluteBuild -Leaf) -ne 'hdr-codecs') { throw 'Invalid HDR build cleanup path' }
if (Test-Path -LiteralPath $absoluteBuild) { Remove-Item -LiteralPath $absoluteBuild -Recurse -Force }
$gitPerl = Resolve-ShenViewGitTool 'usr/bin/perl.exe' -Optional
[string[]]$perlArg = if ($gitPerl) { @('-DPERL_EXECUTABLE=' + $gitPerl) } else { @() }
& $CMake -S (Join-Path $root 'native/hdr_codecs') -B $build -G $Generator -A $Architecture -DSHENVIEW_AVIF_ONLY=OFF @perlArg
if ($LASTEXITCODE -ne 0) { throw "HDR 解码组件配置失败：$LASTEXITCODE" }
& $CMake --build $build --config Release --target viewer_gainmap viewer_heif_gainmap viewer_raw viewer_avif_animation --parallel 4
if ($LASTEXITCODE -ne 0) { throw "HDR 解码组件构建失败：$LASTEXITCODE" }
Write-NativeCacheManifest $build $key @('bin','licenses')
if (-not (Test-NativeCacheManifest $build $key @('bin','licenses') $required)) { throw 'HDR cache verification failed after build' }
