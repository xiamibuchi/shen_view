param(
  [string]$Flutter = ''
)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Flutter)) { $Flutter = 'flutter' }
$flutterPath = Resolve-ShenViewFlutterTool $Flutter
$projectRoot = $ViewerRoot
$checks = @(
  @{ Name = 'custom_lint'; Arguments = @('pub', 'run', 'custom_lint') },
  @{ Name = 'analyze'; Arguments = @('analyze') },
  @{ Name = 'test'; Arguments = @('test') }
)
$results = @()
$totalTime = [Diagnostics.Stopwatch]::StartNew()

Push-Location -LiteralPath $projectRoot
try {
  # Keep these sequential: analyze and custom_lint share analyzer/plugin caches.
  # Run every check even when an earlier one fails, then return a combined result.
  foreach ($check in $checks) {
    Write-Host "`n== $($check.Name) =="
    $arguments = $check.Arguments
    $exitCode = 1
    try {
      & $flutterPath @arguments
      $exitCode = $LASTEXITCODE
    } catch {
      Write-Warning "$($check.Name): $($_.Exception.Message)"
    }
    $results += [pscustomobject]@{
      Check = $check.Name
      Result = $(if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' })
      ExitCode = $exitCode
    }
  }
} finally {
  Pop-Location
}

$results | Format-Table -AutoSize | Out-Host
Write-Host ('Total: {0:N1}s' -f $totalTime.Elapsed.TotalSeconds)
if (@($results | Where-Object ExitCode -ne 0).Count -gt 0) {
  exit 1
}
exit 0
