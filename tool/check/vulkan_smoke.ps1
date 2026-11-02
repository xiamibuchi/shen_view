[CmdletBinding()]
param([Parameter(Mandatory)][string]$Loader)

$ErrorActionPreference = 'Stop'
$loaderPath = (Resolve-Path -LiteralPath $Loader).Path
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
Write-Host ('Vulkan probe administrator=' + $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ShenViewVulkanProbe {
    [StructLayout(LayoutKind.Sequential)]
    public struct InstanceInfo {
        public uint type;
        public IntPtr next;
        public uint flags;
        public IntPtr application;
        public uint layerCount;
        public IntPtr layers;
        public uint extensionCount;
        public IntPtr extensions;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr LoadLibraryW(string path);
    [DllImport("vulkan-1.dll")]
    public static extern int vkCreateInstance(ref InstanceInfo info, IntPtr allocator, out IntPtr instance);
    [DllImport("vulkan-1.dll")]
    public static extern int vkEnumeratePhysicalDevices(IntPtr instance, ref uint count, IntPtr devices);
    [DllImport("vulkan-1.dll")]
    public static extern void vkDestroyInstance(IntPtr instance, IntPtr allocator);
}
'@
if ([ShenViewVulkanProbe]::LoadLibraryW($loaderPath) -eq [IntPtr]::Zero) {
  throw [ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
}
$info = [ShenViewVulkanProbe+InstanceInfo]::new()
$info.type = 1
$instance = [IntPtr]::Zero
$result = [ShenViewVulkanProbe]::vkCreateInstance([ref]$info, [IntPtr]::Zero, [ref]$instance)
if ($result -ne 0) { throw "vkCreateInstance failed: $result" }
try {
  [uint32]$count = 0
  $result = [ShenViewVulkanProbe]::vkEnumeratePhysicalDevices($instance, [ref]$count, [IntPtr]::Zero)
  if ($result -ne 0 -or $count -eq 0) { throw "No Vulkan device: result=$result count=$count" }
  Write-Host "PASS: Vulkan instance and $count device(s), loader=$loaderPath"
} finally {
  [ShenViewVulkanProbe]::vkDestroyInstance($instance, [IntPtr]::Zero)
}
