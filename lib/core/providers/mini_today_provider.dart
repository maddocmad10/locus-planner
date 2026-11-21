import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When true the main window is compact, always-on-top and shows only the next
/// few items. The window geometry is owned by [WindowService].
final miniTodayModeProvider = StateProvider<bool>((ref) => false);
