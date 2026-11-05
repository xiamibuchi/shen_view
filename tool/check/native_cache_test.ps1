param([switch]$Probe,[string]$ProbeRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../build/native_cache.ps1')
if ($Probe) { Get-NativeInputKey $ProbeRoot @('bin','licenses') 'compiler-1'; return }
$root = Join-Path ([IO.Path]::GetTempPath()) ('shenview-cache-test-' + [guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition) { if (-not $Condition) { throw 'Native cache assertion failed' } }
try {
  New-Item -ItemType Directory -Path (Join-Path $root 'bin'),(Join-Path $root 'licenses') -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $root 'bin/codec.exe'), 'test binary')
  [IO.File]::WriteAllText((Join-Path $root 'licenses/LICENSE'), 'test license')
  foreach ($name in @('a_b','a-b','ab','AB')) { [IO.File]::WriteAllText((Join-Path $root ('bin/' + $name)), $name) }
  $dirs = @('bin','licenses')
  $required = @('bin/codec.exe','licenses/LICENSE')
  $key = Get-NativeInputKey $root $dirs 'compiler-1'
  foreach ($shell in @(Get-Command powershell.exe,pwsh.exe -ErrorAction SilentlyContinue)) {
    $other = & $shell.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Probe -ProbeRoot $root
    Assert ($LASTEXITCODE -eq 0 -and $key -ceq $other)
  }
  Assert ($key -eq (Get-NativeInputKey $root $dirs 'compiler-1'))
  Assert ($key -ne (Get-NativeInputKey $root $dirs 'compiler-2'))
  Assert (-not (Test-NativeCacheManifest $root $key $dirs $required))
  Write-NativeCacheManifest $root $key $dirs
  Assert (Test-NativeCacheManifest $root $key $dirs $required)
  Assert (-not (Test-NativeCacheManifest $root 'different-key' $dirs $required))
  [IO.File]::WriteAllText((Join-Path $root 'bin/codec.exe'), 'changed binary')
  Assert (-not (Test-NativeCacheManifest $root $key $dirs $required))
  Assert ($key -ne (Get-NativeInputKey $root $dirs 'compiler-1'))
  Write-NativeCacheManifest $root $key $dirs
  Assert (Test-NativeCacheManifest $root $key $dirs $required)
  [IO.File]::WriteAllText((Join-Path $root 'bin/extra.dll'), 'unexpected')
  Assert (-not (Test-NativeCacheManifest $root $key $dirs $required))
  Remove-Item -LiteralPath (Join-Path $root 'bin/extra.dll')
  Remove-Item -LiteralPath (Join-Path $root 'licenses/LICENSE')
  Assert (-not (Test-NativeCacheManifest $root $key $dirs $required))
  Write-Output 'PASS: native cache keys, corruption, missing files, extra files and toolchain invalidation'
} finally {
  $absolute = [IO.Path]::GetFullPath($root)
  $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('/','\') + [IO.Path]::DirectorySeparatorChar
  if (-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $absolute -Leaf) -notlike 'shenview-cache-test-*') { throw 'Invalid test cleanup path' }
  Remove-Item -LiteralPath $absolute -Recurse -Force
}
