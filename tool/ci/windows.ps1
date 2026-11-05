[CmdletBinding()]
param(
  [string]$Flutter = 'flutter',
  [ValidateSet('All','Prepare','Build','Test','Package')][string]$Phase = 'All',
  [switch]$StaticChecked
)
. (Join-Path $PSScriptRoot '../paths.ps1')
. (Join-Path $PSScriptRoot 'prepare.ps1')
. (Join-Path $PSScriptRoot 'timing.ps1')
$ErrorActionPreference = 'Stop'
$Flutter = Resolve-ShenViewFlutterTool $Flutter
$CiTimingPath = Join-Path $ArtifactRoot 'ci/windows-timings.jsonl'
New-Item -ItemType Directory -Path (Split-Path $CiTimingPath) -Force | Out-Null
if ($Phase -in @('All','Prepare')) { [IO.File]::WriteAllText($CiTimingPath, '') }
Push-Location $ViewerRoot
try {
  if ($Phase -in @('All','Prepare')) {
    Measure-CiStage 'Dependencies and generated files' { Invoke-CiPreparation $Flutter }
  }
  if ($Phase -in @('All','Build')) {
    Measure-CiStage 'Windows Release build' { Run $Flutter @('build','windows','--release','--no-pub') }
    Measure-CiStage 'Native codecs and layout' {
      & (Join-Path $PSScriptRoot '../build/build_hdr_codecs.ps1')
      & (Join-Path $PSScriptRoot '../build/package_windows_codecs.ps1')
    }
  }
  if ($Phase -in @('All','Test')) {
    # Real decoder tests must not silently skip on a clean runner.
    $env:SHENVIEW_MAGICK = Join-Path $ViewerRoot 'build/windows/x64/runner/Release/codecs/imagemagick/magick.exe'
    if (-not (Test-Path -LiteralPath $env:SHENVIEW_MAGICK)) { throw 'Bundled ImageMagick is missing' }
    Measure-CiStage 'HDR video smoke' { Run node @((Join-Path $PSScriptRoot '../check/hdr_video_smoke.cjs')) }
    Measure-CiStage 'Flutter checks' {
      $mode = if ($StaticChecked) { 'Test' } else { 'All' }
      & (Join-Path $PSScriptRoot '../check/check.ps1') -Flutter $Flutter -Mode $mode
      if ($LASTEXITCODE) { throw 'Flutter checks failed' }
    }
    Measure-CiStage 'Native queue tests' {
      $cmake = Resolve-ShenViewCMake
      $ctest = Join-Path (Split-Path $cmake) 'ctest.exe'
      Run $cmake @('-S',(Join-Path $RepositoryRoot 'native/tests'),'-B',(Join-Path $NativeBuildRoot 'native-tests'),'-G',(Resolve-ShenViewVisualStudioGenerator),'-A','x64')
      Run $cmake @('--build',(Join-Path $NativeBuildRoot 'native-tests'),'--config','Release','--parallel','2')
      Run $ctest @('--test-dir',(Join-Path $NativeBuildRoot 'native-tests'),'-C','Release','--output-on-failure')
    }
  }
  if ($Phase -in @('All','Package')) {
    Measure-CiStage 'Portable package and smoke' {
      & (Join-Path $PSScriptRoot '../release/package_windows_portable.ps1') -Flutter $Flutter -SkipBuild -SkipCodecs
      $line = Get-Content pubspec.yaml | Where-Object { $_.StartsWith('version: ') }
      $parts = $line.Substring(9).Trim().Split('+')
      if ($parts.Count -ne 2) { throw 'Cannot read release version' }
      $output = Join-Path $ArtifactRoot ('releases/' + $parts[0] + '.' + $parts[1] + '/windows-x64/portable-ci')
      & (Join-Path $PSScriptRoot '../check/windows_portable_smoke.ps1') -ReleaseDirectory $output
    }
  }
  Run git @('diff','--exit-code')
} finally { Pop-Location }