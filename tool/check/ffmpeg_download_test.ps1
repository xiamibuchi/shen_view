$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../third_party/ffmpeg/download.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('shenview-download-test-' + [guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition) { if (-not $Condition) { throw 'Download assertion failed' } }
function Invoke-WebRequest {
  [CmdletBinding()]
  param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile, [int]$TimeoutSec)
  $script:attempts++
  Assert ($TimeoutSec -eq 90)
  Assert ($Uri -eq 'https://example.invalid/source.tar.xz')
  if ($script:mode -eq 'network' -and $script:attempts -eq 1) {
    [IO.File]::WriteAllText($OutFile, 'interrupted')
    throw 'Simulated connection reset'
  }
  $content = if ($script:mode -eq 'always-bad' -or ($script:mode -eq 'corrupt' -and $script:attempts -eq 1)) { 'corrupt' } else { 'verified source' }
  [IO.File]::WriteAllText($OutFile, $content)
}
try {
  New-Item -ItemType Directory -Path $root | Out-Null
  $destination = Join-Path $root 'source.tar.xz'
  [IO.File]::WriteAllText($destination, 'verified source')
  $sha = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
  foreach ($mode in @('cached','fresh','network','corrupt','always-bad')) {
    $script:mode = $mode
    $script:attempts = 0
    if ($mode -eq 'fresh') { Remove-Item -LiteralPath $destination }
    elseif ($mode -ne 'cached') { [IO.File]::WriteAllText($destination, 'stale cached source') }
    $failed = $false
    try {
      $result = Get-VerifiedFfmpegDownload -Uri 'https://example.invalid/source.tar.xz' -Sha256 $sha -Destination $destination -RetryDelaySeconds 0
    } catch { $failed = $true }
    $expectedAttempts = switch ($mode) { cached { 0 } fresh { 1 } always-bad { 3 } default { 2 } }
    Assert ($script:attempts -eq $expectedAttempts)
    Assert ($failed -eq ($mode -eq 'always-bad'))
    if (-not $failed) {
      Assert ($result -eq $destination)
      Assert ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $sha)
    } else { Assert ([IO.File]::ReadAllText($destination) -eq 'stale cached source') }
    Assert (@(Get-ChildItem -LiteralPath $root -Filter '*.partial').Count -eq 0)
  }
  Write-Output 'PASS: verified downloads, bounded retries and partial file cleanup'
} finally {
  $absolute = [IO.Path]::GetFullPath($root)
  $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('/','\') + [IO.Path]::DirectorySeparatorChar
  if (-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $absolute -Leaf) -notlike 'shenview-download-test-*') { throw 'Invalid download test cleanup path' }
  Remove-Item -LiteralPath $absolute -Recurse -Force
}
