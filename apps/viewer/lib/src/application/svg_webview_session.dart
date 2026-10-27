import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as paths;

import 'decode_request.dart';

/// One live document per viewer window. Thumbnail consumers never acquire it.
/// KeepAlive reattaches the same native view when the current page changes.
class SvgWebViewSession extends ChangeNotifier {
  SvgWebViewSession({this.idleDelay = const Duration(seconds: 15)});
  final Duration idleDelay;
  Object? _owner;
  Timer? _idle;
  InAppWebViewKeepAlive? _keepAlive;
  Future<WebViewEnvironment?>? _environment;
  Future<void> _tail = Future.value();
  bool _disposed = false, _created = false;
  bool owns(Object owner) => !_disposed && identical(_owner, owner);
  InAppWebViewKeepAlive get keepAlive => _keepAlive!;

  bool acquire(Object owner) {
    if (_disposed || (_owner != null && !identical(_owner, owner))) {
      return false;
    }
    _idle?.cancel();
    _owner = owner;
    _keepAlive ??= InAppWebViewKeepAlive();
    return true;
  }

  void created(Object owner) {
    if (owns(owner)) _created = true;
  }

  Future<WebViewEnvironment?> environment() =>
      _environment ??= _createEnvironment();

  Future<WebViewEnvironment?> _createEnvironment() async {
    if (!Platform.isWindows) return null;
    final version = await WebViewEnvironment.getAvailableVersion();
    if (version == null) {
      throw StateError(
        '缺少 WebView2 Runtime，请安装 Microsoft Edge WebView2 Runtime 后重试。',
      );
    }
    final directory = Directory(
      paths.join(
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path,
        'ShenView',
        'WebView2',
      ),
    );
    await directory.create(recursive: true);
    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(userDataFolder: directory.path),
    );
  }

  Future<T> run<T>(Object owner, Future<T> Function() operation) {
    final result = _tail.then((_) async {
      if (!owns(owner)) throw DecodeCancelled();
      return operation();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void release(
    Object owner, {
    bool discard = false,
    Future<void>? afterDetach,
  }) {
    if (!owns(owner)) return;
    _owner = null;
    _idle?.cancel();
    if (discard) {
      // A dead renderer must not block the next document or be reattached.
      _tail = Future.value();
      unawaited(_destroy(afterDetach: afterDetach));
    } else {
      _idle = Timer(idleDelay, () {
        unawaited(_destroy());
      });
    }
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _destroy({Future<void>? afterDetach}) async {
    final keepAlive = _keepAlive;
    final environment = _environment;
    final created = _created;
    _keepAlive = null;
    _environment = null;
    _created = false;
    await afterDetach;
    try {
      if (created && keepAlive != null) {
        await InAppWebViewController.disposeKeepAlive(keepAlive)
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // A failed native view cannot prevent the static fallback or a retry.
    } finally {
      if (environment != null) {
        try {
          await environment
              .then((value) => value?.dispose())
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          /* Initialization already reported to the image error view. */
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _owner = null;
    _idle?.cancel();
    // Let the widget detach before releasing its kept-alive platform view.
    scheduleMicrotask(() {
      unawaited(_destroy());
    });
    super.dispose();
  }
}
