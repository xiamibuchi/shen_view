[CmdletBinding()]
param([Parameter(Mandatory)][string]$InstallRoot,[Parameter(Mandatory)][string]$OutputDirectory)

. (Join-Path $PSScriptRoot '../paths.ps1')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$InstallRoot=(Resolve-Path -LiteralPath $InstallRoot).Path
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$results=[Collections.Generic.List[object]]::new()
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Invoke-Codec([string]$Relative,[string[]]$Arguments,[string]$Name,[string]$InputText=''){
  $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $InstallRoot $Relative))
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WorkingDirectory=$OutputDirectory
  $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
  $info.Arguments=($Arguments | ForEach-Object {'"'+$_+'"'}) -join ' '
  $info.EnvironmentVariables['PATH']=Join-Path $env:SystemRoot 'System32'
  $info.EnvironmentVariables['MAGICK_CONFIGURE_PATH']=Split-Path $info.FileName
  $info.EnvironmentVariables['MAGICK_CODER_MODULE_PATH']=Join-Path (Split-Path $info.FileName) 'modules/coders'
  $info.EnvironmentVariables['MAGICK_FILTER_MODULE_PATH']=Join-Path (Split-Path $info.FileName) 'modules/filters'
  $process=[Diagnostics.Process]::new();$process.StartInfo=$info
  $output=Join-Path $OutputDirectory ($Name+'.bin')
  try{
    [void]$process.Start()
    $stream=[IO.File]::Create($output)
    try{
      $copy=$process.StandardOutput.BaseStream.CopyToAsync($stream)
      $errors=$process.StandardError.ReadToEndAsync()
      if($InputText){$process.StandardInput.Write($InputText)}
      $process.StandardInput.Close()
      if(-not $process.WaitForExit(45000)){$process.Kill();throw ('组件超时: '+$Relative)}
      [void]$copy.GetAwaiter().GetResult()
      $errorText=$errors.GetAwaiter().GetResult()
      Assert ($process.ExitCode-eq0) ('组件运行失败: '+$Relative+' '+$errorText)
      $results.Add(@{name=$Name;executable=$info.FileName;exitCode=$process.ExitCode})
    }finally{$stream.Dispose()}
  }finally{$process.Dispose()}
  return $output
}
foreach($name in @('flutter_windows.dll','printing_plugin.dll','pdfium.dll','flutter_inappwebview_windows_plugin.dll','WebView2Loader.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')){
  Assert (Test-Path (Join-Path $InstallRoot $name)) ('核心启动依赖缺失: '+$name)
}
foreach($directory in @('codecs','codecs/archive','codecs/imagemagick')){
  foreach($name in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')){
    Assert (Test-Path (Join-Path $InstallRoot ($directory+'/'+$name))) ('子进程运行库缺失: '+$directory+'/'+$name)
  }
}
foreach($name in @('magick.exe','7z.dll','viewer_archive.exe','viewer_heif_gainmap.exe','CORE_RL_heif_.dll')){
  Assert (-not(Test-Path (Join-Path $InstallRoot ('codecs/'+$name)))) ('旧平铺组件仍残留: '+$name)
}
$fixtures=Join-Path $ViewerRoot 'testdata/formats'
foreach($fixture in @(
  @{name='raw_nikon_d2h.nef';model='D2H';date='2005:09:24 13:23:28'},
  @{name='raw_sony_a7s.arw';model='ILCE-7S';date='2017:07:13 16:58:28'}
)){
  $output=Invoke-Codec 'codecs/viewer_raw.exe' @('info',(Join-Path $fixtures $fixture.name)) ('metadata-'+$fixture.name)
  $metadata=Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
  Assert ($metadata.model-eq$fixture.model) ('RAW 相机型号不匹配: '+$fixture.name)
  Assert ($null-ne$metadata.PSObject.Properties['dateTimeOriginal']) ('RAW 拍摄时间缺失: '+$fixture.name)
  Assert ($metadata.dateTimeOriginal-eq$fixture.date) ('RAW 拍摄时间缺失或不匹配: '+$fixture.name)
}
foreach($extension in @('dds','psd','jxl','heif')){
  $source=Join-Path $fixtures ('format_static.'+$extension)
  if($extension-eq'heif'){$source=Join-Path $fixtures 'format_alpha.heif'}
  $output=Invoke-Codec 'codecs/imagemagick/magick.exe' @(($source+'[0]'),'-resize','64x64','png:-') ('decode-'+$extension)
  $bytes=[IO.File]::ReadAllBytes($output)
  Assert ($bytes.Length-gt24 -and ($bytes[0..7]-join ',')-eq '137,80,78,71,13,10,26,10') ('未产生有效 PNG: '+$extension)
}
$heif=Join-Path $fixtures 'hdr_gain_map.heic'
$output=Invoke-Codec 'codecs/imagemagick/viewer_heif_gainmap.exe' @('decode',$heif) 'heif-gain-map'
Assert ((Get-Item $output).Length-gt64) 'HEIF Gain Map 没有产生像素数据。'
$archive=Join-Path $fixtures 'format_comic.cbz'
$hex=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($archive)).Replace('-','')
$open="open"+[char]9+$hex+[char]9+'-'+[char]9+'2048'+[char]9+'65536'+[char]10
$output=Invoke-Codec 'codecs/archive/viewer_archive.exe' @() 'archive-index' $open
$events=@([IO.File]::ReadAllLines($output) | ForEach-Object {$_ | ConvertFrom-Json})
Assert (@($events | Where-Object {$_.event-eq'error'}).Count-eq0) '压缩包索引报错。'
$entry=$events | Where-Object {$_.event-eq'entry' -and -not $_.directory} | Select-Object -First 1
Assert ($null-ne$entry) '压缩包没有读到图片条目。'
$extracted=Join-Path $OutputDirectory 'archive-entry.bin'
$destination=[BitConverter]::ToString([Text.Encoding]::UTF8.GetBytes($extracted)).Replace('-','')
$read='read'+[char]9+$entry.index+[char]9+$destination+[char]9+'33554432'+[char]9+'134217728'+[char]10
$output=Invoke-Codec 'codecs/archive/viewer_archive.exe' @() 'archive-extract' ($open+$read)
Assert ((Get-Item $extracted).Length-eq$entry.size) '压缩包提取大小与索引不一致。'
@{passed=$true;root=$InstallRoot;isolatedPath=$true;results=$results} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'codec-results.json') -Encoding utf8
Write-Output ('PASS: '+$OutputDirectory)
