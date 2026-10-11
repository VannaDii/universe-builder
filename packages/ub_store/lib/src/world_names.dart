import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'revision_input.dart';

/// Names are selected-revision projections, but reservations are immutable
/// installation history. Removing a world never transfers its old identity.
final class WorldNames {
  WorldNames(this.database);
  final Database database;

  static void validateRecords(Iterable<StoredVersion> records) {
    final names = <String, RecordId>{};
    for (final record in records) {
      for (final key in _keys(record)) {
        final old = names[key];
        if (old != null && old != record.identity.recordId) {
          throw const FormatException('Duplicate world selector');
        }
        names[key] = record.identity.recordId;
      }
    }
  }

  /// Called after inserting the commit, within the caller's write transaction.
  void reserve(CommitInput input, RevisionId revision) {
    if (database.autocommit) {
      throw StateError('World reservations require an owned transaction');
    }
    for (final change in input.changes) {
      final next = change.next;
      if (next == null) continue;
      if (next.identity.universeId != input.universe ||
          next.identity.recordId != change.recordId) {
        throw const FormatException('World reservation identity mismatch');
      }
      for (final key in _keys(next)) {
        final rows = database.select(
          'SELECT record_id FROM world_name_reservations WHERE universe_id=? AND name=?',
          [input.universe.value, key],
        );
        if (rows.isNotEmpty &&
            rows.single['record_id'] != change.recordId.value) {
          throw const FormatException(
            'World name reserved to another identity',
          );
        }
        database.execute(
          'INSERT INTO world_name_reservations VALUES(?,?,?,?) ON CONFLICT DO NOTHING',
          [input.universe.value, key, change.recordId.value, revision.value],
        );
      }
    }
  }

  static Iterable<String> _keys(StoredVersion record) sync* {
    if (record.identity.recordKind != RecordKind.world) return;
    final world = WorldRecord.fromWire(record.payload);
    yield selectorKey(world.selector);
    for (final alias in world.aliases) {
      yield selectorKey(alias);
    }
  }
}
