$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../paths.ps1')
. (Join-Path $PSScriptRoot '../release/windows_source_helpers.ps1')
function Reject([scriptblock]$Action) {
  $failed = $false
  try { & $Action | Out-Null } catch { $failed = $true }
  if (-not $failed) { throw 'Expected rejection' }
}
$lock = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'third_party/release-sources.lock.json') -Raw | ConvertFrom-Json
$dependencies = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'third_party/dependencies.lock.json') -Raw | ConvertFrom-Json
$sdk = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'third_party/native-sdk.lock.json') -Raw | ConvertFrom-Json
if (@(Get-ReleaseSourceAssets $lock $dependencies $sdk).Count -ne 4) { throw 'Missing release sources' }
$original = $sdk.components.hdr.sha256
$sdk.components.hdr.sha256 = '0' * 64
Reject { Get-ReleaseSourceAssets $lock $dependencies $sdk }
$sdk.components.hdr.sha256 = $original
$duplicate = $lock.assets[0].id
$lock.assets[0].id = '7zip'
Reject { Get-ReleaseSourceAssets $lock $dependencies $sdk }
$lock.assets[0].id = $duplicate
$manifest = [pscustomobject]@{sourceDirty=$false;sourceCommit='commit';installerType='portable';package='ShenView-0.1.0.1-windows-x64-portable.zip'}
Assert-ReleaseSourceInput $manifest 'commit' $false $manifest.package
Reject { Assert-ReleaseSourceInput $manifest 'another' $false $manifest.package }
Reject { Assert-ReleaseSourceInput $manifest 'commit' $true $manifest.package }
$manifest.sourceDirty = $true
Reject { Assert-ReleaseSourceInput $manifest 'commit' $false $manifest.package }
$manifest.sourceDirty = $false
$manifest.package = '../outside.zip'
Reject { Assert-ReleaseSourceInput $manifest 'commit' $false $manifest.package }

$work = Join-Path $NativeBuildRoot ('release-sources/test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
try {
  $file = Join-Path $work 'source.zip'
  [IO.File]::WriteAllText($file,'source bytes')
  $asset = [pscustomobject]@{id='test';url='https://github.com/example/source/releases/download/1/source.zip';sha256=(Get-FileHash $file).Hash.ToLowerInvariant()}
  if ((Get-ReleaseSourceFile $asset $work) -ne $file) { throw 'Verified cache was not reused' }
  function global:curl.exe {
    $outputIndex = [Array]::IndexOf($args,'--output')
    [IO.File]::WriteAllText($args[$outputIndex + 1],'source bytes')
    $global:LASTEXITCODE = 0
  }
  [IO.File]::WriteAllText($file,'corrupted cache')
  $null = Get-ReleaseSourceFile $asset $work
  if ((Get-FileHash $file).Hash -ne $asset.sha256) { throw 'Corrupt cache was accepted' }
  $asset.sha256 = 'f' * 64
  Reject { Get-ReleaseSourceFile $asset $work }
  Add-Member -InputObject $asset -NotePropertyName bytes -NotePropertyValue 10
  Reject { Get-ReleaseSourceFile $asset $work }
  if (@(Get-ChildItem -LiteralPath $work -Filter '*.partial*').Count) { throw 'Failed download left temporary files' }
  $lf = Join-Path $work 'lf.txt'
  $crlf = Join-Path $work 'crlf.txt'
  [IO.File]::WriteAllText($lf,'a' + [char]10 + 'b')
  [IO.File]::WriteAllText($crlf,'a' + [char]13 + [char]10 + 'b')
  if ((Get-ReleaseSourceTextHash $lf) -ne (Get-ReleaseSourceTextHash $crlf)) { throw 'Source lock identity depends on checkout line endings' }
} finally {
  Remove-Item Function:/curl.exe -ErrorAction SilentlyContinue
  $allowed = [IO.Path]::GetFullPath((Join-Path $NativeBuildRoot 'release-sources')).TrimEnd('/','\') + [IO.Path]::DirectorySeparatorChar
  if (-not [IO.Path]::GetFullPath($work).StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid test cleanup path' }
  Remove-Item -LiteralPath $work -Recurse -Force
}
Write-Host 'PASS: source locks, provenance, verified cache, corruption, partial download and line endings'
