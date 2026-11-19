import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SharedFile {
  const SharedFile({
    required this.path,
    required this.name,
    required this.mimeType,
  });

  final String path;
  final String name;
  final String mimeType;
}

/// Receives files shared to Locus from Android's share sheet. The Kotlin side
/// copies each shared URI into the app cache and returns only those paths.
class ShareIntakeService {
  ShareIntakeService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedFiles') {
        final files = _parse(call.arguments);
        if (files.isNotEmpty) _controller.add(files);
      }
    });
  }

  static const channelName = 'locus_planner/share_intake';
  static const _channel = MethodChannel(channelName);

  final _controller = StreamController<List<SharedFile>>.broadcast();

  /// Files shared while the app is already running.
  Stream<List<SharedFile>> get sharedFiles => _controller.stream;

  Future<List<SharedFile>> take() async {
    try {
      return _parse(
        await _channel.invokeListMethod<dynamic>('takeSharedFiles'),
      );
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static List<SharedFile> _parse(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map && item['path'] is String)
          SharedFile(
            path: item['path'] as String,
            name: item['name'] is String
                ? item['name'] as String
                : 'shared-file',
            mimeType: item['mimeType'] is String
                ? item['mimeType'] as String
                : 'application/octet-stream',
          ),
    ];
  }

  void dispose() {
    _controller.close();
  }
}

final shareIntakeServiceProvider = Provider<ShareIntakeService>((ref) {
  final service = ShareIntakeService();
  ref.onDispose(service.dispose);
  return service;
});
