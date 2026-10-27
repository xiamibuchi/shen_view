param(
  [string]$Flutter = 'flutter',
  [string]$OutputDirectory = 'artifacts/windows-regression',
  [switch]$SkipBuild,
  [switch]$RunIntegration,
  [switch]$SkipSmoke
)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'

function Resolve-ProjectPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function Invoke-Step([string]$Name, [scriptblock]$Command, [string]$LogPath) {
  $startedAt = [Diagnostics.Stopwatch]::StartNew()
  Write-Host "== $Name =="
  try {
    & $Command 2>&1 | Tee-Object -FilePath $LogPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "步骤失败，退出码：$LASTEXITCODE"
    }
    return [ordered]@{ name = $Name; passed = $true; durationMs = $startedAt.ElapsedMilliseconds; log = $LogPath }
  } catch {
    return [ordered]@{ name = $Name; passed = $false; durationMs = $startedAt.ElapsedMilliseconds; log = $LogPath; error = $_.Exception.Message }
  }
}

$project = $ViewerRoot
$flutterPath = (Resolve-ShenViewFlutterTool $Flutter)
$OutputDirectory = if ([IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path $RepositoryRoot $OutputDirectory }
Push-Location -LiteralPath $ViewerRoot
try {
$dartPath = Join-Path (Split-Path $flutterPath) 'dart.bat'
$output = Resolve-ProjectPath $OutputDirectory
$fixture = Join-Path $output 'fixtures'
New-Item -ItemType Directory -Path $output -Force | Out-Null

$results = [System.Collections.Generic.List[object]]::new()
$results.Add((Invoke-Step 'generate fixtures' { & $dartPath run tool/regression_fixtures.dart $fixture } (Join-Path $output '01-fixtures.log')))
$results.Add((Invoke-Step 'custom design lints' { & $flutterPath pub run custom_lint } (Join-Path $output '01-design-lints.log')))
$results.Add((Invoke-Step 'static analysis' { & $flutterPath analyze } (Join-Path $output '02-analyze.log')))
$results.Add((Invoke-Step 'Dart and widget tests' { & $flutterPath test } (Join-Path $output '03-test.log')))

if ($RunIntegration) {
  $env:SHENVIEW_TESTDATA = $fixture
  $integration = Join-Path $PSScriptRoot 'windows_integration.ps1'
  $results.Add((Invoke-Step 'Windows integration tests' { & powershell -ExecutionPolicy Bypass -File $integration -Flutter $flutterPath -OutputDirectory (Join-Path $output 'integration') } (Join-Path $output '04-integration.log')))
}

if (-not $SkipBuild) {
  $results.Add((Invoke-Step 'Windows release build' { & $flutterPath build windows --release --no-pub } (Join-Path $output '05-build.log')))
  $results.Add((Invoke-Step 'package native codecs' { & powershell -ExecutionPolicy Bypass -File ../../tool/build/package_windows_codecs.ps1 } (Join-Path $output '06-codecs.log')))
}

if (-not $SkipSmoke) {
  $smoke = Join-Path $RepositoryRoot 'tool/check/windows_smoke_test.ps1'
  $releaseExecutable = Join-Path $project 'build/windows/x64/runner/Release/ShenView.exe'
  if (-not (Test-Path -LiteralPath $releaseExecutable -PathType Leaf)) {
    $missingReleaseError = '未找到 Release 可执行文件；请先运行完整回归，或显式使用 -SkipSmoke。'
    $results.Add([ordered]@{ name = 'Release smoke test'; passed = $false; durationMs = 0; log = (Join-Path $output '07-smoke.log'); error = $missingReleaseError })
  } else {
    $results.Add((Invoke-Step 'Release smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $fixture 'normal/001-red.png') -ExpectedImage red -OutputDirectory (Join-Path $output 'smoke-normal') } (Join-Path $output '07-smoke.log')))
    $results.Add((Invoke-Step 'Release JXL smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $project 'testdata/formats/format_static.jxl') -ExpectedImage visible -OutputDirectory (Join-Path $output 'smoke-jxl') } (Join-Path $output '07-smoke-jxl.log')))
    $results.Add((Invoke-Step 'Release APNG smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $project 'testdata/formats/format_animated.apng') -ExpectedImage visible -OutputDirectory (Join-Path $output 'smoke-apng') } (Join-Path $output '07-smoke-apng.log')))
    $results.Add((Invoke-Step 'Release AVIF smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $project 'testdata/formats/format_static.avif') -ExpectedImage visible -OutputDirectory (Join-Path $output 'smoke-avif') } (Join-Path $output '07-smoke-avif.log')))
    $results.Add((Invoke-Step 'Release HEIC smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $project 'testdata/formats/format_alpha.heic') -ExpectedImage visible -OutputDirectory (Join-Path $output 'smoke-heic') } (Join-Path $output '07-smoke-heic.log')))
    $results.Add((Invoke-Step 'Release HEIF smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $project 'testdata/formats/format_alpha.heif') -ExpectedImage visible -OutputDirectory (Join-Path $output 'smoke-heif') } (Join-Path $output '07-smoke-heif.log')))
    $results.Add((Invoke-Step 'Release RAW smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $project 'testdata/formats/raw_canon_white_paper.cr2') -ExpectedImage visible -WaitMilliseconds 25000 -SkipNavigation -OutputDirectory (Join-Path $output 'smoke-raw') } (Join-Path $output '09-smoke-raw.log')))
    $results.Add((Invoke-Step 'Release HDR smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $project 'testdata/formats/hdr_gradient.hdr') -ExpectedImage visible -WaitMilliseconds 25000 -SkipNavigation -OutputDirectory (Join-Path $output 'smoke-hdr') } (Join-Path $output '09-smoke-hdr.log')))
    $results.Add((Invoke-Step 'Release EXR smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $project 'testdata/formats/hdr_gradient.exr') -ExpectedImage visible -WaitMilliseconds 25000 -SkipNavigation -OutputDirectory (Join-Path $output 'smoke-exr') } (Join-Path $output '09-smoke-exr.log')))
    $results.Add((Invoke-Step 'Release long-image smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $fixture 'long/001-long.png') -ExpectedImage long -SkipNavigation -OutputDirectory (Join-Path $output 'smoke-long') } (Join-Path $output '08-smoke-long.log')))
    $results.Add((Invoke-Step 'Release CBR smoke test' { & powershell -ExecutionPolicy Bypass -File $smoke -Executable $releaseExecutable -InputPath (Join-Path $project 'testdata/formats/format_comic_rar.cbr') -OutputDirectory (Join-Path $output 'smoke-cbr') } (Join-Path $output '08-smoke-cbr.log')))
  }
}

$report = [ordered]@{
  project = $project
  startedAt = (Get-Date).ToString('o')
  passed = @($results | Where-Object passed -eq $false).Count -eq 0
  steps = @($results)
}
$reportPath = Join-Path $output 'report.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
$report | ConvertTo-Json -Depth 6
if (-not $report.passed) { exit 1 }

} finally { Pop-Location }
