import 'app_database.dart';

/// Opens (and, if needed, migrates) the database right now.
///
/// Drift opens lazily, so without this a corrupt file or a failed migration
/// only shows up at the first query, which may be inside code that treats
/// errors as optional. Call it before any other startup work that touches the
/// database so a broken database always reaches the startup error screen.
Future<void> verifyDatabaseReady(AppDatabase db) async {
  await db.customSelect('SELECT 1').get();
}

/// Closes [db] without letting a failure to close hide the original error.
Future<void> closeQuietly(AppDatabase? db) async {
  if (db == null) return;
  try {
    await db.close();
  } catch (_) {
    // A database that never opened can fail to close; nothing more to do.
  }
}
