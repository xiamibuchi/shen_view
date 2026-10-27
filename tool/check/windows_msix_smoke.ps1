[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReleaseDirectory,[string]$WindowsSdkBin = '')

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$developer = Get-ItemPropertyValue -LiteralPath 'HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
if ($developer -ne 1) { throw 'MSIX 开发注册验证需要系统已开启开发者模式；脚本不会修改系统策略。' }
$externalData = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ShenView/MSIX'))
if (Test-Path -LiteralPath $externalData) { throw 'MSIX 外置数据目录已存在；为保护已有数据，请在干净测试账号运行。' }
if (-not $WindowsSdkBin) {
  $sdk = Get-ChildItem -LiteralPath (Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) 'Windows Kits/10/bin') -Directory |
    Where-Object { $_.Name -match '^10[.]0[.]\d+[.]0$' } | Sort-Object { [version]$_.Name } -Descending |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'x64/makeappx.exe') } | Select-Object -First 1
  if (-not $sdk) { throw '未找到 Windows SDK makeappx.exe。' }
  $WindowsSdkBin = Join-Path $sdk.FullName 'x64'
}
$package = Get-ChildItem -LiteralPath $ReleaseDirectory -Filter '*.msix' | Select-Object -First 1
if (-not $package) { throw '发布目录没有 MSIX。' }
$work = Join-Path $RepositoryRoot ('build/packaging/msix-smoke/' + [guid]::NewGuid().ToString('N'))
$unpacked = Join-Path $work 'package'
[IO.Directory]::CreateDirectory($work) | Out-Null
& (Join-Path $WindowsSdkBin 'makeappx.exe') unpack /p $package.FullName /d $unpacked /o > (Join-Path $work 'unpack.log')
if ($LASTEXITCODE -ne 0) { throw 'MSIX 解包失败，见 unpack.log。' }
$manifestPath = Join-Path $unpacked 'AppxManifest.xml'
[xml]$xml = Get-Content -LiteralPath $manifestPath -Raw
$name = 'ShenView.Test.' + [guid]::NewGuid().ToString('N')
# A temporary family keeps validation registration separate from installed copies.
$xml.Package.Identity.Name = $name
$xml.Save($manifestPath)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
[ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IDistributionActivation {
  [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string app,[MarshalAs(UnmanagedType.LPWStr)] string args,uint options,out uint pid);
  [PreserveSig] int ActivateForFile(IntPtr app,IntPtr items,IntPtr verb,out uint pid);
  [PreserveSig] int ActivateForProtocol(IntPtr app,IntPtr items,out uint pid);
}
[ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")] class DistributionActivation {}
public static class MsixWindow {
  [StructLayout(LayoutKind.Sequential)] public struct Rect {public int Left,Top,Right,Bottom;}
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window,out Rect rect);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr window,uint message,IntPtr w,IntPtr l);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern int GetPackageFamilyName(IntPtr process,ref uint length,StringBuilder name);
  public static uint Activate(string app,string args) {
    var manager=(IDistributionActivation)new DistributionActivation();
    try { uint pid; Marshal.ThrowExceptionForHR(manager.ActivateApplication(app,args,0,out pid)); return pid; }
    finally { Marshal.ReleaseComObject(manager); }
  }
}
'@
$probePath = Join-Path $work 'msix-probe.png'
$probe = [Drawing.Bitmap]::new(256,256); $paint = [Drawing.Graphics]::FromImage($probe)
try { $paint.Clear([Drawing.Color]::CornflowerBlue); $probe.Save($probePath,[Drawing.Imaging.ImageFormat]::Png) } finally { $paint.Dispose(); $probe.Dispose() }
$app = $null
$registered = $null
$results = [Collections.Generic.List[string]]::new()
try {
  Add-AppxPackage -Register $manifestPath -ErrorAction Stop
  $registered = Get-AppxPackage -Name $name
  if (-not $registered) { throw 'MSIX 开发注册后未发现临时包身份。' }
  $results.Add('从最终 MSIX 解包并以隔离身份完成开发注册')
  $initialVersion = [version]$registered.Version
  $nextVersion = [version]::new($initialVersion.Major,$initialVersion.Minor,$initialVersion.Build,$initialVersion.Revision+1)
  $xml.Package.Identity.Version = $nextVersion.ToString()
  $xml.Save($manifestPath)
  Add-AppxPackage -Register $manifestPath -ErrorAction Stop
  $registered = Get-AppxPackage -Name $name
  if ([version]$registered.Version -ne $nextVersion) { throw '开发注册升级未切换版本。' }
  $results.Add('同一临时包身份更新版本并保留包家族')
  $processId = [MsixWindow]::Activate(($registered.PackageFamilyName+'!ShenView'),('-- "'+$probePath+'"'))
  $app = Get-Process -Id $processId
  $length = [uint32]0
  [void][MsixWindow]::GetPackageFamilyName($app.Handle,[ref]$length,$null)
  $family = [Text.StringBuilder]::new([int]$length)
  if ([MsixWindow]::GetPackageFamilyName($app.Handle,[ref]$length,$family) -ne 0 -or $family.ToString() -ne $registered.PackageFamilyName) { throw '启动进程没有预期 MSIX 包身份。' }
  $results.Add('通过 Windows 包激活入口启动，进程持有正确 MSIX 身份')
  $rendered = $false
  for ($attempt=0; $attempt -lt 120; $attempt++) {
    Start-Sleep -Milliseconds 150; $app.Refresh()
    if ($app.HasExited) { throw 'MSIX 应用提前退出。' }
    if ($app.MainWindowHandle -eq [IntPtr]::Zero) { continue }
    [void][MsixWindow]::SetForegroundWindow($app.MainWindowHandle)
    $bounds = [MsixWindow+Rect]::new(); [void][MsixWindow]::GetWindowRect($app.MainWindowHandle,[ref]$bounds)
    $capture = [Drawing.Bitmap]::new(($bounds.Right-$bounds.Left),($bounds.Bottom-$bounds.Top))
    $graphics = [Drawing.Graphics]::FromImage($capture)
    try {
      $graphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$capture.Size)
      $pixel = $capture.GetPixel([int]($capture.Width/2),[int]($capture.Height/2))
      if ([Math]::Abs($pixel.R-100) -le 3 -and [Math]::Abs($pixel.G-149) -le 3 -and [Math]::Abs($pixel.B-237) -le 3) {
        $capture.Save((Join-Path $work 'msix-opened-image.png'),[Drawing.Imaging.ImageFormat]::Png); $rendered=$true; break
      }
    } finally { $graphics.Dispose(); $capture.Dispose() }
  }
  if (-not $rendered) { throw 'MSIX 已启动，但未实际显示验证图片。' }
  $results.Add('MSIX 包内应用实际显示图片并通过像素检查')
  [void][MsixWindow]::PostMessage($app.MainWindowHandle,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
  if (-not $app.WaitForExit(10000)) { throw 'MSIX 应用未正常关闭。' }
  Remove-AppxPackage -Package $registered.PackageFullName -ErrorAction Stop
  $registered = $null
  if (Get-AppxPackage -Name $name) { throw 'MSIX 临时身份未卸载。' }
  $results.Add('Windows 卸载临时包并移除注册')
} finally {
  if ($app -and -not $app.HasExited) {
    [void][MsixWindow]::PostMessage($app.MainWindowHandle,0x10,[IntPtr]::Zero,[IntPtr]::Zero)
    if (-not $app.WaitForExit(10000)) { throw 'MSIX 验证窗口仍在运行，保留临时注册供检查。' }
  }
  if ($registered) { Remove-AppxPackage -Package $registered.PackageFullName -ErrorAction Stop }
  # Development registration can leave LocalAppData unvirtualized on newer Windows.
  if (Test-Path -LiteralPath $externalData) {
    $dataItem = Get-Item -LiteralPath $externalData
    $expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ShenView/MSIX'))
    $destination = [IO.Path]::GetFullPath((Join-Path $work 'user-data-evidence'))
    if ($dataItem.FullName -ne $expected -or ($dataItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      -not $destination.StartsWith($work + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'MSIX 验证数据路径异常，保留原处。' }
    Move-Item -LiteralPath $externalData -Destination $destination
  }
}
@{passed=$true;package=$package.FullName;work=$work;identity=$name;registrationMode='developer';trustedSignedInstallTested=$false;cases=@($results)} |
  ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $work 'results.json') -Encoding UTF8
Write-Output $work
