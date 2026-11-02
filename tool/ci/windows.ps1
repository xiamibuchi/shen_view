[CmdletBinding()]
param([string]$Flutter = 'flutter')

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
$Flutter = Resolve-ShenViewFlutterTool $Flutter
$dart = Join-Path (Split-Path $Flutter) 'dart.bat'
function Run([string]$Program, [string[]]$Arguments) {
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "检查失败：$Program $Arguments ($LASTEXITCODE)" }
}
Push-Location $ViewerRoot
try {
  Run $Flutter @('pub', 'get', '--enforce-lockfile')
  Run $Flutter @('gen-l10n')
  Run $dart @('run', 'tool/generate_license_exclusions.dart')
  # Format the PR's Dart files; analyzer and tests still cover the whole project.
  $base = if ($env:CI_BASE_SHA) { $env:CI_BASE_SHA } else { 'HEAD' }
  $changed = @(& git -C $RepositoryRoot diff --name-only --diff-filter=ACMR $base -- '*.dart')
  if ($LASTEXITCODE -ne 0) { throw '无法读取待检查的 Dart 文件。' }
  $files = @($changed | ForEach-Object { Join-Path $RepositoryRoot $_ } | Where-Object { Test-Path -LiteralPath $_ })
  if ($files.Count) { Run $dart (@('format', '--output=none', '--set-exit-if-changed') + $files) }
  Run git @('diff', '--exit-code', '--', 'lib/l10n', 'lib/src/application/license_exclusions.g.dart', 'pubspec.lock')
  Run $Flutter @('build', 'windows', '--release', '--no-pub')
  & (Join-Path $PSScriptRoot '../build/build_hdr_codecs.ps1')
  & (Join-Path $PSScriptRoot '../build/package_windows_codecs.ps1')
  # Tests must use the packaged decoder rather than silently skipping it on a clean runner.
  $env:SHENVIEW_MAGICK = Join-Path $ViewerRoot 'build/windows/x64/runner/Release/codecs/imagemagick/magick.exe'
  if (-not (Test-Path -LiteralPath $env:SHENVIEW_MAGICK)) { throw 'CI 缺少随包 ImageMagick。' }
  & (Join-Path $PSScriptRoot '../check/check.ps1') -Flutter $Flutter
  if ($LASTEXITCODE -ne 0) { throw '完整检查失败。' }
  Run cmake @('-S', (Join-Path $RepositoryRoot 'native/tests'), '-B', (Join-Path $NativeBuildRoot 'native-tests'), '-G', (Resolve-ShenViewVisualStudioGenerator), '-A', 'x64')
  Run cmake @('--build', (Join-Path $NativeBuildRoot 'native-tests'), '--config', 'Release', '--parallel', '2')
  Run ctest @('--test-dir', (Join-Path $NativeBuildRoot 'native-tests'), '-C', 'Release', '--output-on-failure')
  & (Join-Path $PSScriptRoot '../release/package_windows_portable.ps1') -Flutter $Flutter -SkipBuild -SkipCodecs
  $version = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:s*(d+.d+.d+)+(d+)s*$')
  if (-not $version.Success) { throw '无法读取发布版本。' }
  $output = Join-Path $ArtifactRoot ('releases/' + $version.Groups[1].Value + '.' + $version.Groups[2].Value + '/windows-x64/portable-ci')
  & (Join-Path $PSScriptRoot '../check/windows_portable_smoke.ps1') -ReleaseDirectory $output
  Run git @('diff', '--exit-code')
} finally { Pop-Location }
