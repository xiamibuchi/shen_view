param([string]$ReleaseDirectory = 'build/windows/x64/runner/Release')
. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ConfigSmokeWindow {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);
}
'@
$project = $ViewerRoot
$release = [IO.Path]::GetFullPath((Join-Path $project $ReleaseDirectory))
$runRoot = [IO.Path]::GetFullPath((Join-Path $project ('build/config-smoke-' + [Guid]::NewGuid().ToString('N'))))
New-Item -ItemType Directory -Path $runRoot | Out-Null
Get-ChildItem -LiteralPath $release | Where-Object { $_.Name -notlike 'settings.json*' } | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $runRoot -Recurse
}
$executable = Join-Path $runRoot 'ShenView.exe'
$configPath = Join-Path $runRoot 'settings.json'
$instancePath = $configPath + '.instances'
$imagePath = Join-Path $runRoot 'startup.png'
$bitmap = [Drawing.Bitmap]::new(64,64)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([Drawing.Color]::CornflowerBlue)
$bitmap.Save($imagePath, [Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
$valid = '{"settings":{"localeCode":"zh","watchFolderChanges":false}}'
$process = $null
$heldFile = $null

function Close-Viewer {
  if ($null -eq $script:process) { return }
  $script:process.Refresh()
  if (-not $script:process.HasExited) {
    [void][ConfigSmokeWindow]::PostMessage($script:process.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $script:process.WaitForExit(5000)) {
      $script:process.Kill()
      $script:process.WaitForExit()
    }
  }
  $script:process.Dispose()
  $script:process = $null
}

function Clear-Fixture {
  foreach ($target in @($configPath, $instancePath)) {
    $resolved = [IO.Path]::GetFullPath($target)
    if (-not $resolved.StartsWith($runRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw '测试清理路径超出独立测试目录'
    }
    if (Test-Path -LiteralPath $resolved) {
      if (Test-Path -LiteralPath $resolved -PathType Leaf) {
        [IO.File]::SetAttributes($resolved, [IO.FileAttributes]::Normal)
      }
      Remove-Item -LiteralPath $resolved -Recurse -Force
    }
  }
}

function Wait-Image([string]$Name) {
  $deadline = [DateTime]::UtcNow.AddSeconds(25)
  do {
    $script:process.Refresh()
    if ($script:process.HasExited) { throw ($Name + ': 查看器提前退出') }
    $window = $script:process.MainWindowHandle
    if ($window -ne 0) {
      $rect = [ConfigSmokeWindow+RECT]::new()
      [void][ConfigSmokeWindow]::GetWindowRect($window, [ref]$rect)
      if ($rect.Right -gt $rect.Left -and $rect.Bottom -gt $rect.Top) {
        $capture = [Drawing.Bitmap]::new($rect.Right-$rect.Left, $rect.Bottom-$rect.Top)
        $paint = [Drawing.Graphics]::FromImage($capture)
        $dc = $paint.GetHdc()
        try { [void][ConfigSmokeWindow]::PrintWindow($window, $dc, 2) } finally { $paint.ReleaseHdc($dc) }
        try {
          $pixel = $capture.GetPixel([int]($capture.Width/2), [int]($capture.Height/2))
          if ($pixel.R -eq 100 -and $pixel.G -eq 149 -and $pixel.B -eq 237) {
            $capture.Save((Join-Path $runRoot ($Name + '.png')), [Drawing.Imaging.ImageFormat]::Png)
            return
          }
        } finally { $paint.Dispose(); $capture.Dispose() }
      }
    }
    Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $deadline)
  throw ($Name + ': 配置异常时未能正常显示图片')
}

$cases = @(
  @{ Name='missing'; Setup={} },
  @{ Name='malformed'; Setup={ [IO.File]::WriteAllText($configPath, '{"settings":') } },
  @{ Name='non-object'; Setup={ [IO.File]::WriteAllText($configPath, '[1,2,3]') } },
  @{ Name='bad-fields'; Setup={ [IO.File]::WriteAllText($configPath, '{"settings":{"sortOrder":42,"comicPageGap":"bad","shortcutOverrides":[],"localeCode":{},"autoPlay":true},"session":{"recentFolder":42,"recentFile":[],"recentReadingPath":{}},"readingHistory":{"bad":{"mode":42,"scales":true,"entryPath":[]}},"recentOpen":[null,42,{"path":[]}],"recentColors":[42],"windowPlacement":{"width":[]}}') } },
  @{ Name='invalid-utf8'; Setup={ [IO.File]::WriteAllBytes($configPath, [byte[]]@(255,254,0)) } },
  @{ Name='deep-nesting'; Setup={ [IO.File]::WriteAllText($configPath, ('[' * 1000 + ']' * 1000)) } },
  @{ Name='oversized'; Setup={ [IO.File]::WriteAllBytes($configPath, [byte[]]::new(16*1024*1024+1)) } },
  @{ Name='directory'; Setup={ New-Item -ItemType Directory -Path $configPath | Out-Null } },
  @{ Name='locked'; Setup={ [IO.File]::WriteAllText($configPath, $valid); $script:heldFile = [IO.File]::Open($configPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) } },
  @{ Name='read-only'; Setup={ [IO.File]::WriteAllText($configPath, $valid); [IO.File]::SetAttributes($configPath, [IO.FileAttributes]::ReadOnly) } },
  @{ Name='blocked-instance-storage'; Setup={ [IO.File]::WriteAllText($configPath, $valid); [IO.File]::WriteAllText($instancePath, 'occupied') } }
)
try {
  foreach ($case in $cases) {
    Clear-Fixture
    & $case.Setup
    try {
      $process = Start-Process -FilePath $executable -ArgumentList @('"' + $imagePath + '"') -WindowStyle Hidden -PassThru
      Wait-Image $case.Name
      Write-Output ('PASS: ' + $case.Name)
    } finally {
      if ($null -ne $heldFile) { $heldFile.Dispose(); $heldFile = $null }
      Close-Viewer
    }
  }
  Write-Output ('Artifacts: ' + $runRoot)
} finally {
  if ($null -ne $heldFile) { $heldFile.Dispose() }
  Close-Viewer
  if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    [IO.File]::SetAttributes($configPath, [IO.FileAttributes]::Normal)
  }
}
