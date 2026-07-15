import 'package:flutter/material.dart';

class AppTheme {
  static const seedColor = Color(0xFF6C5CE7);
  static const lightScaffold = Color(0xFFFAFAF9);
  static const darkScaffold = Color(0xFF121218);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: lightScaffold,
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: darkScaffold,
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
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
        .firstWhere(
          (c) => c.$1 == category,
          orElse: () => categories.first,
        )
        .$3;
  }

  static String labelFor(String category) {
    return categories
        .firstWhere(
          (c) => c.$1 == category,
          orElse: () => categories.first,
        )
        .$2;
  }
}
