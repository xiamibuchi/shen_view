import 'dart:ffi';
import 'dart:io';

/// Opens a real Windows handle that allows reads/writes but denies deletion
/// and replacement. This reproduces antivirus/other-app file sharing failures.
class WindowsReplaceGuard {
  WindowsReplaceGuard(String path, {bool denyRead = false}) {
    final codes = File(path).absolute.path.codeUnits;
    final heap = _getProcessHeap();
    final memory = _heapAlloc(heap, 8, (codes.length + 1) * 2);
    if (memory == nullptr) throw StateError('HeapAlloc failed');
    try {
      final text = memory.cast<Uint16>();
      text.asTypedList(codes.length + 1).setAll(0, codes);
      _handle = _createFile(
        text,
        0x80000000,
        denyRead ? 0 : 3,
        nullptr,
        3,
        0,
        nullptr,
      );
      if (_handle.address == -1 || _handle == nullptr) {
        throw OSError('CreateFileW failed', _getLastError());
      }
    } finally {
      _heapFree(heap, 0, memory);
    }
  }

  late Pointer<Void> _handle;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    if (_closeHandle(_handle) == 0) {
      throw OSError('CloseHandle failed', _getLastError());
    }
  }

  static final _library = DynamicLibrary.open('kernel32.dll');
  static final _getProcessHeap = _library
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetProcessHeap',
      );
  static final _heapAlloc = _library
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Uint32, UintPtr),
        Pointer<Void> Function(Pointer<Void>, int, int)
      >('HeapAlloc');
  static final _heapFree = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Void>),
        int Function(Pointer<Void>, int, Pointer<Void>)
      >('HeapFree');
  static final _createFile = _library
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<Uint16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          Pointer<Void>,
        ),
        Pointer<Void> Function(
          Pointer<Uint16>,
          int,
          int,
          Pointer<Void>,
          int,
          int,
          Pointer<Void>,
        )
      >('CreateFileW');
  static final _closeHandle = _library
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('CloseHandle');
  static final _getLastError = _library
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
}
