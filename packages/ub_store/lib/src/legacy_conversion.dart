import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'canonical_integrity.dart';
import 'journal.dart';
import 'owned_database.dart';
import 'ownership.dart';
import 'references.dart';
import 'relational.dart';
import 'revision_input.dart';

/// The maintained v0.3 canon-only converter. This deliberately maps legacy
/// editorial IDs; it is separate from identity-preserving operator conversion.
CanonicalObject convertLegacy(
  String source,
  String destination,
  String scratch,
) {
  protectedFile(source);
  if (File(source).lengthSync() > 512 * 1024 * 1024) {
    throw const FormatException('Legacy package exceeds conversion budget');
  }
  final input = sqlite3.open(source, mode: OpenMode.readOnly);
  OwnedSqliteDatabase? output;
  Directory? temporary;
  try {
    input.execute('PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; BEGIN');
    if (input.select('PRAGMA user_version').single.values.single != 0) {
      throw const FormatException(
        'Explicit v0.3 conversion requires schema v0',
      );
    }
    final integrity = input.select('PRAGMA integrity_check');
    if (integrity.length != 1 || integrity.single.values.single != 'ok') {
      throw const FormatException('Legacy integrity check failed');
    }
    for (final table in [
      'source_versions',
      'anchors',
      'blob_refs',
      'changesets',
      'changeset_versions',
      'approvals',
      'operation_receipts',
      'idempotency_keys',
    ]) {
      if (input.select('SELECT count(*) AS n FROM $table').single['n'] != 0) {
        throw const FormatException(
          'Legacy source/workflow data requires explicit external migration; original retained',
        );
      }
    }
    final universes = input.select('SELECT id,name FROM universes LIMIT 2');
    if (universes.length != 1) {
      throw const FormatException(
        'Legacy conversion requires exactly one universe',
      );
    }
    final universe = UniverseId.parse(universes.single['id'] as String);
    final name = universes.single['name'] as String;
    selectorKey(name);
    temporary = Directory(privateDirectory(scratch))
        .createTempSync('.legacy-conversion-');
    privateDirectory(temporary.path);
    output = OwnedSqliteDatabase.create('${temporary.path}/package.sqlite');
    final db = output.database;
    db.execute('BEGIN IMMEDIATE; PRAGMA defer_foreign_keys=ON');
    db.execute('INSERT INTO universes(id,name) VALUES(?,?)', [
      universe.value,
      name,
    ]);
    final records = <RecordVersionId, RecordId>{};
    final identities = <RecordId, RecordKind>{};
    final codec = RelationalCodec(db);
    final read = input.prepare(
      'SELECT id,record_id,universe_id,kind,payload,digest FROM record_versions ORDER BY id LIMIT 100001',
    );
    try {
      final rows = read.selectCursor();
      while (rows.moveNext()) {
        if (records.length >= 100000) {
          throw const FormatException('Legacy version budget exceeded');
        }
        final row = rows.current;
        final bytes = row['payload'];
        if (row['universe_id'] != universe.value ||
            bytes is! Uint8List ||
            bytes.length > 1048576) {
          throw const FormatException('Legacy record scope or size');
        }
        final kind = RecordKind.parse(row['kind'] as String);
        final id = RecordId.parse(row['record_id'] as String);
        final payload = RecordPayload.fromWire(
          CanonicalValue.parseWireJson(utf8.decode(bytes)),
        ).toWire();
        final record = StoredVersion.build(
          RecordVersionId.parse(row['id'] as String),
          RecordIdentity(universeId: universe, recordId: id, recordKind: kind),
          payload,
        );
        if (record.digest != row['digest']) {
          throw const FormatException('Legacy payload digest mismatch');
        }
        final priorKind = identities[id];
        if (priorKind != null && priorKind != kind) {
          throw const FormatException('Legacy identity changes kind');
        }
        if (priorKind == null) {
          identities[id] = kind;
          db.execute('INSERT INTO record_identities VALUES(?,?,?)', [
            universe.value,
            id.value,
            kind.wireName,
          ]);
        }
        if (records.containsKey(record.versionId)) {
          throw const FormatException('Duplicate legacy version');
        }
        records[record.versionId] = id;
        db.execute('INSERT INTO record_versions VALUES(?,?,?,?,?,?)', [
          universe.value,
          record.versionId.value,
          id.value,
          kind.wireName,
          codec.put('Payload', payload),
          record.digest,
        ]);
      }
    } finally {
      read.close();
    }
    if (input
            .select('SELECT count(*) AS n FROM record_identities')
            .single['n'] !=
        identities.length) {
      throw const FormatException(
        'Legacy identities without typed versions require explicit resolution',
      );
    }
    final identityRows = input.prepare(
      'SELECT id,universe_id,kind FROM record_identities',
    );
    try {
      final rows = identityRows.selectCursor();
      while (rows.moveNext()) {
        final row = rows.current;
        if (row['universe_id'] != universe.value ||
            identities[RecordId.parse(row['id'] as String)]?.wireName !=
                row['kind']) {
          throw const FormatException(
            'Legacy identity does not match its typed versions',
          );
        }
      }
    } finally {
      identityRows.close();
    }
    String mapped(String prefix, String id) =>
        '$prefix${sha256.convert(utf8.encode('${universe.value}:$id')).toString().substring(0, 24)}';
    final oldContinuities = input.select(
      'SELECT id,head_commit,baseline_commit FROM continuities ORDER BY id LIMIT 1001',
    );
    if (oldContinuities.isEmpty ||
        oldContinuities.length > 1000 ||
        oldContinuities.any((row) => row['baseline_commit'] != null)) {
      throw const FormatException(
        'Legacy conversion requires non-inherited continuities; ambiguous baselines are not inferred',
      );
    }
    final continuities = <String, ContinuityId>{
      for (final row in oldContinuities)
        row['id'] as String: ContinuityId.parse(
          mapped('cont_', row['id'] as String),
        ),
    };
    final oldCommits = input.select(
      'SELECT id,continuity_id,parent_id,author,reason FROM commits ORDER BY canon_revision,id LIMIT 10001',
    );
    if (oldCommits.isEmpty || oldCommits.length > 10000) {
      throw const FormatException('Legacy commit budget or missing history');
    }
    final commits = {for (final row in oldCommits) row['id'] as String: row};
    final revisions = {
      for (final id in commits.keys) id: RevisionId.parse(mapped('rev_', id)),
    };
    final snapshots = <String, (int, Membership)>{};
    final firstAdmission = <RecordId, RevisionId>{};
    var work = 0;
    while (snapshots.length < commits.length) {
      final before = snapshots.length;
      for (final entry in commits.entries) {
        final id = entry.key, row = entry.value;
        final parent = row['parent_id'] as String?;
        if (snapshots.containsKey(id) ||
            parent != null && !snapshots.containsKey(parent)) {
          continue;
        }
        final cont = row['continuity_id'] as String;
        if (!continuities.containsKey(cont)) {
          throw const FormatException('Legacy commit continuity missing');
        }
        if (parent != null && commits[parent]?['continuity_id'] != cont) {
          throw const FormatException(
            'Legacy cross-continuity parent requires explicit mapping',
          );
        }
        final previous = parent == null ? null : snapshots[parent];
        final sequence = previous == null ? 0 : previous.$1 + 1;
        final membership = previous == null
            ? <RecordId, RecordVersionId>{}
            : Map<RecordId, RecordVersionId>.from(previous.$2);
        final changes = input.select(
          'SELECT record_id,action,version_id FROM commit_changes WHERE commit_id=? ORDER BY id LIMIT 10001',
          [id],
        );
        if (changes.length > 10000) {
          throw const FormatException('Legacy change budget exceeded');
        }
        final touched = <RecordId>{};
        for (final change in changes) {
          final record = RecordId.parse(change['record_id'] as String);
          final prior = membership[record];
          final next = change['version_id'] == null
              ? null
              : RecordVersionId.parse(change['version_id'] as String);
          if (!touched.add(record)) {
            throw const FormatException(
              'Legacy commit changes an identity twice',
            );
          }
          final valid = switch ((
            change['action'],
            prior != null,
            next != null,
          )) {
            ('create', false, true) ||
            ('replace', true, true) ||
            ('tombstone', true, false) => true,
            _ => false,
          };
          if (!valid) {
            throw const FormatException(
              'Legacy change action does not match its history',
            );
          }
          if (next != null && records[next] != record) {
            throw const FormatException(
              'Legacy change targets the wrong record version',
            );
          }
          if (next == null) {
            membership.remove(record);
          } else {
            membership[record] = next;
          }
          firstAdmission.putIfAbsent(record, () => revisions[id]!);
          db.execute('INSERT INTO commit_changes VALUES(?,?,?,?,?)', [
            universe.value,
            revisions[id]!.value,
            record.value,
            prior?.value,
            next?.value,
          ]);
        }
        final digest = canonicalDigest(
          CanonicalObject([
            for (final entry in membership.entries)
              MapEntry(entry.key.value, CanonicalString(entry.value.value)),
          ]),
        );
        db.execute('INSERT INTO commits VALUES(?,?,?,?,?,?,?,?,?)', [
          universe.value,
          revisions[id]!.value,
          continuities[cont]!.value,
          parent == null ? null : revisions[parent]!.value,
          sequence,
          row['author'],
          'legacy-conversion:$id',
          row['reason'],
          digest,
        ]);
        work += membership.length + 1;
        if (work > 1000000) {
          throw const FormatException('Legacy replay work budget exceeded');
        }
        snapshots[id] = (sequence, membership);
      }
      if (snapshots.length == before) {
        throw const FormatException(
          'Legacy history contains a cycle or missing parent',
        );
      }
    }
    for (final row in oldContinuities) {
      final id = row['id'] as String, head = row['head_commit'] as String;
      if (!snapshots.containsKey(head) ||
          commits[head]?['continuity_id'] != id) {
        throw const FormatException('Legacy head has no matching history');
      }
      db.execute('INSERT INTO continuities VALUES(?,?,?,NULL)', [
        universe.value,
        continuities[id]!.value,
        revisions[head]!.value,
      ]);
    }
    final journal = SqliteJournal(db, universe);
    final worldHistory = <RecordId, Set<String>>{};
    for (final entry in records.entries) {
      if (identities[entry.value] != RecordKind.world) continue;
      final world = WorldRecord.fromWire(journal.load(entry.key).payload);
      worldHistory.putIfAbsent(entry.value, () => {}).add(world.selector);
      final first = firstAdmission[entry.value];
      if (first == null) {
        throw const FormatException('Legacy world never admitted');
      }
      for (final name in [world.selector, ...world.aliases]) {
        final key = selectorKey(name);
        final prior = db.select(
          'SELECT record_id FROM world_name_reservations WHERE name=?',
          [key],
        );
        if (prior.isNotEmpty &&
            prior.single['record_id'] != entry.value.value) {
          throw const FormatException('Legacy world names were rebound');
        }
        db.execute(
          'INSERT OR IGNORE INTO world_name_reservations VALUES(?,?,?,?)',
          [universe.value, key, entry.value.value, first.value],
        );
      }
    }
    final worlds = input.select(
      'SELECT id,name FROM worlds ORDER BY id LIMIT 10001',
    );
    if (worlds.length > 10000) {
      throw const FormatException('Legacy world budget exceeded');
    }
    for (final row in worlds) {
      final record = worldRecord(WorldId.parse(row['id'] as String));
      if (!(worldHistory[record]?.contains(row['name']) ?? false)) {
        throw const FormatException(
          'Legacy world lacks typed canonical history; admission cannot be invented',
        );
      }
    }
    db.execute('COMMIT');
    output.recover();
    CanonicalIntegrity(journal).verifyComplete();
    output.exportCanonOnly(destination);
    return CanonicalObject([
      const MapEntry('converted', CanonicalBool(true)),
      const MapEntry('canonical', CanonicalBool(false)),
      MapEntry('universe', CanonicalString(universe.value)),
      MapEntry(
        'continuity_mapping',
        CanonicalObject([
          for (final entry in continuities.entries)
            MapEntry(entry.key, CanonicalString(entry.value.value)),
        ]),
      ),
      MapEntry(
        'revision_mapping',
        CanonicalObject([
          for (final entry in revisions.entries)
            MapEntry(entry.key, CanonicalString(entry.value.value)),
        ]),
      ),
      MapEntry('record_and_version_ids', CanonicalString('preserved')),
      MapEntry('workflow_authority', CanonicalString('not imported')),
      MapEntry(
        'next_step',
        CanonicalString(
          'Validate an import preview, then approve that exact preview. The original package is unchanged.',
        ),
      ),
    ]);
  } finally {
    try {
      output?.close();
    } finally {
      try {
        temporary?.deleteSync(recursive: true);
      } finally {
        input.close();
      }
    }
  }
}
