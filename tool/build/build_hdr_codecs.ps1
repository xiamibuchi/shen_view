param(
  [string]$CMake = 'cmake',
  [string]$Generator = '',
  [string]$Architecture = 'x64',
  [ValidateRange(1,64)][int]$Parallel = 4
)
. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
$root = $RepositoryRoot
$build = Join-Path $root 'build/hdr-codecs'
$CMake = Resolve-ShenViewCMake $CMake
$Generator = Resolve-ShenViewVisualStudioGenerator $Generator
. (Join-Path $PSScriptRoot 'native_cache.ps1')
$key = Get-HdrCacheKey $CMake $Generator $Architecture
if (Test-NativeCacheManifest $build $key $HdrCacheDirectories $HdrCacheRequired) {
  Write-Host 'HDR native cache validated; compilation not needed.'
  return
}
$absoluteBuild = [IO.Path]::GetFullPath($build)
$allowedBuild = [IO.Path]::GetFullPath((Join-Path $root 'build')).TrimEnd('/','\') + [IO.Path]::DirectorySeparatorChar
if (-not $absoluteBuild.StartsWith($allowedBuild,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $absoluteBuild -Leaf) -ne 'hdr-codecs') { throw 'Invalid HDR build cleanup path' }
$buildKey = Get-HdrDependencyKey $CMake $Generator $Architecture
$incremental = Test-NativeIncrementalBuild $build $buildKey $HdrCacheDirectories $HdrCacheRequired
if ($incremental) {
  Write-Host 'HDR dependencies unchanged; reusing the local CMake build tree.'
  Remove-Item -LiteralPath (Join-Path $build 'cache-manifest.json')
} elseif (Test-Path -LiteralPath $absoluteBuild) {
  Remove-Item -LiteralPath $absoluteBuild -Recurse -Force
}
if (-not $incremental) {
  $gitPerl = Resolve-ShenViewGitTool 'usr/bin/perl.exe' -Optional
  [string[]]$perlArg = if ($gitPerl) { @('-DPERL_EXECUTABLE=' + $gitPerl) } else { @() }
  & $CMake -S (Join-Path $root 'native/hdr_codecs') -B $build -G $Generator -A $Architecture -DSHENVIEW_AVIF_ONLY=OFF "-DSHENVIEW_COMPILE_JOBS=$Parallel" @perlArg
  if ($LASTEXITCODE -ne 0) { throw "HDR 解码组件配置失败：$LASTEXITCODE" }
}
& $CMake --build $build --config Release --target viewer_hdr_helpers --parallel $Parallel
if ($LASTEXITCODE -ne 0) { throw "HDR 解码组件构建失败：$LASTEXITCODE" }
Write-NativeCacheManifest $build $key $HdrCacheDirectories
if (-not (Test-NativeCacheManifest $build $key $HdrCacheDirectories $HdrCacheRequired)) { throw 'HDR cache verification failed after build' }
@{schema=1;key=$buildKey} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $build 'build-state.json') -Encoding UTF8
