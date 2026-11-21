import 'package:flutter/services.dart';

/// Dart side of the native `locus/windows_toasts` channel.
class WindowsToastPlatform {
  const WindowsToastPlatform();

  static const channelName = 'locus/windows_toasts';
  static const _channel = MethodChannel(channelName);

  Future<void> schedule(List<Map<String, Object>> items) async {
    if (items.isEmpty) return;
    await _channel.invokeMethod<void>('schedule', items);
  }

  Future<void> cancelAllExcept(Set<String> keepIds) async {
    await _channel.invokeMethod<void>(
      'cancelAllExcept',
      keepIds.toList(growable: false),
    );
  }

  Future<List<String>> listScheduled() async {
    final result = await _channel.invokeListMethod<String>('listScheduled');
    return result ?? const [];
  }

  Future<void> setBadge(int count) async {
    await _channel.invokeMethod('setBadge', count);
  }
}
