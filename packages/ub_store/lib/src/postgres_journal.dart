import 'dart:typed_data';

import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'journal.dart' show Membership, maxRecords, maxVersions, maxChain;
import 'postgres_relational.dart';
import 'postgres_values.dart';
import 'revision_input.dart';
import 'world_names.dart';

/// Internal history primitives in a caller-owned transaction. These do not
/// authorize publication or replace candidate/definition/initialization checks.
/// The kernel must acquire installation authority before [lockUniverse], perform
/// all admission/projection/workflow work, then commit the owning transaction.
final class PostgresJournal {
  PostgresJournal(this._session, this.universe)
    : _schema = postgresUniverseSchema(universe),
      _codec = PostgresRelationalCodec(_session, universe);
  final TxSession _session;
  final UniverseId universe;
  final String _schema;
  final PostgresRelationalCodec _codec;
  bool _locked = false;

  Future<void> lockUniverse() async {
    await _one('SELECT id FROM $_schema.universes WHERE id=\$1 FOR UPDATE', [
      universe.value,
    ]);
    _locked = true;
  }

  void _writeRequired() {
    if (!_locked) throw StateError('Journal write requires the universe lock');
  }

  Future<RevisionId> initialize(
    String name,
    ContinuityId continuity,
    PrincipalId principal,
  ) async {
    selectorKey(name);
    final revision = RevisionId.generate();
    await _execute('INSERT INTO $_schema.universes(id,name) VALUES(\$1,\$2)', [
      universe.value,
      postgresAuthoredText(name),
    ]);
    // An inserted singleton is exclusively owned by this transaction.
    _locked = true;
    await _execute(
      'INSERT INTO $_schema.continuities VALUES(\$1,\$2,\$3,NULL)',
      [universe.value, continuity.value, revision.value],
    );
    await _execute(
      'INSERT INTO $_schema.commits VALUES(\$1,\$2,\$3,NULL,0,\$4,\$5,\$6,\$7)',
      [
        universe.value,
        revision.value,
        continuity.value,
        principal.value,
        postgresAuthoredText('genesis'),
        postgresAuthoredText('genesis'),
        _membershipDigest({}),
      ],
    );
    await setHeadProjection(continuity, revision, {});
    return revision;
  }

  Future<RevisionId> head(ContinuityId continuity) async => RevisionId.parse(
    (await _one(
          'SELECT head_commit FROM $_schema.continuities WHERE universe_id=\$1 AND id=\$2',
          [universe.value, continuity.value],
        ))['head_commit']
        as String,
  );

  Future<Map<ContinuityId, RevisionId>> heads() async => Map.unmodifiable({
    for (final row in await _rows(
      'SELECT id,head_commit FROM $_schema.continuities WHERE universe_id=\$1 ORDER BY id',
      [universe.value],
    ))
      ContinuityId.parse(row['id'] as String): RevisionId.parse(
        row['head_commit'] as String,
      ),
  });

  Future<RevisionId?> receipt(CommitInput input) async {
    _checkInput(input);
    final rows = await _rows(
      "SELECT payload_digest,revision_id FROM $_schema.operation_receipts r WHERE universe_id=\$1 AND principal=\$2 AND operation_kind='commit' AND idempotency_key=\$3 AND NOT EXISTS(SELECT 1 FROM $_schema.historical_receipt h WHERE h.universe_id=r.universe_id AND h.principal=r.principal AND h.operation_kind=r.operation_kind AND h.idempotency_key=r.idempotency_key)",
      [
        universe.value,
        input.principal.value,
        postgresAuthoredText(input.idempotencyKey),
      ],
    );
    if (rows.isEmpty) return null;
    if (rows.single['payload_digest'] != canonicalDigest(input.toCanonical())) {
      throw const FormatException('Idempotency key reused');
    }
    return RevisionId.parse(rows.single['revision_id'] as String);
  }

  Future<Membership> stageVersions(CommitInput input) async {
    _writeRequired();
    _checkInput(input);
    if (await head(input.continuity) != input.expectedHead) {
      throw const FormatException('Revision conflict');
    }
    final membership = Map<RecordId, RecordVersionId>.of(
      await snapshot(input.continuity, input.expectedHead),
    );
    final changed = <RecordId>{};
    for (final change in input.changes) {
      if (!changed.add(change.recordId) ||
          membership[change.recordId] != change.expected) {
        throw const FormatException(
          'Duplicate assignment or prior-version conflict',
        );
      }
      final next = change.next;
      if (next == null) {
        if (change.expected == null) {
          throw const FormatException('Cannot tombstone an absent record');
        }
        membership.remove(change.recordId);
        continue;
      }
      next.verify();
      if (next.identity.universeId != universe ||
          next.identity.recordId != change.recordId) {
        throw const FormatException('Record universe or identity mismatch');
      }
      if (next.toCanonical().toBytes().length > 1048576) {
        throw const FormatException('Record too large');
      }
      await _execute(
        'INSERT INTO $_schema.record_identities VALUES(\$1,\$2,\$3) ON CONFLICT(universe_id,id) DO NOTHING',
        [
          universe.value,
          change.recordId.value,
          next.identity.recordKind.wireName,
        ],
      );
      final row = await _codec.put('Payload', next.payload);
      await _execute(
        'INSERT INTO $_schema.record_versions VALUES(\$1,\$2,\$3,\$4,\$5,\$6)',
        [
          universe.value,
          next.versionId.value,
          change.recordId.value,
          next.identity.recordKind.wireName,
          row,
          next.digest,
        ],
      );
      membership[change.recordId] = next.versionId;
    }
    if (membership.length > maxRecords) {
      throw const FormatException('Record budget exceeded');
    }
    if ((await _one(
              'SELECT count(*) AS n FROM $_schema.record_versions',
              [],
            ))['n']
            as int >
        maxVersions) {
      throw const FormatException('History budget exceeded');
    }
    return Map.unmodifiable(membership);
  }

  Future<RevisionId> append(CommitInput input) async {
    _writeRequired();
    _checkInput(input);
    if (await head(input.continuity) != input.expectedHead) {
      throw const FormatException('Revision conflict');
    }
    final sequence =
        (await _one(
              'SELECT sequence FROM $_schema.commits WHERE universe_id=\$1 AND id=\$2',
              [universe.value, input.expectedHead.value],
            ))['sequence']
            as int;
    if (sequence + 1 >= maxChain) {
      throw const FormatException('Continuity history budget reached');
    }
    final revision = RevisionId.generate();
    await _execute(
      'INSERT INTO $_schema.commits VALUES(\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9)',
      [
        universe.value,
        revision.value,
        input.continuity.value,
        input.expectedHead.value,
        sequence + 1,
        input.principal.value,
        postgresAuthoredText(input.decision),
        postgresAuthoredText(input.reason),
        canonicalDigest(input.toCanonical()),
      ],
    );
    for (final change in input.changes) {
      await _execute(
        'INSERT INTO $_schema.commit_changes VALUES(\$1,\$2,\$3,\$4,\$5)',
        [
          universe.value,
          revision.value,
          change.recordId.value,
          change.expected?.value,
          change.next?.versionId.value,
        ],
      );
      final next = change.next;
      if (next == null) continue;
      if (next.identity.universeId != input.universe ||
          next.identity.recordId != change.recordId) {
        throw const FormatException('World reservation identity mismatch');
      }
      for (final key in WorldNames.keys(next)) {
        final rows = await _rows(
          'SELECT record_id FROM $_schema.world_name_reservations WHERE universe_id=\$1 AND name=\$2',
          [universe.value, key],
        );
        if (rows.isNotEmpty &&
            rows.single['record_id'] != change.recordId.value) {
          throw const FormatException(
            'World name reserved to another identity',
          );
        }
        await _execute(
          'INSERT INTO $_schema.world_name_reservations VALUES(\$1,\$2,\$3,\$4) ON CONFLICT DO NOTHING',
          [universe.value, key, change.recordId.value, revision.value],
        );
      }
    }
    return revision;
  }

  Future<void> advanceHead(
    ContinuityId continuity,
    RevisionId expected,
    RevisionId revision,
    Membership membership,
  ) async {
    _writeRequired();
    if (await head(continuity) != expected) {
      throw const FormatException('Revision conflict');
    }
    await _execute(
      'UPDATE $_schema.continuities SET head_commit=\$1 WHERE universe_id=\$2 AND id=\$3',
      [revision.value, universe.value, continuity.value],
    );
    await setHeadProjection(continuity, revision, membership);
  }

  Future<void> writeReceipt(CommitInput input, RevisionId revision) async {
    _writeRequired();
    _checkInput(input);
    await _execute(
      "INSERT INTO $_schema.operation_receipts VALUES(\$1,\$2,'commit',\$3,\$4,\$5)",
      [
        universe.value,
        input.principal.value,
        postgresAuthoredText(input.idempotencyKey),
        canonicalDigest(input.toCanonical()),
        revision.value,
      ],
    );
  }

  Future<StoredVersion> load(RecordVersionId version) async {
    final row = await _one(
      'SELECT payload_row,record_id,kind,digest FROM $_schema.record_versions WHERE universe_id=\$1 AND id=\$2',
      [universe.value, version.value],
    );
    final result = StoredVersion(
      versionId: version,
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.parse(row['record_id'] as String),
        recordKind: RecordKind.parse(row['kind'] as String),
      ),
      payload: await _codec.get('Payload', row['payload_row']),
      digest: row['digest'] as String,
    );
    result.verify();
    return result;
  }

  Future<Membership> snapshot(
    ContinuityId continuity,
    RevisionId revision,
  ) async => Map.unmodifiable(
    await _resolve(continuity.value, revision.value, <String>{}),
  );

  Future<List<CanonicalObject>> recordHistory(
    ContinuityId continuity,
    RevisionId revision,
    RecordId record,
  ) async {
    await snapshot(continuity, revision);
    String? next = revision.value;
    final seen = <String>{};
    final entries = <CanonicalObject>[];
    while (next != null) {
      if (!seen.add(next) || seen.length > maxChain) {
        throw const FormatException('history chain budget exceeded');
      }
      final commit = await _one(
        'SELECT parent_id,continuity_id,principal,reason FROM $_schema.commits WHERE universe_id=\$1 AND id=\$2',
        [universe.value, next],
      );
      final change = await _rows(
        'SELECT version_id FROM $_schema.commit_changes WHERE universe_id=\$1 AND revision_id=\$2 AND record_id=\$3',
        [universe.value, next, record.value],
      );
      if (change.isNotEmpty) {
        final version = change.single['version_id'] as String?;
        entries.add(
          CanonicalObject([
            MapEntry('record_id', CanonicalString(record.value)),
            MapEntry('revision', CanonicalString(next)),
            MapEntry(
              'continuity',
              CanonicalString(commit['continuity_id'] as String),
            ),
            MapEntry(
              'principal',
              CanonicalString(commit['principal'] as String),
            ),
            MapEntry(
              'reason',
              CanonicalString(
                readPostgresAuthoredText(commit['reason'] as Uint8List),
              ),
            ),
            MapEntry(
              'record',
              version == null
                  ? const CanonicalNull()
                  : (await load(RecordVersionId.parse(version))).toCanonical(),
            ),
          ]),
        );
        if (entries.length > 100) {
          throw const FormatException(
            'record history exceeds 100 changes; select an earlier pinned revision',
          );
        }
      }
      next = commit['parent_id'] as String?;
      next ??=
          (await _one(
                'SELECT baseline_commit FROM $_schema.continuities WHERE universe_id=\$1 AND id=\$2',
                [universe.value, commit['continuity_id']],
              ))['baseline_commit']
              as String?;
    }
    return List.unmodifiable(entries);
  }

  Future<RevisionId> branch(
    ContinuityId id,
    ContinuityId from,
    RevisionId base,
    PrincipalId principal,
  ) async {
    _writeRequired();
    final membership = await snapshot(from, base);
    final existing = await _rows(
      'SELECT baseline_commit FROM $_schema.continuities WHERE universe_id=\$1 AND id=\$2',
      [universe.value, id.value],
    );
    if (existing.isNotEmpty) {
      if (existing.single['baseline_commit'] != base.value) {
        throw const FormatException('Continuity identity has another baseline');
      }
      return RevisionId.parse(
        (await _one(
              'SELECT id FROM $_schema.commits WHERE universe_id=\$1 AND continuity_id=\$2 AND sequence=0',
              [universe.value, id.value],
            ))['id']
            as String,
      );
    }
    final revision = RevisionId.generate();
    await _execute(
      'INSERT INTO $_schema.continuities VALUES(\$1,\$2,\$3,\$4)',
      [universe.value, id.value, revision.value, base.value],
    );
    await _execute(
      'INSERT INTO $_schema.commits VALUES(\$1,\$2,\$3,NULL,0,\$4,\$5,\$6,\$7)',
      [
        universe.value,
        revision.value,
        id.value,
        principal.value,
        postgresAuthoredText('branch'),
        postgresAuthoredText('pinned branch'),
        _membershipDigest(membership),
      ],
    );
    final recovered = await snapshot(id, revision);
    if (recovered.length != membership.length ||
        membership.entries.any(
          (entry) => recovered[entry.key] != entry.value,
        )) {
      throw const FormatException('Branch baseline reconstruction mismatch');
    }
    await setHeadProjection(id, revision, membership);
    return revision;
  }

  Future<Membership> _resolve(
    String continuity,
    String revision,
    Set<String> visited,
  ) async {
    if (visited.length > 64 || !visited.add(continuity)) {
      throw const FormatException('Branch ancestry cycle or depth limit');
    }
    try {
      final baseline =
          (await _one(
                'SELECT baseline_commit FROM $_schema.continuities WHERE universe_id=\$1 AND id=\$2',
                [universe.value, continuity],
              ))['baseline_commit']
              as String?;
      final membership = baseline == null
          ? <RecordId, RecordVersionId>{}
          : await _resolve(
              (await _one(
                    'SELECT continuity_id FROM $_schema.commits WHERE universe_id=\$1 AND id=\$2',
                    [universe.value, baseline],
                  ))['continuity_id']
                  as String,
              baseline,
              visited,
            );
      final chain = <String>[];
      String? next = revision;
      final seen = <String>{};
      int? expected;
      while (next != null) {
        if (chain.length >= maxChain || !seen.add(next)) {
          throw const FormatException(
            'Revision chain cycle or budget exceeded',
          );
        }
        final row = await _one(
          'SELECT parent_id,sequence FROM $_schema.commits WHERE universe_id=\$1 AND continuity_id=\$2 AND id=\$3',
          [universe.value, continuity, next],
        );
        final parent = row['parent_id'] as String?;
        final sequence = row['sequence'] as int;
        if ((expected != null && expected != sequence) ||
            (parent == null && sequence != 0)) {
          throw const FormatException('Broken revision chain');
        }
        expected = sequence - 1;
        chain.add(next);
        next = parent;
      }
      for (final revision in chain.reversed) {
        for (final change in await _rows(
          'SELECT record_id,prior_version,version_id FROM $_schema.commit_changes WHERE universe_id=\$1 AND revision_id=\$2 ORDER BY record_id',
          [universe.value, revision],
        )) {
          final id = RecordId.parse(change['record_id'] as String);
          if (membership[id]?.value != change['prior_version']) {
            throw const FormatException('Historical prior-version mismatch');
          }
          final version = change['version_id'] as String?;
          if (version == null) {
            membership.remove(id);
          } else {
            membership[id] = RecordVersionId.parse(version);
          }
        }
        if (membership.length > maxRecords) {
          throw const FormatException('Snapshot budget exceeded');
        }
      }
      return membership;
    } finally {
      visited.remove(continuity);
    }
  }

  Future<void> setHeadProjection(
    ContinuityId continuity,
    RevisionId revision,
    Membership membership,
  ) async {
    _writeRequired();
    await _execute(
      'DELETE FROM $_schema.head_membership WHERE universe_id=\$1 AND continuity_id=\$2',
      [universe.value, continuity.value],
    );
    final ids = membership.keys.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final id in ids) {
      await _execute(
        'INSERT INTO $_schema.head_membership VALUES(\$1,\$2,\$3,\$4)',
        [universe.value, continuity.value, id.value, membership[id]!.value],
      );
    }
    await _execute(
      'INSERT INTO $_schema.projection_heads VALUES(\$1,\$2,\$3,\$4) ON CONFLICT(universe_id,continuity_id) DO UPDATE SET revision_id=EXCLUDED.revision_id,checksum=EXCLUDED.checksum',
      [
        universe.value,
        continuity.value,
        revision.value,
        _membershipDigest(membership),
      ],
    );
  }

  void _checkInput(CommitInput input) {
    if (input.universe != universe ||
        input.changes.isEmpty ||
        input.changes.length > 100 ||
        input.idempotencyKey.trim().isEmpty ||
        input.decision.trim().isEmpty) {
      throw const FormatException(
        'Invalid commit scope, size, key or decision',
      );
    }
  }

  Future<void> _execute(String sql, List<Object?> parameters) async {
    await _session.execute(sql, parameters: parameters);
  }

  Future<List<Map<String, dynamic>>> _rows(
    String sql,
    List<Object?> parameters,
  ) async => (await _session.execute(
    sql,
    parameters: parameters,
  )).map((row) => row.toColumnMap()).toList();
  Future<Map<String, dynamic>> _one(
    String sql,
    List<Object?> parameters,
  ) async {
    final rows = await _rows(sql, parameters);
    if (rows.length != 1) {
      throw const FormatException('Missing or ambiguous journal row');
    }
    return rows.single;
  }

  String _membershipDigest(Membership membership) => canonicalDigest(
    CanonicalObject([
      for (final entry in membership.entries)
        MapEntry(entry.key.value, CanonicalString(entry.value.value)),
    ]),
  );
}
