/// A conservative plain-text projection of the `md1` subset.
///
/// Used where raw markup must never appear: list subtitles, reminders and
/// widget text. Images are reduced to their alt text, links to their label and
/// block markers are removed. It intentionally does not parse HTML.
String plainTextFromMd1(String source, {int maxChars = 160}) {
  var text = source.replaceAll('\r\n', '\n');

  // Images -> alt text (or a neutral word).
  text = text.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]+\)'),
    (match) => match.group(1)!.trim().isEmpty ? 'image' : match.group(1)!,
  );
  // Links -> label.
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (match) => match.group(1)!,
  );
  // Fenced code markers.
  text = text.replaceAll(RegExp(r'^\s*```.*$', multiLine: true), '');
  text = text.replaceAll('`', '');
  // Emphasis markers.
  text = text.replaceAll(RegExp(r'\*\*|~~|\*'), '');

  final lines = text
      .split('\n')
      .map((line) {
        var value = line.trim();
        value = value.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
        value = value.replaceFirst(RegExp(r'^>\s?'), '');
        value = value.replaceFirst(RegExp(r'^[-*+]\s+\[[ xX]\]\s+'), '');
        value = value.replaceFirst(RegExp(r'^[-*+]\s+'), '');
        value = value.replaceFirst(RegExp(r'^\d+[.)]\s+'), '');
        return value.trim();
      })
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  if (lines.isEmpty) return '';
  final first = lines.first.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (first.length <= maxChars) return first;
  return '${first.substring(0, maxChars).trimRight()}…';
}
