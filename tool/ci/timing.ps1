function Measure-CiStage([string]$Name, [scriptblock]$Action) {
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $result = 'failure'
  Write-Host ('::group::' + $Name)
  try {
    & $Action
    $result = 'success'
  } finally {
    $watch.Stop()
    $record = @{name=$Name; seconds=[math]::Round($watch.Elapsed.TotalSeconds, 2); result=$result}
    $record | ConvertTo-Json -Compress | Add-Content -LiteralPath $CiTimingPath -Encoding UTF8
    Write-Host ('::endgroup::')
    Write-Host ('{0}: {1}s ({2})' -f $Name,$record.seconds,$result)
    if ($env:GITHUB_STEP_SUMMARY) {
      '- {0}: {1}s ({2})' -f $Name,$record.seconds,$result | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding UTF8
    }
  }
}
