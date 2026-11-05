$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('shenview-check-test-' + [guid]::NewGuid().ToString('N'))
$previousLog = $env:SHENVIEW_CHECK_TEST_LOG
$previousFailure = $env:SHENVIEW_CHECK_FAIL
function Assert([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
try {
  New-Item -ItemType Directory -Path $root | Out-Null
  $fake = Join-Path $root 'fake_flutter.cmd'
  @('@echo off','echo %*>>"%SHENVIEW_CHECK_TEST_LOG%"',
    'if "%1"=="%SHENVIEW_CHECK_FAIL%" exit /b 3','exit /b 0') | Set-Content -LiteralPath $fake -Encoding ASCII
  $env:SHENVIEW_CHECK_TEST_LOG = Join-Path $root 'calls.txt'
  function Test-Entry([string]$Mode,[string[]]$Expected,[string]$Failure = '') {
    [IO.File]::WriteAllText($env:SHENVIEW_CHECK_TEST_LOG, '')
    $env:SHENVIEW_CHECK_FAIL = $Failure
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'check.ps1'),'-Flutter',$fake)
    if ($Mode -ne 'Default') { $arguments += @('-Mode',$Mode) }
    & powershell.exe @arguments *> (Join-Path $root ($Mode + '.log'))
    $code = $LASTEXITCODE
    $calls = @(Get-Content -LiteralPath $env:SHENVIEW_CHECK_TEST_LOG)
    Assert (($calls -join '|') -ceq ($Expected -join '|')) ('Unexpected checks: ' + ($calls -join ','))
    $expectedCode = if ($Failure) { 1 } else { 0 }
    Assert ($code -eq $expectedCode) ('Unexpected check exit code: ' + $code)
  }
  Test-Entry 'Default' @('pub run custom_lint','analyze','test')
  Test-Entry 'Static' @('pub run custom_lint','analyze')
  Test-Entry 'Test' @('test')
  Test-Entry 'Default' @('pub run custom_lint','analyze','test') 'pub'
  Test-Entry 'Test' @('test') 'test'
  Write-Output 'PASS: default full checks, static/test split and failure propagation'
} finally {
  $env:SHENVIEW_CHECK_TEST_LOG = $previousLog
  $env:SHENVIEW_CHECK_FAIL = $previousFailure
  $absolute = [IO.Path]::GetFullPath($root)
  $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('/','\') + [IO.Path]::DirectorySeparatorChar
  if (-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $absolute -Leaf) -notlike 'shenview-check-test-*') { throw 'Invalid check test cleanup path' }
  Remove-Item -LiteralPath $absolute -Recurse -Force
}
