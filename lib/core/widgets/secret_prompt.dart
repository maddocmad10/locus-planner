import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared PIN/passphrase prompt used by app lock and encrypted backups.
///
/// It deliberately keeps the text masked and never logs the value. Callers
/// receive null when the user cancels.
Future<String?> showSecretPrompt(
  BuildContext context, {
  required String title,
  String? description,
  String label = 'PIN',
  String confirmLabel = 'Continue',
  bool numeric = false,
  int? maxLength,
  bool obscure = true,
}) async {
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (description != null) ...[
              Text(description),
              const SizedBox(height: 12),
            ],
            TextField(
              autofocus: true,
              obscureText: obscure,
              keyboardType: numeric
                  ? TextInputType.number
                  : TextInputType.visiblePassword,
              inputFormatters: [
                if (numeric) FilteringTextInputFormatter.digitsOnly,
                if (maxLength != null)
                  LengthLimitingTextInputFormatter(maxLength),
              ],
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              onChanged: (text) => setDialogState(() => value = text),
              onSubmitted: (text) {
                if (text.isNotEmpty) Navigator.pop(dialogContext, text);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: value.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, value),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
}

Future<String?> showPinPrompt(
  BuildContext context, {
  required String title,
  String? description,
  String confirmLabel = 'Continue',
}) => showSecretPrompt(
  context,
  title: title,
  description: description,
  label: 'PIN',
  confirmLabel: confirmLabel,
  numeric: true,
  maxLength: 8,
);

Future<String?> showPassphrasePrompt(
  BuildContext context, {
  required String title,
  String? description,
  String confirmLabel = 'Continue',
}) => showSecretPrompt(
  context,
  title: title,
  description: description,
  label: 'Passphrase',
  confirmLabel: confirmLabel,
  maxLength: 128,
);
