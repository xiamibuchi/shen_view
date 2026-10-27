import 'dart:convert';
import 'dart:io';

abstract interface class FolderOrderProvider {
  const FolderOrderProvider();

  /// Returns the order currently exposed by the platform folder view.
  ///
  /// A null result means that the platform has no matching folder view, so
  /// callers should keep the directory enumeration order.
  Future<List<String>?> orderFor(String folderPath);
}

class PlatformFolderOrderProvider extends FolderOrderProvider {
  const PlatformFolderOrderProvider();

  static const _windowsScript = r'''
$source = @'
using System;
using System.Runtime.InteropServices;
public static class FolderViewWindowOrder {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint command);
  public static int ZOrder(IntPtr target) {
    var current = GetForegroundWindow();
    for (var index = 0; current != IntPtr.Zero && index < 4096; index++) {
      if (current == target) return index;
      current = GetWindow(current, 3); // GW_HWNDPREV
    }
    return int.MaxValue;
  }
}
'@
Add-Type $source
$target = [IO.Path]::GetFullPath($env:SHENVIEW_FOLDER)
$shell = New-Object -ComObject Shell.Application
$candidates = @()
foreach ($window in $shell.Windows()) {
  try {
    $location = [Uri]::new([string]$window.LocationURL).LocalPath
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      [IO.Path]::GetFullPath($location), $target)) {
      continue
    }
    $candidates += [pscustomobject]@{
      ZOrder = [FolderViewWindowOrder]::ZOrder([IntPtr]$window.HWND)
      Items = @($window.Document.Folder.Items())
    }
  } catch {
    # Shell windows can disappear while the list is being read.
  }
}
if ($candidates.Count -gt 0) {
  $selected = $candidates | Sort-Object ZOrder | Select-Object -First 1
  foreach ($item in $selected.Items) { [Console]::WriteLine([string]$item.Path) }
}
''';

  @override
  Future<List<String>?> orderFor(String folderPath) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          _windowsScript,
        ],
        environment: {...Platform.environment, 'SHENVIEW_FOLDER': folderPath},
      );
      if (result.exitCode != 0) return null;
      final paths = const LineSplitter()
          .convert(result.stdout.toString())
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
      return paths.isEmpty ? null : paths;
    } on IOException {
      return null;
    }
  }
}
