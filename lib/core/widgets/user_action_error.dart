import 'dart:async';

import 'package:flutter/material.dart';

import '../services/error_log_service.dart';

Future<bool> runUserMutation(
  BuildContext context,
  Future<void> Function() action, {
  required String failureMessage,
}) async {
  try {
    await action();
    return true;
  } catch (error, stack) {
    unawaited(ErrorLogService.log(error, stack));
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failureMessage)),
    );
    return false;
  }
}
