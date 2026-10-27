import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class FileOperationService {
  static const _nativeWindowsChannel = MethodChannel(
    'shenview/explorer_reveal',
  );

  Future<void> reveal(File file) async {
    if (Platform.isWindows) {
      final nativeResult = await _revealWithNativeWindows(file);
      if (nativeResult) return;
      await _launchExplorer(file);
      return;
    }
    final result = Platform.isMacOS
        ? await Process.run('/usr/bin/open', ['-R', file.path])
        : await Process.run('xdg-open', [file.parent.path]);
    if (result.exitCode != 0) {
      throw StateError(result.stderr.toString().trim());
    }
  }

  Future<bool> _revealWithNativeWindows(File file) async {
    try {
      return await _nativeWindowsChannel.invokeMethod<bool>('reveal', {
            'path': file.absolute.path,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _launchExplorer(File file) async {
    final result = await Process.run('explorer.exe', ['/select,${file.path}']);
    if (result.exitCode != 0) {
      throw StateError(result.stderr.toString().trim());
    }
  }

  Future<void> copyFile(File file) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('当前平台没有实现文件复制到系统剪贴板');
    }
    final encoded = base64Url.encode(utf8.encode(file.path));
    final script = r'''
$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:SHENVIEW_COPY_PATH));
Add-Type -AssemblyName System.Windows.Forms;
$list = New-Object System.Collections.Specialized.StringCollection;
$list.Add($path);
[Windows.Forms.Clipboard]::SetFileDropList($list);
''';
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-STA',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ],
      environment: {...Platform.environment, 'SHENVIEW_COPY_PATH': encoded},
    );
    if (result.exitCode != 0) {
      throw StateError(result.stderr.toString().trim());
    }
  }

  Future<void> moveToTrash(File file) async {
    if (Platform.isWindows) {
      final encoded = base64Url.encode(utf8.encode(file.path));
      final script = r'''
$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:SHENVIEW_DELETE_PATH));
Add-Type -AssemblyName Microsoft.VisualBasic;
[Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
  $path,
  [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
  [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
)
''';
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
        environment: {...Platform.environment, 'SHENVIEW_DELETE_PATH': encoded},
      );
      if (result.exitCode != 0) {
        throw StateError(_processErrorMessage(result));
      }
      return;
    }
    if (Platform.isMacOS) {
      final escapedPath = file.path
          .replaceAll(r'\', r'\\')
          .replaceAll('"', r'\"');
      final result = await Process.run('/usr/bin/osascript', [
        '-e',
        'tell application "Finder" to delete POSIX file "$escapedPath"',
      ]);
      if (result.exitCode != 0) {
        throw StateError(_processErrorMessage(result));
      }
      return;
    }
    throw UnsupportedError('当前平台没有实现回收站接口');
  }

  String _processErrorMessage(ProcessResult result) {
    final stderr = result.stderr.toString().trim();
    if (stderr.isNotEmpty) return stderr;
    final stdout = result.stdout.toString().trim();
    if (stdout.isNotEmpty) return stdout;
    return '系统未返回错误信息（退出码：${result.exitCode}）';
  }
}
