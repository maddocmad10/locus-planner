/// Separator placed between two diary texts that were written for the same day
/// on different devices. Never change it once released: devices on different
/// versions would otherwise merge the same two texts differently and stop
/// converging.
const diaryMergeDivider = '\n\n— merged from another device —\n\n';

/// Merges the text of two diary entries that claim the same day.
///
/// [survivor] is the content of the entry that keeps its id (the one with the
/// lower id) and [other] is the content being folded into it.
///
/// The result depends only on these two strings, so the desktop and the phone
/// compute exactly the same text and converge without sending merges back and
/// forth. Each text is split into segments at [diaryMergeDivider], and a
/// segment that [survivor] already has is not added again. That makes the
/// merge idempotent: merging an already-merged entry changes nothing, so a
/// diary entry cannot grow on every sync.
///
/// When nothing needs adding, [survivor] is returned unchanged.
String mergeDiaryContent(String survivor, String other) {
  final merged = _segments(survivor);
  final before = merged.length;
  for (final segment in _segments(other)) {
    if (!merged.contains(segment)) merged.add(segment);
  }
  if (merged.length == before) return survivor;
  return merged.join(diaryMergeDivider);
}

List<String> _segments(String content) => [
  for (final part in content.split(diaryMergeDivider))
    if (part.trim().isNotEmpty) part.trim(),
];
