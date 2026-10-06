import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keeps one short-lived destructive action reversible.
///
/// This deliberately stays in memory: it is a UX safety net, not a second
/// persistence layer. A restart clears the pending undo, while exports remain
/// the durable recovery mechanism.
class UndoService extends ChangeNotifier {
  UndoService();

  Timer? _expiry;
  Future<void> Function()? _restore;
  String? _label;

  bool get hasUndo => _restore != null;
  String? get label => _label;

  void offer({
    required String label,
    required Future<void> Function() restore,
    Duration duration = const Duration(seconds: 8),
  }) {
    _expiry?.cancel();
    _label = label;
    _restore = restore;
    _expiry = Timer(duration, clear);
    notifyListeners();
  }

  Future<bool> undo() async {
    final action = _restore;
    if (action == null) return false;
    clear();
    try {
      await action();
      return true;
    } catch (e, st) {
      debugPrint('Undo failed: $e\n$st');
      return false;
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    _expiry = null;
    _restore = null;
    _label = null;
    super.dispose();
  }

  void clear() {
    _expiry?.cancel();
    _expiry = null;
    _restore = null;
    _label = null;
    notifyListeners();
  }
}
