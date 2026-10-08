import 'package:flutter/material.dart';

/// A card that lifts slightly under the mouse and, when [onTap] is given, can
/// be activated with the pointer or the keyboard (Tab to focus, Enter/Space).
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = widget.borderRadius ?? BorderRadius.circular(20);
    final shadow = _hovered
        ? [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ]
        : const <BoxShadow>[];

    final body = Padding(
      padding: widget.padding ?? EdgeInsets.zero,
      child: widget.child,
    );

    // The shadow lives on the outer box; the card colour and the ink splash on
    // the Material inside it, so the splash is drawn above the colour.
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
      child: Material(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: widget.onTap == null
            ? body
            : InkWell(onTap: widget.onTap, borderRadius: radius, child: body),
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: content,
    );
  }
}
