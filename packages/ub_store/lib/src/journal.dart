import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'relational.dart';
import 'revision_input.dart';
import 'world_names.dart';
import 'workflow_storage.dart';

typedef Membership = Map<RecordId, RecordVersionId>;
const maxRecords = 500000;
const maxVersions = 1000000;
const maxChain = 10000;

/// Internal journal primitives, never an application commit bypass. The kernel
/// owns the write transaction and must perform factual candidate validation,
/// definition/initialization admission and projection work before it commits.
/// This layer intentionally neither opens packages nor authorizes callers.
final class SqliteJournal {
  SqliteJournal(this.database, this.universe)
    : codec = RelationalCodec(database);
  final Database database;
  final UniverseId universe;
  final RelationalCodec codec;

  void _transactionRequired() {
    if (database.autocommit) {
      throw StateError('Journal write requires an owned transaction');
    }
  }

  RevisionId initialize(
    String name,
    ContinuityId continuity,
    PrincipalId principal,
  ) {
    _transactionRequired();
    selectorKey(name);
    final revision = RevisionId.generate();
    database.execute('INSERT INTO universes(id,name) VALUES(?,?)', [
      universe.value,
      name,
    ]);
    database.execute('INSERT INTO continuities VALUES(?,?,?,NULL)', [
      universe.value,
      continuity.value,
      revision.value,
    ]);
    database.execute(
      "INSERT INTO commits VALUES(?,?,?,NULL,0,?,'genesis','genesis',?)",
      [
        universe.value,
        revision.value,
        continuity.value,
        principal.value,
        _membershipDigest({}),
      ],
    );
    setHeadProjection(continuity, revision, {});
    return revision;
  }

  RevisionId head(ContinuityId continuity) => RevisionId.parse(
    _one('SELECT head_commit FROM continuities WHERE universe_id=? AND id=?', [
          universe.value,
          continuity.value,
        ])['head_commit']
        as String,
  );

  Map<ContinuityId, RevisionId> heads() => Map.unmodifiable({
    for (final row in database.select(
      'SELECT id,head_commit FROM continuities WHERE universe_id=? ORDER BY id',
      [universe.value],
    ))
      ContinuityId.parse(row['id'] as String): RevisionId.parse(
        row['head_commit'] as String,
      ),
  });

  /// Historical receipts marked by transfer cannot authorize a new write or
  /// satisfy an active retry. Exact active retries precede workflow/head checks.
  RevisionId? receipt(CommitInput input) {
    _checkInput(input);
    final rows = database.select(
      "SELECT payload_digest,revision_id FROM operation_receipts WHERE universe_id=? AND principal=? AND operation_kind='commit' AND idempotency_key=? AND NOT EXISTS(SELECT 1 FROM historical_receipt h WHERE h.universe_id=operation_receipts.universe_id AND h.principal=operation_receipts.principal AND h.operation_kind=operation_receipts.operation_kind AND h.idempotency_key=operation_receipts.idempotency_key)",
      [universe.value, input.principal.value, input.idempotencyKey],
    );
    if (rows.isEmpty) return null;
    if (rows.single['payload_digest'] != canonicalDigest(input.toCanonical())) {
      throw const FormatException('Idempotency key reused');
    }
    return RevisionId.parse(rows.single['revision_id'] as String);
  }

  void compareWorkflow(Map<String, String?> expected) =>
      WorkflowStorage(database).compare(expected);

  /// Apply typed bodies inside the owning transaction. The returned candidate
  /// must pass the kernel's factual/identity/reference gates before append.
  Membership stageVersions(CommitInput input) {
    _transactionRequired();
    _checkInput(input);
    if (head(input.continuity) != input.expectedHead) {
      throw const FormatException('Revision conflict');
    }
    final membership = Map<RecordId, RecordVersionId>.of(
      snapshot(input.continuity, input.expectedHead),
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
      database.execute(
        'INSERT INTO record_identities VALUES(?,?,?) ON CONFLICT(universe_id,id) DO NOTHING',
        [
          universe.value,
          change.recordId.value,
          next.identity.recordKind.wireName,
        ],
      );
      final row = codec.put('Payload', next.payload);
      database.execute('INSERT INTO record_versions VALUES(?,?,?,?,?,?)', [
        universe.value,
        next.versionId.value,
        change.recordId.value,
        next.identity.recordKind.wireName,
        row,
        next.digest,
      ]);
      membership[change.recordId] = next.versionId;
    }
    if (membership.length > maxRecords) {
      throw const FormatException('Record budget exceeded');
    }
    final count =
        database.select('SELECT count(*) AS n FROM record_versions').single['n']
            as int;
    if (count > maxVersions) {
      throw const FormatException('History budget exceeded');
    }
    return Map.unmodifiable(membership);
  }

  /// Append only after candidate admission. Name reservations, subsequent
  /// initialization and projections share this uncommitted write.
  RevisionId append(CommitInput input) {
    _transactionRequired();
    _checkInput(input);
    if (head(input.continuity) != input.expectedHead) {
      throw const FormatException('Revision conflict');
    }
    final sequence =
        (_one('SELECT sequence FROM commits WHERE universe_id=? AND id=?', [
              universe.value,
              input.expectedHead.value,
            ])['sequence']
            as int) +
        1;
    if (sequence >= maxChain) {
      throw const FormatException('Continuity history budget reached');
    }
    final revision = RevisionId.generate();
    database.execute('INSERT INTO commits VALUES(?,?,?,?,?,?,?,?,?)', [
      universe.value,
      revision.value,
      input.continuity.value,
      input.expectedHead.value,
      sequence,
      input.principal.value,
      input.decision,
      input.reason,
      canonicalDigest(input.toCanonical()),
    ]);
    for (final change in input.changes) {
      database.execute('INSERT INTO commit_changes VALUES(?,?,?,?,?)', [
        universe.value,
        revision.value,
        change.recordId.value,
        change.expected?.value,
        change.next?.versionId.value,
      ]);
    }
    WorldNames(database).reserve(input, revision);
    return revision;
  }

  void advanceHead(
    ContinuityId continuity,
    RevisionId expected,
    RevisionId revision,
    Membership membership,
  ) {
    _transactionRequired();
    if (head(continuity) != expected) {
      throw const FormatException('Revision conflict');
    }
    database.execute(
      'UPDATE continuities SET head_commit=? WHERE universe_id=? AND id=?',
      [revision.value, universe.value, continuity.value],
    );
    setHeadProjection(continuity, revision, membership);
  }

  void writeReceipt(CommitInput input, RevisionId revision) {
    _transactionRequired();
    _checkInput(input);
    database.execute(
      "INSERT INTO operation_receipts VALUES(?,?,'commit',?,?,?)",
      [
        universe.value,
        input.principal.value,
        input.idempotencyKey,
        canonicalDigest(input.toCanonical()),
        revision.value,
      ],
    );
  }

  StoredVersion load(RecordVersionId version) {
    final row = _one(
      'SELECT payload_row,record_id,kind,digest FROM record_versions WHERE universe_id=? AND id=?',
      [universe.value, version.value],
    );
    final result = StoredVersion(
      versionId: version,
      identity: RecordIdentity(
        universeId: universe,
        recordId: RecordId.parse(row['record_id'] as String),
        recordKind: RecordKind.parse(row['kind'] as String),
      ),
      payload: codec.get('Payload', row['payload_row']),
      digest: row['digest'] as String,
    );
    result.verify();
    return result;
  }

  /// Decode immutable versions in bounded batches, preserving request order
  /// and duplicates. No query or decoded-body cache survives a batch.
  Iterable<StoredVersion> loadMany(Iterable<RecordVersionId> versions) sync* {
    final source = versions.iterator;
    while (true) {
      final batch = <RecordVersionId>[];
      while (batch.length < 50 && source.moveNext()) {
        batch.add(source.current);
      }
      if (batch.isEmpty) return;
      final rows = database.select(
        'SELECT id,payload_row,record_id,kind,digest FROM record_versions WHERE universe_id=? AND id IN (${List.filled(batch.length, '?').join(',')})',
        [universe.value, for (final version in batch) version.value],
      );
      final byId = {for (final row in rows) row['id'] as String: row};
      final pointers = <Object?>[];
      for (final version in batch) {
        final row = byId[version.value];
        if (row == null) {
          throw const FormatException('Missing or ambiguous journal row');
        }
        pointers.add(row['payload_row']);
      }
      final payloads = codec.getMany('Payload', pointers);
      for (var i = 0; i < batch.length; i++) {
        final row = byId[batch[i].value]!;
        final result = StoredVersion(
          versionId: batch[i],
          identity: RecordIdentity(
            universeId: universe,
            recordId: RecordId.parse(row['record_id'] as String),
            recordKind: RecordKind.parse(row['kind'] as String),
          ),
          payload: payloads[i],
          digest: row['digest'] as String,
        );
        result.verify();
        yield result;
      }
    }
  }

  Membership snapshot(ContinuityId continuity, RevisionId revision) =>
      Map.unmodifiable(_resolve(continuity.value, revision.value, <String>{}));

  /// Newest-first changes at a validated pinned revision, including tombstones
  /// and exact fork baselines. The service owns history disclosure admission.
  List<CanonicalObject> recordHistory(
    ContinuityId continuity,
    RevisionId revision,
    RecordId record,
  ) {
    snapshot(continuity, revision);
    String? next = revision.value;
    final seen = <String>{};
    final entries = <CanonicalObject>[];
    while (next != null) {
      if (!seen.add(next) || seen.length > maxChain) {
        throw const FormatException('history chain budget exceeded');
      }
      final commit = _one(
        'SELECT parent_id,continuity_id,principal,reason FROM commits WHERE universe_id=? AND id=?',
        [universe.value, next],
      );
      final change = database.select(
        'SELECT version_id FROM commit_changes WHERE universe_id=? AND revision_id=? AND record_id=?',
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
            MapEntry('reason', CanonicalString(commit['reason'] as String)),
            MapEntry(
              'record',
              version == null
                  ? const CanonicalNull()
                  : load(RecordVersionId.parse(version)).toCanonical(),
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
          _one(
                'SELECT baseline_commit FROM continuities WHERE universe_id=? AND id=?',
                [universe.value, commit['continuity_id']],
              )['baseline_commit']
              as String?;
    }
    return List.unmodifiable(entries);
  }

  /// Caller has already admitted the baseline candidate and owns the write
  /// transaction. A branch pins the exact revision, never the parent's head.
  RevisionId branch(
    ContinuityId id,
    ContinuityId from,
    RevisionId base,
    PrincipalId principal,
  ) {
    _transactionRequired();
    final membership = snapshot(from, base);
    final existing = database.select(
      'SELECT baseline_commit FROM continuities WHERE universe_id=? AND id=?',
      [universe.value, id.value],
    );
    if (existing.isNotEmpty) {
      if (existing.single['baseline_commit'] != base.value) {
        throw const FormatException('Continuity identity has another baseline');
      }
      return RevisionId.parse(
        _one(
              'SELECT id FROM commits WHERE universe_id=? AND continuity_id=? AND sequence=0',
              [universe.value, id.value],
            )['id']
            as String,
      );
    }
    final revision = RevisionId.generate();
    database.execute('INSERT INTO continuities VALUES(?,?,?,?)', [
      universe.value,
      id.value,
      revision.value,
      base.value,
    ]);
    database.execute(
      "INSERT INTO commits VALUES(?,?,?,NULL,0,?,'branch','pinned branch',?)",
      [
        universe.value,
        revision.value,
        id.value,
        principal.value,
        _membershipDigest(membership),
      ],
    );
    final recovered = snapshot(id, revision);
    if (recovered.length != membership.length ||
        membership.entries.any(
          (entry) => recovered[entry.key] != entry.value,
        )) {
      throw const FormatException('Branch baseline reconstruction mismatch');
    }
    setHeadProjection(id, revision, membership);
    return revision;
  }

  Membership _resolve(String continuity, String revision, Set<String> visited) {
    if (visited.length > 64 || !visited.add(continuity)) {
      throw const FormatException('Branch ancestry cycle or depth limit');
    }
    try {
      final baseline =
          _one(
                'SELECT baseline_commit FROM continuities WHERE universe_id=? AND id=?',
                [universe.value, continuity],
              )['baseline_commit']
              as String?;
      final membership = baseline == null
          ? <RecordId, RecordVersionId>{}
          : _resolve(
              _one(
                    'SELECT continuity_id FROM commits WHERE universe_id=? AND id=?',
                    [universe.value, baseline],
                  )['continuity_id']
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
        final row = _one(
          'SELECT parent_id,sequence FROM commits WHERE universe_id=? AND continuity_id=? AND id=?',
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
      for (final rev in chain.reversed) {
        final changes = database.select(
          'SELECT record_id,prior_version,version_id FROM commit_changes WHERE universe_id=? AND revision_id=? ORDER BY record_id',
          [universe.value, rev],
        );
        for (final change in changes) {
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

  void setHeadProjection(
    ContinuityId continuity,
    RevisionId revision,
    Membership membership,
  ) {
    _transactionRequired();
    database.execute(
      'DELETE FROM head_membership WHERE universe_id=? AND continuity_id=?',
      [universe.value, continuity.value],
    );
    final ids = membership.keys.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    for (final id in ids) {
      database.execute('INSERT INTO head_membership VALUES(?,?,?,?)', [
        universe.value,
        continuity.value,
        id.value,
        membership[id]!.value,
      ]);
    }
    database.execute(
      'INSERT OR REPLACE INTO projection_heads VALUES(?,?,?,?)',
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

  Row _one(String sql, List<Object?> arguments) {
    final rows = database.select(sql, arguments);
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
