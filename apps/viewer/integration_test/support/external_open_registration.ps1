param(
  [ValidateSet('setup', 'verify', 'cleanup')][string]$Mode,
  [string]$Root,
  [string]$Suffix
)

$ErrorActionPreference = 'Stop'
if ($Suffix -notmatch '^shenview-open-test-[0-9a-f]+$') {
  throw 'Invalid isolated test association'
}
$classes = 'HKCU:\Software\Classes'
$extension = Join-Path $classes ".$Suffix"
$default = "$Suffix.Default"
$selected = "$Suffix.Selected"
$keys = @($extension, (Join-Path $classes $default), (Join-Path $classes $selected))

if ($Mode -eq 'cleanup') {
  foreach ($key in $keys) {
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
  }
  exit
}
if ($Mode -eq 'verify') {
  if ((Get-Item -LiteralPath $extension).GetValue('') -ne $default) {
    throw 'Opening with the selected app changed the default association'
  }
  exit
}

# Only this random test extension is registered; real image associations are untouched.
$receiver = Join-Path $Root 'receive.ps1'
Set-Content -LiteralPath $receiver -Encoding UTF8 -Value @'
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'received.txt'), $args[0], [Text.UTF8Encoding]::new($false))
'@
$shell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$command = '"' + $shell + '" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -File "' + $receiver + '" "%1"'
New-Item -Path $extension -Force | Out-Null
Set-Item -LiteralPath $extension -Value $default
New-Item -Path (Join-Path $extension 'OpenWithProgids') -Force | Out-Null
foreach ($prog in @($default, $selected)) {
  New-ItemProperty -LiteralPath (Join-Path $extension 'OpenWithProgids') -Name $prog -Value '' -PropertyType String -Force | Out-Null
  New-Item -Path (Join-Path $classes "$prog\shell\open\command") -Force | Out-Null
}
Set-Item -LiteralPath (Join-Path $classes "$default\shell\open\command") -Value ('"' + $env:WINDIR + '\System32\cmd.exe" /d /c exit')
Set-Item -LiteralPath (Join-Path $classes "$selected\shell\open\command") -Value $command
