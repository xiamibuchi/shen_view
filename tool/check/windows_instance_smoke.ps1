param([string]$ReleaseDirectory = 'build/windows/x64/runner/Release')
. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class InstanceSmokeWindow {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window, uint message, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr window, IntPtr dc, uint flags);
}
'@
$project = $ViewerRoot
$release = [IO.Path]::GetFullPath((Join-Path $project $ReleaseDirectory))
$runRoot = Join-Path $project ('build/instance-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot | Out-Null
# Use a private portable copy; never alter the user's running viewer/config.
Get-ChildItem -LiteralPath $release | Where-Object { $_.Name -notlike 'settings.json*' } | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $runRoot -Recurse
}
$executable = Join-Path $runRoot 'ShenView.exe'
$configPath = Join-Path $runRoot 'settings.json'
$tracked = [Collections.Generic.List[Diagnostics.Process]]::new()
$results = [Collections.Generic.List[string]]::new()
function Assert-True($Value, [string]$Message) {
  if (-not $Value) { throw $Message }
  $results.Add($Message)
}
function Wait-Until([scriptblock]$Condition, [string]$Message) {
  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  do {
    if (& $Condition) { return }
    Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $deadline)
  throw $Message
}
function Launch-Viewer([string]$InputPath = '') {
  $arguments = @{FilePath=$executable; PassThru=$true; WindowStyle='Hidden'}
  if ($InputPath) { $arguments.ArgumentList = @('"' + $InputPath + '"') }
  $process = Start-Process @arguments
  $tracked.Add($process)
  return $process
}
function Wait-Viewer([Diagnostics.Process]$Process) {
  Wait-Until { $Process.Refresh(); -not $Process.HasExited -and $Process.MainWindowHandle -ne 0 -and [InstanceSmokeWindow]::IsWindowVisible($Process.MainWindowHandle) } '等待查看器窗口超时'
}
function Save-Window([Diagnostics.Process]$Process, [string]$Name) {
  $rect = [InstanceSmokeWindow+RECT]::new()
  [void][InstanceSmokeWindow]::GetWindowRect($Process.MainWindowHandle, [ref]$rect)
  $bitmap = [Drawing.Bitmap]::new($rect.Right-$rect.Left, $rect.Bottom-$rect.Top)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $dc = $graphics.GetHdc()
  try { [void][InstanceSmokeWindow]::PrintWindow($Process.MainWindowHandle, $dc, 2) } finally { $graphics.ReleaseHdc($dc) }
  try { $bitmap.Save((Join-Path $runRoot $Name), [Drawing.Imaging.ImageFormat]::Png) } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
function Set-Mode([string]$Mode) {
  # Edit only this isolated fixture while its viewer is idle.
  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  $config.settings | Add-Member -NotePropertyName instanceMode -NotePropertyValue $Mode -Force
  [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 30))
}
try {
  [IO.File]::WriteAllText($configPath, '{"settings":{"localeCode":"zh","instanceMode":"singleProcess","openRecentOnNewWindow":true,"watchFolderChanges":false}}')
  $imagePath = Join-Path $runRoot '中文 image.png'
  $bitmap = [Drawing.Bitmap]::new(64,64)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $graphics.Clear([Drawing.Color]::CornflowerBlue)
  $bitmap.Save($imagePath, [Drawing.Imaging.ImageFormat]::Png)
  $graphics.Dispose(); $bitmap.Dispose()
  $first = Launch-Viewer
  Wait-Viewer $first
  $second = Launch-Viewer $imagePath
  Assert-True ($second.WaitForExit(20000) -and $second.ExitCode -eq 0) '单进程重复启动完成转发并退出'
  Wait-Until { ((Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).session.recentFile) -eq $imagePath } '文件请求未交给已有窗口'
  Assert-True (-not $first.HasExited) '已有窗口接收中文空格路径后保持运行'
  [void][InstanceSmokeWindow]::ShowWindow($first.MainWindowHandle, 6)
  $third = Launch-Viewer
  Assert-True ($third.WaitForExit(20000) -and $third.ExitCode -eq 0) '单进程空请求完成转发并退出'
  Wait-Until { -not [InstanceSmokeWindow]::IsIconic($first.MainWindowHandle) } '最小化窗口未恢复'
  Assert-True (-not [InstanceSmokeWindow]::IsIconic($first.MainWindowHandle)) '重复启动恢复最小化窗口'
  Wait-Until {
    Save-Window $first 'single-process.png'
    $capture = [Drawing.Bitmap]::new((Join-Path $runRoot 'single-process.png'))
    try {
      $pixel = $capture.GetPixel([int]($capture.Width/2), [int]($capture.Height/2))
      return ($pixel.R -eq 100 -and $pixel.G -eq 149 -and $pixel.B -eq 237)
    } finally { $capture.Dispose() }
  } '转发后主图像素未就绪'
  Assert-True $true '转发后主图像素与测试图片一致'
  Set-Mode 'multiProcess'
  $fourth = Launch-Viewer $imagePath
  Wait-Viewer $fourth
  Assert-True ($first.Id -ne $fourth.Id -and -not $first.HasExited) '多进程启动创建独立窗口'
  [void][InstanceSmokeWindow]::PostMessage($first.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
  Assert-True ($first.WaitForExit(20000)) '关闭第一个窗口正常退出'
  Assert-True (-not $fourth.HasExited) '关闭一个实例不影响另一个实例'
  Set-Mode 'singleProcess'
  $fifth = Launch-Viewer
  Assert-True ($fifth.WaitForExit(20000) -and $fifth.ExitCode -eq 0) '切回单进程后复用存活窗口'
  Save-Window $fourth 'surviving-window.png'
  $fourth.Kill(); $fourth.WaitForExit()
  $sixth = Launch-Viewer
  Wait-Viewer $sixth
  Assert-True (-not $sixth.HasExited) '实例强退后可以重新启动'
  Save-Window $sixth 'recovered-window.png'
  $results | ForEach-Object { Write-Output ('PASS: ' + $_) }
  Write-Output ('Artifacts: ' + $runRoot)
} finally {
  foreach ($process in $tracked) {
    $process.Refresh()
    if (-not $process.HasExited) {
      [void][InstanceSmokeWindow]::PostMessage($process.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
      if (-not $process.WaitForExit(5000)) { $process.Kill(); $process.WaitForExit() }
    }
  }
}
