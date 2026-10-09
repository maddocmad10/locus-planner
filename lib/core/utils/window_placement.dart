import 'dart:ui';

/// Where to put a window restored from a saved position.
///
/// If the saved window still shows a meaningful part of any monitor's usable
/// area, keep it there (clamped fully inside that area). Otherwise the monitor
/// it was on has probably been unplugged, so move it to [primaryWorkArea]
/// (or the first monitor if none is given). With no monitor information at all
/// the saved position is returned unchanged.
Offset restoredWindowPosition({
  required Offset saved,
  required Size size,
  required List<Rect> workAreas,
  Rect? primaryWorkArea,
  double minVisibleWidth = 120,
  double minVisibleHeight = 80,
}) {
  final savedRect = Rect.fromLTWH(saved.dx, saved.dy, size.width, size.height);

  for (final area in workAreas) {
    // With no overlap Rect.intersect gives a negative width or height.
    final overlap = savedRect.intersect(area);
    if (overlap.width >= minVisibleWidth &&
        overlap.height >= minVisibleHeight) {
      return _clampInside(saved, size, area);
    }
  }

  final fallback =
      primaryWorkArea ?? (workAreas.isEmpty ? null : workAreas.first);
  if (fallback == null) return saved;
  return _clampInside(saved, size, fallback);
}

Offset _clampInside(Offset position, Size size, Rect area) {
  final maxX = area.right - size.width;
  final maxY = area.bottom - size.height;
  // A window larger than the work area is pinned to its top-left corner.
  final x = maxX < area.left
      ? area.left
      : position.dx.clamp(area.left, maxX).toDouble();
  final y = maxY < area.top
      ? area.top
      : position.dy.clamp(area.top, maxY).toDouble();
  return Offset(x, y);
}
