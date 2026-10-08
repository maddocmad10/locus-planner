/// A user-facing message for a failed backup import. The technical details are
/// already in the error log; this only says what went wrong and, where it is
/// certain, that nothing was changed.
String describeImportFailure(Object error) {
  if (error is FormatException) {
    final detail = error.message.trim();
    return detail.isEmpty
        ? 'Import failed: the file is not a valid Locus backup. '
            'Your data was not changed.'
        : 'Import failed: $detail Your data was not changed.';
  }
  if (error is StateError) {
    return 'Import failed: ${error.message} Your data was not changed.';
  }
  return 'Import failed. The details were written to the error log.';
}
