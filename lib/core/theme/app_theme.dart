import 'package:flutter/material.dart';

class AppTheme {
  static const seedColor = Color(0xFF6C5CE7);
  static const lightScaffold = Color(0xFFF8F7FF);
  static const darkScaffold = Color(0xFF121218);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return _buildTheme(
      scheme,
      scaffoldBackgroundColor: lightScaffold,
      cardColor: Colors.white,
      cardShadowColor: scheme.primary.withValues(alpha: 0.10),
      inputFillColor: Colors.white,
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return _buildTheme(
      scheme,
      scaffoldBackgroundColor: darkScaffold,
      cardColor: scheme.surfaceContainerLow,
      cardShadowColor: Colors.black.withValues(alpha: 0.24),
      inputFillColor: scheme.surfaceContainerHighest,
    );
  }

  static ThemeData _buildTheme(
    ColorScheme scheme, {
    required Color scaffoldBackgroundColor,
    required Color cardColor,
    required Color cardShadowColor,
    required Color inputFillColor,
  }) {
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    final inputRadius = BorderRadius.circular(12);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: cardShadowColor,
        shape: cardShape,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: buttonShape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: buttonShape,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        selectedIconTheme: IconThemeData(
          color: scheme.onPrimaryContainer,
        ),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        space: 1,
        thickness: 1,
      ),
    );
  }
}

class EventCategories {
  static const categories = [
    ('general', 'General', Colors.blueGrey),
    ('work', 'Work', Colors.indigo),
    ('personal', 'Personal', Colors.teal),
    ('health', 'Health', Colors.green),
    ('learn', 'Learn', Colors.orange),
  ];

  static Color colorFor(String category) {
    return categories
        .firstWhere((c) => c.$1 == category, orElse: () => categories.first)
        .$3;
  }

  static String labelFor(String category) {
    return categories
        .firstWhere((c) => c.$1 == category, orElse: () => categories.first)
        .$2;
  }
}
