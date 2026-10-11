import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'references.dart';
import 'revision_input.dart';

/// Disposable indexes only. Revision history and typed bodies remain authority.
final class RecordProjections {
  RecordProjections(this.database);
  final Database database;

  void project(int generation, StoredVersion version) {
    if (database.autocommit) {
      throw StateError('Projection write requires an owned transaction');
    }
    final refs = ReferenceScan.collect(
      version.payload,
      version.identity.universeId,
    );
    final id = version.versionId.value;
    for (final reference in refs.records) {
      database.execute('INSERT INTO reference_index VALUES(?,?,?,?,?)', [
        generation,
        id,
        reference.record.value,
        reference.version?.value,
        reference.path,
      ]);
      if ({
        RecordKind.work,
        RecordKind.workVersion,
        RecordKind.saga,
        RecordKind.sceneRef,
        RecordKind.passageRef,
      }.contains(version.identity.recordKind)) {
        database.execute('INSERT INTO narrative_projection VALUES(?,?,?,?)', [
          generation,
          id,
          reference.record.value,
          reference.path,
        ]);
      }
    }
    for (final world in refs.worlds) {
      database.execute('INSERT INTO world_projection VALUES(?,?,?)', [
        generation,
        id,
        world.value,
      ]);
    }
    for (final (path, value) in refs.scalars) {
      database.execute('INSERT INTO typed_projection VALUES(?,?,?,?)', [
        generation,
        id,
        path,
        value,
      ]);
    }
    final fields = objectFields(version.payload);
    final String text;
    switch (version.identity.recordKind) {
      case RecordKind.entity:
        final names = (fields['names'] as CanonicalArray).items;
        text = [
          for (final value in objectFields(fields['labels']!).values)
            (value as CanonicalString).value,
          for (final name in names)
            (objectFields(name)['text'] as CanonicalString).value,
        ].join(' ');
      case RecordKind.world:
        text = [
          (fields['selector'] as CanonicalString).value,
          for (final alias in (fields['aliases'] as CanonicalArray).items)
            (alias as CanonicalString).value,
        ].join(' ');
      case RecordKind.work:
      case RecordKind.saga:
        text = (fields['title'] as CanonicalString).value;
      case RecordKind.appearance:
      case RecordKind.source:
        text = (fields['label'] as CanonicalString).value;
      case RecordKind.imageAsset:
        text = (fields['original_name'] as CanonicalString).value;
      default:
        text = '';
    }
    database.execute(
      'INSERT INTO search_index(generation,version_id,text) VALUES(?,?,?)',
      [generation, id, text],
    );
  }
}
