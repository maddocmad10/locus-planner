import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/features/settings/import_failure_message.dart';

void main() {
  test('a format error shows its detail and says nothing was changed', () {
    final message = describeImportFailure(
      const FormatException('A backup file must contain a JSON object.'),
    );
    expect(message, contains('must contain a JSON object'));
    expect(message, contains('not changed'));
  });

  test('a format error without detail still explains the problem', () {
    final message = describeImportFailure(const FormatException(''));
    expect(message, contains('not a valid Locus backup'));
  });

  test('a failed recovery backup is reported', () {
    final message = describeImportFailure(
      StateError('Could not create a recovery backup before import.'),
    );
    expect(message, contains('recovery backup'));
    expect(message, contains('not changed'));
  });

  test('anything else points at the error log without promising too much', () {
    final message = describeImportFailure(Exception('disk full'));
    expect(message, contains('error log'));
    expect(message, isNot(contains('not changed')));
    expect(message, isNot(contains('disk full')));
  });
}
