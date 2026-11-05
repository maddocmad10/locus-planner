import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/planning/saved_filter.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/undo_service.dart';
import '../../../core/utils/app_clock.dart';

final savedFilterRepositoryProvider = Provider<SavedFilterRepository>((ref) {
  return SavedFilterRepository(
    ref.watch(databaseProvider),
    ref.watch(undoServiceProvider),
  );
});

final savedFiltersProvider = StreamProvider.autoDispose
    .family<List<SavedFilter>, String>((ref, scope) {
      return ref.watch(savedFilterRepositoryProvider).watchForScope(scope);
    });

/// Validated saved views. Raw SQL is never stored: every write parses the
/// definition through [SavedFilterDefinition] first.
class SavedFilterRepository {
  SavedFilterRepository(this._db, this._undo);

  final AppDatabase _db;
  final UndoService _undo;
  static const _uuid = Uuid();

  Stream<List<SavedFilter>> watchForScope(String scope) {
    return (_db.select(_db.savedFilters)
          ..where((t) => t.entityScope.equals(scope))
          ..orderBy([
            (t) => OrderingTerm.desc(t.isPinned),
            (t) => OrderingTerm.asc(t.position),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  Future<SavedFilterDefinition> validate({
    required String scope,
    required String filterJson,
    String sortJson = '[]',
  }) async {
    return SavedFilterDefinition.parse(
      scope: scope,
      filterJson: filterJson,
      sortJson: sortJson,
    );
  }

  Future<String> create({
    required String scope,
    required String name,
    required String filterJson,
    String sortJson = '[]',
    bool isPinned = false,
  }) async {
    final trimmedName = _validateName(name);
    final definition = await validate(
      scope: scope,
      filterJson: filterJson,
      sortJson: sortJson,
    );
    await _ensureNameFree(scope, trimmedName);

    final now = AppClock.now();
    final id = _uuid.v4();
    await _db
        .into(_db.savedFilters)
        .insert(
          SavedFiltersCompanion.insert(
            id: id,
            name: trimmedName,
            entityScope: scope,
            filterJson: definition.toFilterJson(),
            sortJson: Value(definition.toSortJson()),
            isPinned: Value(isPinned),
            position: Value(await _nextPosition(scope)),
            createdAt: now,
            updatedAt: now,
            definitionVersion: Value(SavedFilterDefinition.supportedVersion),
          ),
        );
    return id;
  }

  Future<void> updateDefinition({
    required SavedFilter savedFilter,
    String? name,
    String? filterJson,
    String? sortJson,
    int? definitionVersion,
  }) async {
    final nextName = name == null ? savedFilter.name : _validateName(name);
    if (nextName != savedFilter.name) {
      await _ensureNameFree(savedFilter.entityScope, nextName);
    }
    final definition = SavedFilterDefinition.parse(
      scope: savedFilter.entityScope,
      filterJson: filterJson ?? savedFilter.filterJson,
      sortJson: sortJson ?? savedFilter.sortJson,
      definitionVersion: definitionVersion ?? savedFilter.definitionVersion,
    );
    await (_db.update(
      _db.savedFilters,
    )..where((t) => t.id.equals(savedFilter.id))).write(
      SavedFiltersCompanion(
        name: Value(nextName),
        filterJson: Value(definition.toFilterJson()),
        sortJson: Value(definition.toSortJson()),
        updatedAt: Value(AppClock.now()),
      ),
    );
  }

  Future<void> setPinned(SavedFilter filter, bool pinned) async {
    await (_db.update(
      _db.savedFilters,
    )..where((t) => t.id.equals(filter.id))).write(
      SavedFiltersCompanion(
        isPinned: Value(pinned),
        updatedAt: Value(AppClock.now()),
      ),
    );
  }

  Future<void> delete(SavedFilter filter) async {
    await (_db.delete(
      _db.savedFilters,
    )..where((t) => t.id.equals(filter.id))).go();
    _undo.offer(
      label: 'saved view',
      restore: () async {
        await _db.into(_db.savedFilters).insertOnConflictUpdate(filter);
      },
    );
  }

  Future<void> reorder(String scope, List<String> orderedIds) async {
    final now = AppClock.now();
    await _db.transaction(() async {
      for (var index = 0; index < orderedIds.length; index++) {
        await (_db.update(
          _db.savedFilters,
        )..where((t) => t.id.equals(orderedIds[index]))).write(
          SavedFiltersCompanion(position: Value(index), updatedAt: Value(now)),
        );
      }
    });
  }

  /// Builds the SQL predicate and variables for a saved view. The caller adds
  /// the WHERE keyword only when [CompiledFilter.whereSql] is non-empty.
  CompiledFilter compile(SavedFilter filter, {DateTime? now}) {
    final definition = SavedFilterDefinition.parse(
      scope: filter.entityScope,
      filterJson: filter.filterJson,
      sortJson: filter.sortJson,
      definitionVersion: filter.definitionVersion,
    );
    return definition.compile(now: now);
  }

  Future<void> _ensureNameFree(String scope, String name) async {
    final rows = await (_db.select(
      _db.savedFilters,
    )..where((t) => t.entityScope.equals(scope))).get();
    final lowered = name.toLowerCase();
    if (rows.any((row) => row.name.toLowerCase() == lowered)) {
      throw SavedFilterException('A saved view named "$name" already exists.');
    }
  }

  Future<int> _nextPosition(String scope) async {
    final last =
        await (_db.select(_db.savedFilters)
              ..where((t) => t.entityScope.equals(scope))
              ..orderBy([(t) => OrderingTerm.desc(t.position)])
              ..limit(1))
            .getSingleOrNull();
    return (last?.position ?? -1) + 1;
  }

  static String _validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const SavedFilterException('A saved view needs a name.');
    }
    if (trimmed.length > 80) {
      throw const SavedFilterException('A saved view name is too long.');
    }
    return trimmed;
  }
}
