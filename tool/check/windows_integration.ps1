param(
  [string]$Flutter = 'flutter',
  [string]$OutputDirectory = '',
  [string[]]$TestFiles = @()
)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
$flutterPath = (Resolve-ShenViewFlutterTool $Flutter)
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $ArtifactRoot 'windows-integration' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($output) | Out-Null
$proxy = Join-Path $NativeBuildRoot 'native-tests/Release/raw_helper_trace.exe'
$rawHelper = Join-Path $NativeBuildRoot 'hdr-codecs/bin/viewer_raw.exe'
foreach ($helper in @($proxy, $rawHelper)) {
  if (-not (Test-Path -LiteralPath $helper)) {
    throw "缺少集成测试组件：$helper。请先构建 native/tests 与 HDR helper。"
  }
}
$variables = @('SHENVIEW_RAW', 'RAW_TRACE_HELPER', 'RAW_TRACE_LOG')
$saved = @{}
foreach ($name in $variables) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
Push-Location -LiteralPath $ViewerRoot
try {
  $env:SHENVIEW_RAW = $proxy
  $env:RAW_TRACE_HELPER = $rawHelper
  $env:RAW_TRACE_LOG = Join-Path $output 'raw-helper-trace.log'
  $formats = Join-Path $ViewerRoot 'testdata/formats'
  $svg = Join-Path $ViewerRoot 'testdata/svg'
  $commonArguments = @('-d', 'windows', '--no-pub', '--timeout', '5m',
    "--dart-define=NATIVE_DECODER_FIXTURES=$formats",
    "--dart-define=PHOTO_MEDIA_FIXTURES=$(Join-Path $ViewerRoot 'testdata/photo_media')",
    "--dart-define=SVG_FIXTURES=$svg",
    "--dart-define=SVG_ARTIFACTS=$output/svg")
  $results = @()
  # Flutter desktop caches its log reader within one CLI process. Start a new
  # process per target so a completed runner cannot close the next target's log.
  $targets = @(Get-ChildItem (Join-Path $ViewerRoot 'integration_test') -Filter '*_test.dart' -File | Sort-Object Name)
  foreach ($name in $TestFiles) {
    if ($name -notin $targets.Name) { throw "未知集成测试文件：$name" }
  }
  if ($TestFiles.Count -gt 0) { $targets = @($targets | Where-Object { $_.Name -in $TestFiles }) }
  if ($targets.Count -eq 0) { throw '没有找到 Windows 集成测试' }
  foreach ($target in $targets) {
    Write-Host "=== $($target.Name) ==="
    $errorPreference = $ErrorActionPreference
    try {
      # Windows PowerShell wraps compiler warnings on stderr as NativeCommandError.
      $ErrorActionPreference = 'Continue'
      & $flutterPath test $target.FullName @commonArguments 2>&1 | Tee-Object -FilePath (Join-Path $output "$($target.BaseName).log") -ErrorAction Stop
      $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $errorPreference }
    $results += [pscustomobject]@{ target = $target.Name; exitCode = $exitCode }
  }
  $results | ConvertTo-Json | Set-Content (Join-Path $output 'results.json') -Encoding UTF8
  $failed = @($results | Where-Object { $_.exitCode -ne 0 })
  if ($failed.Count -gt 0) { throw "Windows 集成测试失败：$($failed.target -join ', ')" }
} finally {
  Pop-Location
  foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
}
