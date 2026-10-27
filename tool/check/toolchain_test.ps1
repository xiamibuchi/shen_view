$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../paths.ps1')
$testRoot = Join-Path $NativeBuildRoot ('toolchain-test-' + [guid]::NewGuid().ToString('N'))
$environmentNames = @('PATH', 'FLUTTER_ROOT', 'ProgramFiles', 'ProgramW6432', 'ProgramFiles(x86)')
$saved = @{}
foreach ($name in $environmentNames) { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }

function New-TestTool([string]$RelativePath) {
  $file = Join-Path $testRoot $RelativePath
  [IO.Directory]::CreateDirectory((Split-Path $file)) | Out-Null
  [IO.File]::WriteAllText($file, '')
  return $file
}
function Assert-Tool([string]$Actual, [string]$Expected) {
  if ($Actual -ne $Expected) { throw "工具路径不符：$Actual，预期 $Expected" }
}

try {
  $flutter = New-TestTool 'sdk with spaces/bin/flutter.bat'
  $dart = New-TestTool 'sdk with spaces/bin/dart.bat'
  $pathFlutter = New-TestTool 'on path/flutter.bat'
  $env:FLUTTER_ROOT = Join-Path $testRoot 'sdk with spaces'
  $env:PATH = Join-Path $testRoot 'on path'
  Assert-Tool (Resolve-ShenViewFlutterTool flutter) $pathFlutter
  Assert-Tool (Resolve-ShenViewFlutterTool $flutter) $flutter
  $env:PATH = Join-Path $testRoot 'empty path'
  Assert-Tool (Resolve-ShenViewFlutterTool flutter) $flutter
  Assert-Tool (Resolve-ShenViewFlutterTool dart) $dart

  $env:ProgramFiles = Join-Path $testRoot 'relocated programs'
  $env:ProgramW6432 = $env:ProgramFiles
  [Environment]::SetEnvironmentVariable('ProgramFiles(x86)', $env:ProgramFiles, 'Process')
  $sevenZip = New-TestTool 'relocated programs/7-Zip/7z.exe'
  $magick = New-TestTool 'relocated programs/ImageMagick-custom/magick.exe'
  Assert-Tool (Resolve-ShenViewSevenZip) $sevenZip
  Assert-Tool (Resolve-ShenViewMagick) $magick

  $null = New-TestTool 'portable git/cmd/git.exe'
  $bash = New-TestTool 'portable git/bin/bash.exe'
  $env:PATH = Join-Path $testRoot 'portable git/cmd'
  Assert-Tool (Resolve-ShenViewGitTool 'bin/bash.exe') $bash

  $missing = Join-Path $testRoot 'missing/flutter.bat'
  $rejected = $false
  try { Resolve-ShenViewFlutterTool $missing | Out-Null } catch { $rejected = $true }
  if (-not $rejected) { throw '显式指定的错误路径不应被默认 SDK 替代。' }
  Write-Host '工具路径测试通过：PATH 优先、显式路径、SDK 环境变量、迁移安装目录、便携 Git 与缺失路径。'
} finally {
  foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
  $absolute = [IO.Path]::GetFullPath($testRoot)
  $allowed = [IO.Path]::GetFullPath($NativeBuildRoot) + [IO.Path]::DirectorySeparatorChar
  if (-not $absolute.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) { throw '测试清理路径超出 build。' }
  if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
