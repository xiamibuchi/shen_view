param(
  [string]$Executable = 'build/windows/x64/runner/Release/ShenView.exe',
  [string]$InputPath = 'testdata/formats/format_static.png',
  [string]$OutputDirectory = '../../artifacts/windows-smoke',
  [int]$TimeoutSeconds = 15,
  [int]$WaitMilliseconds = 800,
  [ValidateSet('none', 'red', 'visible', 'long')]
  [string]$ExpectedImage = 'none',
  [ValidateSet('window', 'desktop')]
  [string]$CaptureMethod = 'window',
  [switch]$NavigateToLast,
  [switch]$VerifyFocusRetention,
  [switch]$SkipNavigation
)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'

function Resolve-ProjectPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $ViewerRoot $Path))
}

function Wait-MainWindow([Diagnostics.Process]$Process, [int]$Timeout) {
  $deadline = [DateTime]::UtcNow.AddSeconds($Timeout)
  do {
    $Process.Refresh()
    if ($Process.HasExited) {
      throw "应用在创建窗口前退出，退出码：$($Process.ExitCode)"
    }
    if ($Process.MainWindowHandle -ne 0) { return $Process.MainWindowHandle }
    Start-Sleep -Milliseconds 200
  } while ([DateTime]::UtcNow -lt $deadline)
  throw '等待应用窗口超时。'
}

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeWindow {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr CreateWindowEx(uint exStyle, string className, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
  [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int width, int height, uint flags);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint message, UIntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumChildProc callback, IntPtr extra);
  public delegate bool EnumChildProc(IntPtr hWnd, IntPtr extra);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern uint SendInput(uint count, INPUT[] inputs, int size);
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint Type; public KEYBDINPUT Keyboard; }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort Vk; public ushort Scan; public uint Flags; public uint Time; public IntPtr Extra; }
  public const uint INPUT_KEYBOARD = 1;
  public const uint KEYEVENTF_KEYUP = 2;
  public const uint WM_KEYDOWN = 0x0100;
  public const uint WM_KEYUP = 0x0101;
  public const ushort VK_LEFT = 0x25;
  public const ushort VK_RIGHT = 0x27;
  public const ushort VK_F5 = 0x74;
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static string Title(IntPtr hWnd) {
    var text = new System.Text.StringBuilder(256);
    GetWindowText(hWnd, text, text.Capacity);
    return text.ToString();
  }
  public static void Key(ushort key) {
    var inputs = new INPUT[2];
    inputs[0].Type = INPUT_KEYBOARD; inputs[0].Keyboard.Vk = key;
    inputs[1].Type = INPUT_KEYBOARD; inputs[1].Keyboard.Vk = key; inputs[1].Keyboard.Flags = KEYEVENTF_KEYUP;
    SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
  }
  public static void KeyToWindow(IntPtr hWnd, ushort key) {
    var target = IntPtr.Zero;
    EnumChildWindows(hWnd, (child, extra) => {
      target = child;
      return false;
    }, IntPtr.Zero);
    if (target == IntPtr.Zero) target = hWnd;
    PostMessage(target, WM_KEYDOWN, (UIntPtr)key, IntPtr.Zero);
    PostMessage(target, WM_KEYUP, (UIntPtr)key, IntPtr.Zero);
  }
}
'@

$exe = Resolve-ProjectPath $Executable
$input = Resolve-ProjectPath $InputPath
$output = Resolve-ProjectPath $OutputDirectory
New-Item -ItemType Directory -Path $output -Force | Out-Null

$process = $null
$result = [ordered]@{
  executable = $exe
  input = $input
  started = $false
  windowTitle = $null
  remainedAlive = $false
  captureMethod = $CaptureMethod
  screenshots = @()
  imageAssertions = @()
  durationMs = 0
  passed = $false
}
$startedAt = [Diagnostics.Stopwatch]::StartNew()

try {
  $process = Start-Process -FilePath $exe -ArgumentList @($input) -PassThru
  $result.started = $true
  $handle = Wait-MainWindow $process $TimeoutSeconds
  $windowTitle = [NativeWindow]::Title($handle)
  if ([string]::IsNullOrWhiteSpace($windowTitle)) {
    throw "目标窗口标题为空，句柄无效：$handle"
  }
  $result.windowTitle = $windowTitle
  [NativeWindow]::SetForegroundWindow($handle) | Out-Null
  if ($CaptureMethod -eq 'desktop') {
    # Flutter GPU surfaces are not reliably returned by PrintWindow. Keep only
    # this short-lived test window above other windows for real display capture.
    if (-not [NativeWindow]::SetWindowPos($handle, [IntPtr](-1), 0, 0, 0, 0, 0x43)) {
      throw '无法将测试窗口置于前台以采集实际显示画面。'
    }
  }
  Start-Sleep -Milliseconds $WaitMilliseconds

  function Capture-Window([string]$Name) {
    $process.Refresh()
    if ($process.HasExited) {
      throw "应用已退出，无法截图：$Name，退出码：$($process.ExitCode)"
    }
    if ($process.MainWindowHandle -ne 0) {
      $script:handle = $process.MainWindowHandle
    }
    $rect = New-Object NativeWindow+RECT
    if (-not [NativeWindow]::GetWindowRect($script:handle, [ref]$rect)) {
      throw "无法读取窗口区域：$Name"
    }
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -le 0 -or $height -le 0) {
      throw "窗口区域无效：$width x $height"
    }
    $bitmap = New-Object Drawing.Bitmap($width, $height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    if ($CaptureMethod -eq 'desktop') {
      $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
    } else {
      $deviceContext = $graphics.GetHdc()
      $printed = [NativeWindow]::PrintWindow($script:handle, $deviceContext, 2)
      $graphics.ReleaseHdc($deviceContext)
      if (-not $printed) {
        throw "无法按目标窗口句柄采集截图：$Name，窗口标题：$windowTitle"
      }
    }
    $path = Join-Path $output ($Name + '.png')
    $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    $result.screenshots += $path
    return $path
  }

  function Assert-ImageDisplayed([string]$Path, [string]$Expected) {
    if ($Expected -eq 'none') { return }
    $bitmap = New-Object Drawing.Bitmap($Path)
    try {
      $top = [Math]::Min($bitmap.Height - 1, 52)
      $bottom = [Math]::Max($top + 1, $bitmap.Height - 110)
      $sampled = 0
      $matched = 0
      $luminanceSum = 0.0
      $luminanceSquareSum = 0.0
      $background = $bitmap.GetPixel(0, $top)
      $minX = $bitmap.Width
      $minY = $bitmap.Height
      $maxX = -1
      $maxY = -1
      $centerSamples = 0
      $centerLuminanceSum = 0.0
      $centerLuminanceSquareSum = 0.0
      for ($y = $top; $y -lt $bottom; $y += 4) {
        for ($x = 0; $x -lt $bitmap.Width; $x += 4) {
          $pixel = $bitmap.GetPixel($x, $y)
          $sampled++
          $luminance = 0.299 * $pixel.R + 0.587 * $pixel.G + 0.114 * $pixel.B
          $luminanceSum += $luminance
          $luminanceSquareSum += $luminance * $luminance
          if ($Expected -eq 'long' -and
              $x -ge ($bitmap.Width * 0.45) -and
              $x -le ($bitmap.Width * 0.55)) {
            $centerSamples++
            $centerLuminanceSum += $luminance
            $centerLuminanceSquareSum += $luminance * $luminance
          }
          if ($Expected -eq 'long') {
            $distance = [Math]::Abs($pixel.R - $background.R) +
              [Math]::Abs($pixel.G - $background.G) +
              [Math]::Abs($pixel.B - $background.B)
            $centerLeft = $bitmap.Width * 0.35
            $centerRight = $bitmap.Width * 0.65
            if ($distance -ge 24 -and
                $x -ge $centerLeft -and
                $x -le $centerRight) {
              $minX = [Math]::Min($minX, $x)
              $minY = [Math]::Min($minY, $y)
              $maxX = [Math]::Max($maxX, $x)
              $maxY = [Math]::Max($maxY, $y)
            }
          }
          if ($Expected -eq 'red' -and
              $pixel.R -gt 140 -and
              $pixel.R -gt ($pixel.G * 2) -and
              $pixel.R -gt ($pixel.B * 2)) {
            $matched++
          }
        }
      }
      $ratio = if ($sampled -eq 0) { 0 } else { $matched / $sampled }
      $luminanceVariance = if ($sampled -eq 0) {
        0
      } else {
        ($luminanceSquareSum / $sampled) - [Math]::Pow($luminanceSum / $sampled, 2)
      }
      $boundsWidth = $maxX - $minX
      $boundsHeight = $maxY - $minY
      $centerVariance = if ($centerSamples -eq 0) {
        0
      } else {
        ($centerLuminanceSquareSum / $centerSamples) -
          [Math]::Pow($centerLuminanceSum / $centerSamples, 2)
      }
      $passed = switch ($Expected) {
        'red' { $ratio -ge 0.15 }
        'visible' { $luminanceVariance -ge 500 }
        'long' {
          $boundsHeight -ge ($bitmap.Height * 0.75) -and $centerVariance -ge 100
        }
        default { $true }
      }
      $assertion = [ordered]@{
        screenshot = $Path
        expected = $Expected
        sampledPixels = $sampled
        matchedPixels = $matched
        matchRatio = [Math]::Round($ratio, 4)
        luminanceVariance = [Math]::Round($luminanceVariance, 2)
        passed = $passed
      }
      if ($Expected -eq 'long') {
        $assertion.boundsWidth = $boundsWidth
        $assertion.boundsHeight = $boundsHeight
        $assertion.centerVariance = [Math]::Round($centerVariance, 2)
      }
      $result.imageAssertions += $assertion
      if (-not $assertion.passed) {
        throw "主图像素断言失败：$Path，期望 $Expected，匹配比例 $($assertion.matchRatio)。"
      }
    } finally {
      $bitmap.Dispose()
    }
  }

  $initialScreenshot = Capture-Window 'initial'
  Assert-ImageDisplayed $initialScreenshot $ExpectedImage
  if ($VerifyFocusRetention) {
    # Transfer actual OS focus to a temporary off-screen tool window, keeping
    # the viewer unobscured for desktop capture. Never activate another app.
    $focusWindow = [NativeWindow]::CreateWindowEx(0x80, 'STATIC', 'Viewer focus regression', 2415919104, -10000, -10000, 8, 8, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)
    if ($focusWindow -eq [IntPtr]::Zero) { throw '无法创建临时失焦测试窗口。' }
    try {
      [NativeWindow]::SetForegroundWindow($focusWindow) | Out-Null
      Start-Sleep -Milliseconds 500
      if ([NativeWindow]::GetForegroundWindow() -ne $focusWindow) { throw '无法切换到临时窗口以验证失焦行为。' }
      $blurredScreenshot = Capture-Window 'unfocused'
      Assert-ImageDisplayed $blurredScreenshot $ExpectedImage
    } finally {
      [NativeWindow]::DestroyWindow($focusWindow) | Out-Null
      [NativeWindow]::SetForegroundWindow($handle) | Out-Null
    }
    Start-Sleep -Milliseconds 500
    $refocusedScreenshot = Capture-Window 'refocused'
    Assert-ImageDisplayed $refocusedScreenshot $ExpectedImage
    $before = New-Object Drawing.Bitmap($initialScreenshot)
    try {
      foreach ($path in @($blurredScreenshot, $refocusedScreenshot)) {
        $after = New-Object Drawing.Bitmap($path)
        try {
          $sampled = 0
          $changed = 0
          for ($y = [Math]::Max(0, $before.Height - 120); $y -lt ($before.Height - 45); $y += 2) {
            for ($x = 12; $x -lt ($before.Width - 12); $x += 2) {
              $a = $before.GetPixel($x, $y)
              $b = $after.GetPixel($x, $y)
              $sampled++
              if ([Math]::Abs($a.R - $b.R) + [Math]::Abs($a.G - $b.G) + [Math]::Abs($a.B - $b.B) -gt 30) { $changed++ }
            }
          }
          $ratio = $changed / [Math]::Max(1, $sampled)
          $result.imageAssertions += [ordered]@{ screenshot = $path; expected = 'thumbnail-retention'; changedRatio = $ratio; passed = ($ratio -lt 0.02) }
          if ($ratio -ge 0.02) { throw "焦点切换后缩略图区域发生变化：$path，变化比例 $ratio。" }
        } finally { $after.Dispose() }
      }
    } finally { $before.Dispose() }
  }
  if (-not $SkipNavigation) {
    [NativeWindow]::SetForegroundWindow($handle) | Out-Null
    if ($NavigateToLast) {
      for ($step = 0; $step -lt 100; $step++) {
        [NativeWindow]::KeyToWindow($handle, [NativeWindow]::VK_RIGHT)
        Start-Sleep -Milliseconds 30
      }
    } else {
      [NativeWindow]::KeyToWindow($handle, [NativeWindow]::VK_RIGHT)
      Start-Sleep -Milliseconds 100
      [NativeWindow]::KeyToWindow($handle, [NativeWindow]::VK_LEFT)
      Start-Sleep -Milliseconds 100
    }
    [NativeWindow]::KeyToWindow($handle, [NativeWindow]::VK_F5)
    Start-Sleep -Milliseconds 1200
    $reloadedScreenshot = Capture-Window 'after-navigation-reload'
    Assert-ImageDisplayed $reloadedScreenshot $ExpectedImage
  }
  $result.remainedAlive = -not $process.HasExited
  if (-not $result.remainedAlive) {
    throw "应用在快捷键回归后退出，退出码：$($process.ExitCode)"
  }
  $result.passed = $true
} catch {
  $result.error = $_.Exception.Message
  throw
} finally {
  $startedAt.Stop()
  $result.durationMs = $startedAt.ElapsedMilliseconds
  $report = Join-Path $output 'report.json'
  $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $report -Encoding utf8
  if ($process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force
  }
  Write-Output ($result | ConvertTo-Json -Depth 5)
}
