import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/utils/md1_plain.dart';

void main() {
  test('strips markers, links and image references', () {
    expect(plainTextFromMd1('# Title\n\nSome **bold** text'), 'Title');
    expect(plainTextFromMd1('- [x] Done\n- [ ] Open'), 'Done');
    expect(
      plainTextFromMd1('See [the docs](https://example.com) now'),
      'See the docs now',
    );
    expect(plainTextFromMd1('![Diagram](locus-att://a1)'), 'Diagram');
    expect(plainTextFromMd1('> quoted `code`'), 'quoted code');
  });

  test('never returns raw HTML and truncates long first lines', () {
    expect(plainTextFromMd1('<b>unsafe</b>'), contains('<b>unsafe</b>'));
    final long = plainTextFromMd1('a' * 400, maxChars: 20);
    expect(long.length, lessThanOrEqualTo(21));
    expect(long, endsWith('…'));
  });
}
