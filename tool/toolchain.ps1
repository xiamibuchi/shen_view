function Resolve-ShenViewTool {
  param([string]$Command, [string[]]$Candidates = @(), [switch]$Optional)
  if ([IO.Path]::IsPathRooted($Command) -or $Command.Contains('/') -or $Command.Contains([char]92)) {
    $Candidates = @()
  }
  foreach ($candidate in @($Command) + $Candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    $found = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.Source }
  }
  if ($Optional) { return $null }
  throw "未找到工具 $Command，请将其加入 PATH 或通过脚本参数指定路径。"
}

function Resolve-ShenViewFlutterTool([string]$Command) {
  $name = [IO.Path]::GetFileNameWithoutExtension($Command)
  $candidates = @()
  if ($name -in @('flutter', 'dart')) {
    if ($env:FLUTTER_ROOT) { $candidates += Join-Path $env:FLUTTER_ROOT "bin/$name.bat" }
    if ($name -eq 'dart') {
      $flutter = Resolve-ShenViewTool flutter -Optional
      if ($flutter) { $candidates += Join-Path (Split-Path $flutter) 'dart.bat' }
    }
  }
  Resolve-ShenViewTool $Command -Candidates $candidates
}

function Get-ShenViewProgramDirectories {
  @($env:ProgramW6432, $env:ProgramFiles, [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) |
    Where-Object { $_ } | Select-Object -Unique
}

function Resolve-ShenViewSevenZip([string]$Command = '7z.exe') {
  $candidates = @(Get-ShenViewProgramDirectories | ForEach-Object { Join-Path $_ '7-Zip/7z.exe' })
  Resolve-ShenViewTool $Command -Candidates $candidates
}

function Resolve-ShenViewMagick([string]$Command = 'magick.exe') {
  $candidates = @(foreach ($directory in Get-ShenViewProgramDirectories) {
    Get-ChildItem -LiteralPath $directory -Filter 'ImageMagick-*' -Directory -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'magick.exe' }
  })
  Resolve-ShenViewTool $Command -Candidates $candidates
}

function Resolve-ShenViewGitTool([string]$RelativePath, [switch]$Optional) {
  $candidates = @()
  $git = Resolve-ShenViewTool git -Optional
  if ($git) {
    $directory = Split-Path $git
    foreach ($parent in @($directory, (Split-Path $directory))) {
      $candidates += Join-Path $parent $RelativePath
    }
  }
  $candidates += @(Get-ShenViewProgramDirectories | ForEach-Object { Join-Path $_ "Git/$RelativePath" })
  # Prefer Git's Bash to Windows' WSL launcher with the same executable name.
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
  }
  Resolve-ShenViewTool ([IO.Path]::GetFileName($RelativePath)) -Optional:$Optional
}

function Resolve-ShenViewVsWhere {
  $candidates = @(Get-ShenViewProgramDirectories | ForEach-Object {
    Join-Path $_ 'Microsoft Visual Studio/Installer/vswhere.exe'
  })
  Resolve-ShenViewTool vswhere.exe -Candidates $candidates
}

function Resolve-ShenViewCMake([string]$Command = 'cmake') {
  $found = Resolve-ShenViewTool $Command -Optional
  if ($found) { return $found }
  if ($Command -ne 'cmake') { return Resolve-ShenViewTool $Command }
  $vswhere = Resolve-ShenViewVsWhere
  $installation = & $vswhere -latest -products '*' -property installationPath
  Resolve-ShenViewTool cmake -Candidates @(Join-Path $installation 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')
}

function Resolve-ShenViewVisualStudioGenerator([string]$Generator = '') {
  if ($Generator) { return $Generator }
  $vswhere = Resolve-ShenViewVsWhere
  $version = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion
  if ($LASTEXITCODE -ne 0 -or -not $version) { throw '未找到 Visual Studio C++ 工具链。' }
  switch (([version]$version).Major) {
    17 { return 'Visual Studio 17 2022' }
    18 { return 'Visual Studio 18 2026' }
    default { throw "未配置该 Visual Studio 版本的 CMake generator：$version" }
  }
}
