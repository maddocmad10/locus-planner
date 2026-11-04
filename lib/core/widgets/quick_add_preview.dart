import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/natural_language_quick_add.dart';
import '../utils/recurrence.dart';

/// Compact confirmation preview shared by the desktop dialog and mobile sheet.
class QuickAddPreview extends StatelessWidget {
  const QuickAddPreview({super.key, required this.parsed});

  final NaturalLanguageCapture parsed;

  @override
  Widget build(BuildContext context) {
    final date = parsed.date;
    final chips = <Widget>[
      if (date != null)
        _previewChip(
          Icons.event,
          DateFormat(
            parsed.allDay ? 'EEE d MMM' : 'EEE d MMM, h:mm a',
          ).format(date),
        ),
      if (parsed.recurrenceRule != null)
        _previewChip(Icons.repeat, Recurrence.label(parsed.recurrenceRule)),
      if (parsed.priority != QuickAddPriority.none)
        _previewChip(Icons.flag_outlined, switch (parsed.priority) {
          QuickAddPriority.high => 'High priority',
          QuickAddPriority.medium => 'Medium priority',
          QuickAddPriority.low => 'Low priority',
          QuickAddPriority.none => '',
        }),
      for (final tag in parsed.tags) _previewChip(Icons.tag, '#$tag'),
      if (parsed.projectHint != null)
        _previewChip(Icons.folder_outlined, '@${parsed.projectHint}'),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _previewChip(IconData icon, String label) => Chip(
    avatar: Icon(icon, size: 16),
    label: Text(label),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
