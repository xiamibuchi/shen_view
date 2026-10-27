param([int]$ProcessId, [int]$X, [int]$Y, [switch]$Secondary, [switch]$HoverOnly)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class TestWindowPointer {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr window, ref Point point);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point point);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr window, uint flags);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
[void][TestWindowPointer]::SetProcessDPIAware()
$window = (Get-Process -Id $ProcessId).MainWindowHandle
if ($window -eq [IntPtr]::Zero) { throw 'Test window is not visible' }
$point = [TestWindowPointer+Point]::new()
$point.X = $X
$point.Y = $Y
if (-not [TestWindowPointer]::ClientToScreen($window, [ref]$point)) { throw 'Cannot locate test window' }
$target = [TestWindowPointer]::GetAncestor([TestWindowPointer]::WindowFromPoint($point), 2)
if ($target -ne $window) { throw 'Test window is covered at the requested click position' }
[void][TestWindowPointer]::SetCursorPos($point.X, $point.Y)
if ($HoverOnly) { exit 0 }
Start-Sleep -Milliseconds 50
$down = if ($Secondary) { 8 } else { 2 }
$up = if ($Secondary) { 16 } else { 4 }
[TestWindowPointer]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
[TestWindowPointer]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
