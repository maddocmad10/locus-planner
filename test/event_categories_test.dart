import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/theme/app_theme.dart';

void main() {
  test('known categories are offered exactly once', () {
    final options = EventCategories.optionsFor('work');
    expect(
      options.map((o) => o.$1),
      EventCategories.categories.map((c) => c.$1),
    );
  });

  test(
    'an unknown category is kept as an extra option instead of being replaced',
    () {
      final options = EventCategories.optionsFor('conference');
      expect(options.last, ('conference', 'conference'));
      expect(options.length, EventCategories.categories.length + 1);
    },
  );
}
