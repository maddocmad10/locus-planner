import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SharedFile {
  const SharedFile({
    required this.path,
    required this.name,
    required this.mimeType,
    this.attachmentId,
  });

  final String path;
  final String name;
  final String mimeType;
  final String? attachmentId;
}

class RejectedSharedItem {
  const RejectedSharedItem({
    required this.name,
    required this.mimeType,
    required this.reason,
  });

  final String name;
  final String mimeType;
  final String reason;
}

/// One durable Android share. [id] is reused as the task id so replaying the
/// same pending intake cannot create a second task.
class ShareIntake {
  const ShareIntake({
    required this.id,
    required this.title,
    required this.text,
    required this.files,
    required this.rejected,
  });

  final String id;
  final String title;
  final String text;
  final List<SharedFile> files;
  final List<RejectedSharedItem> rejected;

  bool get isEmpty => text.trim().isEmpty && files.isEmpty;
}

/// Receives shares from Android's share sheet. The Kotlin side stages files
/// and a manifest; this class only parses and acknowledges completion.
class ShareIntakeService {
  ShareIntakeService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedIntake') {
        _controller.add(await takeIntakes());
      }
    });
  }

  static const channelName = 'locus_planner/share_intake';
  static const _channel = MethodChannel(channelName);

  final _controller = StreamController<List<ShareIntake>>.broadcast();

  /// Intakes available while the app is already running.
  Stream<List<ShareIntake>> get pendingIntakes => _controller.stream;

  Future<List<ShareIntake>> takeIntakes() async {
    try {
      final raw = await _channel.invokeListMethod<dynamic>('takeSharedIntakes');
      return _parseIntakes(raw);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Flattened view retained for callers that only need files.
  Future<List<SharedFile>> take() async => [
    for (final intake in await takeIntakes()) ...intake.files,
  ];

  /// Marks one intake complete after the task and attachment metadata commit.
  Future<void> complete(String intakeId) async {
    try {
      await _channel.invokeMethod<void>('completeIntake', {'id': intakeId});
    } on MissingPluginException {
      // Not on Android.
    } on PlatformException {
      // The startup sweep removes an abandoned staging directory.
    }
  }

  static List<ShareIntake> _parseIntakes(Object? value) {
    if (value is! List) return const [];
    final result = <ShareIntake>[];
    for (final item in value) {
      if (item is! Map) continue;
      final id = item['id'];
      if (id is! String || id.isEmpty) continue;
      result.add(
        ShareIntake(
          id: id,
          title: item['title'] is String
              ? item['title'] as String
              : 'Shared item',
          text: item['text'] is String ? item['text'] as String : '',
          files: _parseFiles(item['files']),
          rejected: _parseRejected(item['rejected']),
        ),
      );
    }
    return result;
  }

  static List<SharedFile> _parseFiles(Object? value) {
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
            attachmentId: item['attachmentId'] is String
                ? item['attachmentId'] as String
                : null,
          ),
    ];
  }

  static List<RejectedSharedItem> _parseRejected(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map)
          RejectedSharedItem(
            name: item['name'] is String ? item['name'] as String : 'item',
            mimeType: item['mimeType'] is String
                ? item['mimeType'] as String
                : 'application/octet-stream',
            reason: item['reason'] is String
                ? item['reason'] as String
                : 'rejected',
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
