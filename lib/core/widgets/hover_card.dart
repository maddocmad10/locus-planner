import 'package:flutter/material.dart';

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

    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: radius,
        boxShadow: shadow,
      ),
      transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
      child: widget.child,
    );

    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.onTap == null
          ? content
          : GestureDetector(onTap: widget.onTap, child: content),
    );
  }
}
