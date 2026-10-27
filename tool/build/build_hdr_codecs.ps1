param(
  [string]$CMake = 'cmake',
  [string]$Generator = 'Visual Studio 18 2026',
  [string]$Architecture = 'x64'
)
. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
$root = $RepositoryRoot
$build = Join-Path $root 'build/hdr-codecs'
$CMake = Resolve-ShenViewCMake $CMake
$gitPerl = Resolve-ShenViewGitTool 'usr/bin/perl.exe' -Optional
[string[]]$perlArg = if ($gitPerl) { @('-DPERL_EXECUTABLE=' + $gitPerl) } else { @() }
& $CMake -S (Join-Path $root 'native/hdr_codecs') -B $build -G $Generator -A $Architecture @perlArg
if ($LASTEXITCODE -ne 0) { throw "HDR 解码组件配置失败：$LASTEXITCODE" }
& $CMake --build $build --config Release --target viewer_gainmap viewer_heif_gainmap viewer_raw viewer_avif_animation --parallel 4
if ($LASTEXITCODE -ne 0) { throw "HDR 解码组件构建失败：$LASTEXITCODE" }
