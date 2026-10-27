param(
  [string]$CMake = 'cmake',
  [string]$Generator = 'Visual Studio 18 2026',
  [string]$Architecture = 'x64',
  [string]$SevenZipEngine = ''
)
. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
$root = $RepositoryRoot
$CMake = Resolve-ShenViewCMake $CMake
if (-not $SevenZipEngine) {
  $SevenZipEngine = Join-Path (Split-Path (Resolve-ShenViewSevenZip)) '7z.dll'
}
if (-not (Test-Path -LiteralPath $SevenZipEngine -PathType Leaf)) { throw '未找到 7z.dll，请传 -SevenZipEngine。' }
$build = Join-Path $root 'build/archive-helper'
& $CMake -S (Join-Path $root 'native/archive_helper') -B $build -G $Generator -A $Architecture "-DVIEWER_7ZIP_ENGINE=$SevenZipEngine"
if ($LASTEXITCODE -ne 0) { throw "压缩包读取组件配置失败：$LASTEXITCODE" }
& $CMake --build $build --config Release --parallel 2
if ($LASTEXITCODE -ne 0) { throw "压缩包读取组件构建失败：$LASTEXITCODE" }
