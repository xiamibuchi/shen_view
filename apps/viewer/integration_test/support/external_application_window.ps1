param([string]$Name, [int]$ProcessId)
$ErrorActionPreference = 'Stop'
if ($Name) {
  Get-Process -Name $Name -ErrorAction SilentlyContinue | ForEach-Object { $_.Id }
  exit 0
}
$process = Get-Process -Id $ProcessId
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ExternalWindowPointer {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
[void][ExternalWindowPointer]::SetProcessDPIAware()
$window = $process.MainWindowHandle
if ($window -eq [IntPtr]::Zero) { throw 'External test window is not visible' }
$rect = New-Object ExternalWindowPointer+Rect
if (-not [ExternalWindowPointer]::GetWindowRect($window, [ref]$rect)) { throw 'Cannot locate external test window' }
[void][ExternalWindowPointer]::SetForegroundWindow($window)
[void][ExternalWindowPointer]::SetCursorPos($rect.Right - 20, $rect.Top + 20)
Start-Sleep -Milliseconds 300
[ExternalWindowPointer]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
[ExternalWindowPointer]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
if (-not $process.WaitForExit(10000)) { throw 'External test window did not exit' }
