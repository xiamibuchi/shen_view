import 'dart:io';

import 'package:flutter/services.dart';

import 'file_association_formats.dart';
export 'file_association_formats.dart';

class FileAssociationState {
  const FileAssociationState({
    required this.mode,
    required this.registered,
    required this.defaults,
  });

  final String mode;
  final Set<String> registered;
  final Set<String> defaults;
  bool get isPackaged => mode == 'msix';
}

class FileAssociationService {
  const FileAssociationService();
  static const channel = MethodChannel('shenview/file_associations');
  bool get isSupported => Platform.isWindows;

  Future<FileAssociationState> read() async {
    final data = await channel.invokeMapMethod<String, dynamic>(
      'read',
      FileAssociationFormats.all.toList(),
    );
    if (data == null) throw StateError('No file association state');
    final extensions = Map<Object?, Object?>.from(data['extensions'] as Map);
    final registered = <String>{};
    final defaults = <String>{};
    for (final entry in extensions.entries) {
      final state = Map<Object?, Object?>.from(entry.value as Map);
      if (state['registered'] == true) registered.add(entry.key as String);
      if (state['isDefault'] == true) defaults.add(entry.key as String);
    }
    return FileAssociationState(
      mode: data['mode'] as String,
      registered: registered,
      defaults: defaults,
    );
  }

  Future<void> update(Set<String> selected) async {
    if (!FileAssociationFormats.all.containsAll(selected)) {
      throw ArgumentError.value(selected, 'selected', 'Unsupported file type');
    }
    await channel.invokeMethod<void>('update', selected.toList()..sort());
  }

  Future<void> openSettings() => channel.invokeMethod<void>('openSettings');
}
