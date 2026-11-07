import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A notes editor with an explicit Edit/Preview switch.
///
/// The format marker travels with the text so another device knows whether to
/// render it as plain text or as the small `md1` Markdown subset below. Unknown
/// future markers are coerced to `plain` by the database and sync layers, so
/// text stays readable even when an older build opens a newer row.
class NotesField extends StatefulWidget {
  const NotesField({
    super.key,
    required this.controller,
    required this.format,
    required this.onFormatChanged,
    this.label = 'Notes',
    this.hint,
    this.minLines = 2,
    this.maxLines = 6,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String format;
  final ValueChanged<String> onFormatChanged;
  final String label;
  final String? hint;
  final int minLines;
  final int maxLines;
  final bool autofocus;

  @override
  State<NotesField> createState() => _NotesFieldState();
}

class _NotesFieldState extends State<NotesField> {
  bool _preview = false;

  void _setPreview(bool preview) {
    setState(() => _preview = preview);
    if (preview && widget.format != 'md1') {
      widget.onFormatChanged('md1');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = widget.controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.label, style: theme.textTheme.labelLarge),
            const Spacer(),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.edit_outlined, size: 16),
                  label: Text('Edit'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.visibility_outlined, size: 16),
                  label: Text('Preview'),
                ),
              ],
              selected: {_preview},
              onSelectionChanged: (selection) => _setPreview(selection.first),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_preview)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: text.isEmpty
                ? Text(
                    widget.hint ?? 'Nothing to preview yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Md1Text(text, style: theme.textTheme.bodyMedium),
          )
        else
          TextField(
            controller: widget.controller,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            autofocus: widget.autofocus,
            decoration: InputDecoration(
              hintText: widget.hint,
              border: const OutlineInputBorder(),
            ),
          ),
      ],
    );
  }
}

/// Renders the deliberately small `md1` Markdown subset.
///
/// Supported: headings, paragraphs, unordered/ordered lists, task checkboxes,
/// blockquotes, fenced code, inline code, bold, italic, strikethrough,
/// `[label](url)` links and `![alt](locus-att://id)` image references. Links
/// are shown as underlined text but are not opened from here: a note is
/// untrusted content, and opening a remote URL from a preview would be
/// surprising. Image references render as a labelled placeholder rather than
/// loading anything, and raw HTML is never interpreted.
class Md1Text extends StatefulWidget {
  const Md1Text(this.source, {super.key, this.style});

  final String source;
  final TextStyle? style;

  @override
  State<Md1Text> createState() => _Md1TextState();
}

class _Md1TextState extends State<Md1Text> {
  final _recognizers = <TapGestureRecognizer>[];

  static const _externalSchemes = {'http', 'https', 'mailto'};

  void _resetRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _resetRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _resetRecognizers();
    final base = widget.style ?? Theme.of(context).textTheme.bodyMedium!;
    final blocks = _parseBlocks(widget.source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < blocks.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          _buildBlock(context, blocks[index], base),
        ],
      ],
    );
  }

  Widget _buildBlock(BuildContext context, _Block block, TextStyle base) {
    final theme = Theme.of(context);
    switch (block.kind) {
      case _BlockKind.heading:
        final size = switch (block.level) {
          1 => 22.0,
          2 => 19.0,
          _ => 17.0,
        };
        return SelectableText.rich(
          TextSpan(
            children: _inline(
              context,
              block.text,
              base.copyWith(fontSize: size),
            ),
          ),
          style: base.copyWith(fontWeight: FontWeight.w600, fontSize: size),
        );
      case _BlockKind.quote:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 3),
            ),
          ),
          child: SelectableText.rich(
            TextSpan(children: _inline(context, block.text, base)),
            style: base,
          ),
        );
      case _BlockKind.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            block.text,
            style: base.copyWith(fontFamily: 'monospace', fontSize: 13),
          ),
        );
      case _BlockKind.unordered:
      case _BlockKind.ordered:
      case _BlockKind.task:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: block.kind == _BlockKind.task
                  ? Icon(
                      block.checked
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : Text(
                      block.kind == _BlockKind.ordered
                          ? '${block.level}.'
                          : '•',
                    ),
            ),
            Expanded(
              child: SelectableText.rich(
                TextSpan(children: _inline(context, block.text, base)),
                style: block.checked
                    ? base.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : base,
              ),
            ),
          ],
        );
      case _BlockKind.paragraph:
        return SelectableText.rich(
          TextSpan(children: _inline(context, block.text, base)),
          style: base,
        );
    }
  }

  static List<_Block> _parseBlocks(String source) {
    final lines = source.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_Block>[];
    final paragraph = <String>[];
    var inCode = false;
    final code = <String>[];
    var orderedIndex = 0;

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      blocks.add(_Block(_BlockKind.paragraph, paragraph.join(' '), level: 0));
      paragraph.clear();
    }

    for (final line in lines) {
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          blocks.add(_Block(_BlockKind.code, code.join('\n')));
          code.clear();
          inCode = false;
        } else {
          flushParagraph();
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        code.add(line);
        continue;
      }
      if (line.trim().isEmpty) {
        flushParagraph();
        orderedIndex = 0;
        continue;
      }
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        flushParagraph();
        blocks.add(
          _Block(
            _BlockKind.heading,
            heading.group(2)!.trim(),
            level: heading.group(1)!.length,
          ),
        );
        continue;
      }
      final quote = RegExp(r'^>\s?(.*)$').firstMatch(line);
      if (quote != null) {
        flushParagraph();
        blocks.add(_Block(_BlockKind.quote, quote.group(1)!.trim()));
        continue;
      }
      final task = RegExp(r'^\s*[-*+]\s+\[([ xX])\]\s+(.*)$').firstMatch(line);
      if (task != null) {
        flushParagraph();
        blocks.add(
          _Block(
            _BlockKind.task,
            task.group(2)!.trim(),
            checked: task.group(1)!.toLowerCase() == 'x',
          ),
        );
        continue;
      }
      final unordered = RegExp(r'^\s*[-*+]\s+(.*)$').firstMatch(line);
      if (unordered != null) {
        flushParagraph();
        blocks.add(_Block(_BlockKind.unordered, unordered.group(1)!.trim()));
        continue;
      }
      final ordered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (ordered != null) {
        flushParagraph();
        orderedIndex = int.tryParse(ordered.group(1)!) ?? orderedIndex + 1;
        blocks.add(
          _Block(
            _BlockKind.ordered,
            ordered.group(2)!.trim(),
            level: orderedIndex,
          ),
        );
        continue;
      }
      paragraph.add(line.trim());
    }
    if (inCode && code.isNotEmpty) {
      blocks.add(_Block(_BlockKind.code, code.join('\n')));
    }
    flushParagraph();
    return blocks;
  }

  List<InlineSpan> _inline(BuildContext context, String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(!\[[^\]]*\]\([^)]+\)|\*\*[^*]+\*\*|~~[^~]+~~|\*[^*]+\*|`[^`]+`|\[[^\]]+\]\([^)]+\))',
    );
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final token = match.group(0)!;
      if (token.startsWith('![')) {
        final image = RegExp(r'^!\[([^\]]*)\]\(([^)]+)\)$').firstMatch(token);
        final alt = image?.group(1)?.trim() ?? '';
        spans.add(
          TextSpan(
            text: alt.isEmpty ? '[Image]' : '[Image: $alt]',
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              color: Color(0xFF6C5CE7),
            ),
          ),
        );
      } else if (token.startsWith('**') && token.endsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (token.startsWith('`') && token.endsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: base.copyWith(
              fontFamily: 'monospace',
              backgroundColor: const Color(0x22808080),
            ),
          ),
        );
      } else if (token.startsWith('~~') && token.endsWith('~~')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: const TextStyle(decoration: TextDecoration.lineThrough),
          ),
        );
      } else if (token.startsWith('*') && token.endsWith('*')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        final link = RegExp(r'^\[([^\]]+)\]\(([^)]+)\)$').firstMatch(token);
        final label = link?.group(1) ?? token;
        final rawUri = link?.group(2);
        final uri = rawUri == null ? null : Uri.tryParse(rawUri.trim());
        if (uri == null ||
            (!_externalSchemes.contains(uri.scheme) &&
                uri.scheme != 'locus-att')) {
          // Unknown schemes are shown as plain text, never as a live link.
          spans.add(TextSpan(text: label));
        } else {
          final recognizer = TapGestureRecognizer()
            ..onTap = () => _openLink(context, uri);
          _recognizers.add(recognizer);
          spans.add(
            TextSpan(
              text: label,
              recognizer: recognizer,
              style: const TextStyle(
                decoration: TextDecoration.underline,
                color: Color(0xFF6C5CE7),
              ),
            ),
          );
        }
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return spans;
  }

  Future<void> _openLink(BuildContext context, Uri uri) async {
    if (uri.scheme == 'locus-att') {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Attachment link'),
          content: Text(
            'This note points at attachment ${uri.host.isEmpty ? uri.path : uri.host}. '
            'Open it from the attachment strip below.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    if (!_externalSchemes.contains(uri.scheme)) return;
    // Only a user tap opens a link, and only the four allowed schemes are
    // considered. Note previews never fetch remote images or pages.
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This link could not be opened.')),
      );
    }
  }
}

enum _BlockKind { paragraph, heading, quote, unordered, ordered, task, code }

class _Block {
  const _Block(this.kind, this.text, {this.level = 0, this.checked = false});

  final _BlockKind kind;
  final String text;
  final int level;
  final bool checked;
}
