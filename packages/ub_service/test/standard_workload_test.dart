@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/ub_store.dart';
import 'package:ub_store/src/relational.dart';

String suffix(int n) => n.toRadixString(16).padLeft(24, '0');
RecordId id(int n) => RecordId.parse('rec_${suffix(n)}');
final universe = UniverseId.parse('unv_${suffix(1)}');
final continuity = ContinuityId.parse('cont_${suffix(1)}');
final principal = PrincipalId.parse('prn_${suffix(1)}');
RecordRef ref(int n) => RecordRef(universe: universe, record: id(n));

/// The same already-admitted storage/evaluator workload as the transitional
/// Rust test, built directly in the normative Dart store without legacy import.
RevisionId seed(OwnedSqliteDatabase package, Map<RecordId, String> digests) {
  final kernel = SqliteKernel(package.database, universe);
  final changes = <Assignment>[];
  void add(int n, RecordPayload payload) {
    final row = StoredVersion.build(
      RecordVersionId.parse('ver_${suffix(n)}'),
      RecordIdentity(
        universeId: universe,
        recordId: id(n),
        recordKind: payload.recordKind,
      ),
      payload.toWire(),
    );
    digests[row.identity.recordId] = row.digest;
    changes.add(Assignment(recordId: row.identity.recordId, next: row));
  }

  add(
    1,
    RepresentedContextRecord(
      universe: universe,
      kind: const ObjectiveContext(),
      labels: {'en': 'Objective'},
    ),
  );
  add(
    2,
    PropertyRecord(
      namespace: 'scale',
      key: 'member',
      labels: {},
      value: const SimpleValueShape(SimpleShapeKind.integer),
      multiplicity: Multiplicity.multiple,
      persistence: PersistenceSemantics.unspecified,
      exclusive: false,
      symmetric: false,
      transitive: false,
    ),
  );
  final scope = Scope(
    context: ref(1),
    applicability: const UniverseApplicability(),
  );
  for (var entity = 0; entity < 10000; entity++) {
    add(
      100 + entity,
      EntityRecord(
        names: [],
        classificationResolution: ClassificationResolution.unclassified,
        worldAssociations: [],
        labels: {'en': 'Character $entity'},
        metadata: {},
      ),
    );
    for (var value = 0; value < 20; value++) {
      final n = 20000 + entity * 40 + value * 2;
      add(
        n,
        PropositionRecord(
          subject: ref(100 + entity),
          predicate: ref(2),
          value: IntegerValue('$value'),
          context: ref(1),
          quantification: Quantification.particular,
        ),
      );
      add(
        n + 1,
        AssertionRecord(
          attributeMode: AttributeMode.instance,
          proposition: ref(n),
          polarity: Polarity.support,
          scope: scope,
          validity: const UnspecifiedValidity(),
          persistence: PersistenceSemantics.unspecified,
          precision: Precision.exact,
          basis: const AuthorDecisionBasis('Authored workload member'),
        ),
      );
    }
    if ((entity + 1) % 1000 == 0) {
      stdout.writeln(
        'standard: generated ${entity + 1}/10000 entities and their assertions',
      );
    }
  }
  for (var n = 0; n < 2000; n++) {
    add(
      500000 + n,
      RuleRecord(
        namespace: 'scale',
        key: 'member-$n',
        labels: {},
        kind: RuleKind.physicalConstraint,
        commitPolicy: CommitPolicy.alwaysBlock,
        applicability: const UniverseApplicability(),
        targetPredicates: ['scale:member'],
        expression: ClaimExpr(
          subject: RecordOperand(ref(100 + n)),
          predicate: 'scale:member',
          value: ValueOperand(IntegerValue('${n % 20}')),
          polarity: Polarity.support,
        ),
        capabilities: ['basic.v1'],
        executable: true,
        validity: const UnspecifiedValidity(),
      ),
    );
  }
  expect(changes.length, 412002);
  final writing = Stopwatch()..start();
  stdout.writeln('standard: storing 412002 records');
  // A bulk initial package is the workload fixture, not an application commit.
  // Keep the production 100-change commit bound intact. All bodies still use
  // the normative codec, and ordinary recovery validates/rebuilds this package.
  final revision = RevisionId.generate();
  final membership = {
    for (final change in changes) change.recordId: change.next!.versionId,
  };
  final digest = canonicalDigest(
    CanonicalObject([
      for (final entry in membership.entries)
        MapEntry(entry.key.value, CanonicalString(entry.value.value)),
    ]),
  );
  final db = package.database;
  db.execute('BEGIN IMMEDIATE');
  db.execute('INSERT INTO universes(id,name) VALUES(?,?)', [
    universe.value,
    'Standard workload',
  ]);
  db.execute('INSERT INTO continuities VALUES(?,?,?,NULL)', [
    universe.value,
    continuity.value,
    revision.value,
  ]);
  db.execute(
    "INSERT INTO commits VALUES(?,?,?,NULL,0,?,'fixture import','Standard scale and recovery',?)",
    [universe.value, revision.value, continuity.value, principal.value, digest],
  );
  final codec = RelationalCodec(db);
  for (var i = 0; i < changes.length; i++) {
    final row = changes[i].next!;
    db.execute('INSERT INTO record_identities VALUES(?,?,?)', [
      universe.value,
      row.identity.recordId.value,
      row.identity.recordKind.wireName,
    ]);
    final body = codec.put('Payload', row.payload);
    db.execute('INSERT INTO record_versions VALUES(?,?,?,?,?,?)', [
      universe.value,
      row.versionId.value,
      row.identity.recordId.value,
      row.identity.recordKind.wireName,
      body,
      row.digest,
    ]);
    db.execute('INSERT INTO commit_changes VALUES(?,?,?,NULL,?)', [
      universe.value,
      revision.value,
      row.identity.recordId.value,
      row.versionId.value,
    ]);
    if ((i + 1) % 40000 == 0) {
      stdout.writeln(
        'standard: stored ${i + 1}/${changes.length} records (${writing.elapsedMilliseconds} ms)',
      );
    }
  }
  kernel.journal.setHeadProjection(continuity, revision, membership);
  db.execute('COMMIT');
  stdout.writeln(
    'standard: initial package stored; recovering projections and validating retained data',
  );
  package.recover();
  return revision;
}

void main() {
  test(
    'standard workload preserves history, indexed evaluation, ten continuities and complete backup/restore',
    () {
      final root = Directory('/tmp').createTempSync('ub-standard-workload-');
      final path = '${root.path}/package.sqlite';
      OwnedSqliteDatabase? package;
      final total = Stopwatch()..start();
      void measured(String phase, Stopwatch watch) =>
          stdout.writeln('standard: $phase ${watch.elapsedMilliseconds} ms');
      try {
        final digests = <RecordId, String>{};
        package = OwnedSqliteDatabase.create(path);
        var phase = Stopwatch()..start();
        final revision = seed(package, digests);
        measured('generate and store', phase);
        final kernel = SqliteKernel(package.database, universe);
        phase = Stopwatch()..start();
        package.database.execute('BEGIN IMMEDIATE');
        for (var n = 2; n <= 10; n++) {
          kernel.journal.branch(
            ContinuityId.parse('cont_${suffix(n)}'),
            continuity,
            revision,
            principal,
          );
        }
        package.database.execute('COMMIT');
        final heads = kernel.journal.heads();
        expect(heads.length, 10);
        measured('branches', phase);
        List<RecordVersion> read(SqliteJournal journal) {
          final membership = journal.snapshot(continuity, revision);
          expect(membership.length, 412002);
          return [
            for (final version in membership.values)
              () {
                final row = journal.load(version);
                expect(
                  row.digest,
                  digests[row.identity.recordId],
                  reason: row.identity.recordId.value,
                );
                return RecordVersion.fromWire(row.toCanonical());
              }(),
          ];
        }

        phase = Stopwatch()..start();
        final records = read(kernel.journal);
        measured('snapshot read', phase);
        phase = Stopwatch()..start();
        final index = EvaluationIndex(records);
        measured('evaluation index', phase);
        final frame = Frame(
          universe: universe,
          continuity: continuity,
          revision: revision,
          context: ref(1),
          time: const TimelessFrameTime(),
          perspective: const AuthorPerspective(),
        );
        final indexed = EvaluationContext(
          frame: frame,
          baseSnapshot: records,
          index: index,
          worldScope: [],
        );
        final reference = EvaluationContext(
          frame: frame,
          baseSnapshot: records,
          worldScope: [],
        );
        phase = Stopwatch()..start();
        var evaluated = 0;
        for (final record in records.where((r) => r.payload is RuleRecord)) {
          final rule = compileRule(record.identity.recordId, record.payload);
          final result = evaluateRule(rule, indexed);
          expect(result.coverage, EvaluationCoverage.complete);
          expect(result.outcome, EvidenceOutcome.supported);
          if (evaluated % 199 == 0 || evaluated == 1999) {
            expect(
              evaluateRule(rule, reference).coverage,
              isNot(EvaluationCoverage.complete),
            );
          }
          evaluated++;
        }
        expect(evaluated, 2000);
        measured('evaluate 2000 rules', phase);
        final backup = '${root.path}/backup.sqlite';
        phase = Stopwatch()..start();
        package.backup(backup);
        measured('complete backup', phase);
        package.close();
        package = null;
        phase = Stopwatch()..start();
        package = OwnedSqliteDatabase.openExisting(path);
        package.recover();
        final reopened = SqliteJournal(package.database, universe);
        expect(reopened.heads(), heads);
        read(reopened);
        measured('restart and exact read', phase);
        phase = Stopwatch()..start();
        final restored = OwnedSqliteDatabase.stageRestore(backup, root.path);
        try {
          final journal = SqliteJournal(restored.package.database, universe);
          expect(journal.heads(), heads);
          read(journal);
        } finally {
          restored.close();
        }
        measured('restore and exact read', phase);
        stdout.writeln(
          'standard: total ${total.elapsedMilliseconds} ms; package ${File(path).lengthSync()} bytes',
        );
      } finally {
        package?.close();
        root.deleteSync(recursive: true);
      }
    },
    skip: Platform.environment['UB_RUN_STANDARD_WORKLOAD'] != '1'
        ? 'Opt-in: UB_RUN_STANDARD_WORKLOAD=1 dart test test/standard_workload_test.dart'
        : false,
    timeout: const Timeout(Duration(hours: 2)),
  );
}
