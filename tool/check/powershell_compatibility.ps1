[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$files = @(& git -C $root ls-files -- '*.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Cannot list PowerShell scripts.' }
foreach ($relative in $files) {
  $path = Join-Path $root $relative
  $bytes = [IO.File]::ReadAllBytes($path)
  # PowerShell 5.1 otherwise uses the machine ANSI code page for non-ASCII text.
  $nonAscii = [Text.Encoding]::UTF8.GetString($bytes) -match '[^\x00-\x7F]'
  if ($nonAscii -and -not ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) {
    throw "UTF-8 BOM required for Windows PowerShell 5.1: $relative"
  }
  $tokens = $null
  $errors = $null
  [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { throw "Invalid PowerShell script: $relative`n$errors" }
}
Write-Host "PowerShell $($PSVersionTable.PSVersion): $($files.Count) scripts passed."
