@TestOn('vm')
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/src/postgres_canonical_integrity.dart';
import 'package:ub_store/src/postgres_export.dart';
import 'package:ub_store/src/postgres_import.dart';
import 'package:ub_store/src/postgres_journal.dart';
import 'package:ub_store/src/postgres_kernel_schema.dart';
import 'package:ub_store/src/postgres_projection_recovery.dart';
import 'package:ub_store/src/postgres_projection_schema.dart';
import 'package:ub_store/src/postgres_schema.dart';
import 'package:ub_store/src/postgres_semantic_schema.dart';
import 'package:ub_store/src/postgres_values.dart';
import 'package:ub_store/src/postgres_workflow_schema.dart';

import 'standard_workload_test.dart' as fixture;

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  test(
    'full PostgreSQL workload imports, evaluates, restarts and restores exact retained data',
    () async {
      final endpoint = Endpoint(
        host: '127.0.0.1',
        port: port!,
        database: 'ub_disposable',
        username: 'postgres',
      );
      const settings = ConnectionSettings(sslMode: SslMode.disable);
      final observer = await Connection.open(endpoint, settings: settings);
      Connection? connection;
      OwnedSqliteDatabase? source;
      Directory? root;
      var created = false;
      final schema = postgresUniverseSchema(fixture.universe);
      final total = Stopwatch()..start();
      void measured(String phase, Stopwatch watch) => stdout.writeln(
        'postgres standard: $phase ${watch.elapsedMilliseconds} ms',
      );
      try {
        // Run alone against the disposable database; never overwrite a namespace.
        expect(
          (await observer.execute(
            'SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname=\$1)',
            parameters: ['ub_${fixture.universe.value}'],
          )).single.single,
          isFalse,
        );
        root = Directory('/tmp').createTempSync('ub-postgres-standard-');
        stdout.writeln('postgres standard: disposable fixture ${root.path}');
        source = OwnedSqliteDatabase.create('${root.path}/source.sqlite');
        final digests = <RecordId, String>{};
        var phase = Stopwatch()..start();
        // Already-admitted normative input, not an application publication.
        // The production 100-change commit bound remains unchanged.
        final revision = fixture.seed(source, digests);
        final sourceJournal = SqliteJournal(source.database, fixture.universe);
        source.database.execute('BEGIN IMMEDIATE');
        for (var n = 2; n <= 10; n++) {
          sourceJournal.branch(
            ContinuityId.parse('cont_${fixture.suffix(n)}'),
            fixture.continuity,
            revision,
            fixture.principal,
          );
        }
        source.database.execute('COMMIT');
        final heads = sourceJournal.heads();
        final membership = sourceJournal.snapshot(fixture.continuity, revision);
        expect(membership, hasLength(412004));
        expect(heads, hasLength(10));
        measured('prepare SQLite source', phase);
        connection = await Connection.open(endpoint, settings: settings);
        phase = Stopwatch()..start();
        await connection.runTx((tx) async {
          await tx.execute('CREATE SCHEMA $schema');
          created = true;
          for (final sql in [
            ...postgresBodySchema(fixture.universe),
            ...postgresKernelSchema(fixture.universe),
            ...postgresSemanticSchema(fixture.universe),
            ...postgresWorkflowSchema(fixture.universe),
            ...postgresProjectionSchema(fixture.universe),
          ]) {
            await tx.execute(sql);
          }
        });
        measured('provision namespace', phase);
        phase = Stopwatch()..start();
        await connection.runTx(
          (tx) => PostgresLogicalImport(tx, fixture.universe).copy(source!),
        );
        measured('import all retained data', phase);
        expect(
          (await observer.execute(
            'SELECT count(*) FROM $schema.record_versions',
          )).single.single,
          412004,
        );

        Future<List<RecordVersion>> read(
          PostgresJournal journal, {
          bool materialize = false,
        }) async {
          expect(await journal.heads(), heads);
          expect(
            await journal.snapshot(fixture.continuity, revision),
            membership,
          );
          final records = <RecordVersion>[];
          var count = 0;
          await for (final row in journal.loadMany(membership.values)) {
            expect(row.versionId, membership[row.identity.recordId]);
            expect(
              row.digest,
              digests[row.identity.recordId],
              reason: row.identity.recordId.value,
            );
            if (materialize) {
              records.add(RecordVersion.fromWire(row.toCanonical()));
            }
            count++;
          }
          expect(count, 412004);
          return records;
        }

        phase = Stopwatch()..start();
        await connection.runTx((tx) async {
          await PostgresCanonicalIntegrity(
            tx,
            fixture.universe,
          ).verifyComplete();
          await PostgresProjectionRecovery(tx, fixture.universe).rebuild();
        });
        measured('validate and recover projections', phase);
        phase = Stopwatch()..start();
        await connection.runTx((tx) async {
          final records = await read(
            PostgresJournal(tx, fixture.universe),
            materialize: true,
          );
          final policy = UniversePolicySelection.fromRecords(
            fixture.universe,
            records,
          );
          expect(policy.rules, isEmpty);
          expect(policy.inactiveRuleIds, isEmpty);
          final index = EvaluationIndex(records);
          final context = EvaluationContext(
            frame: Frame(
              universe: fixture.universe,
              continuity: fixture.continuity,
              revision: revision,
              context: fixture.ref(1),
              time: const TimelessFrameTime(),
              perspective: const AuthorPerspective(),
            ),
            baseSnapshot: records,
            index: index,
            worldScope: [],
          );
          var evaluated = 0;
          for (final row in records.where((r) => r.payload is RuleRecord)) {
            final result = evaluateRule(
              compileRule(row.identity.recordId, row.payload),
              context,
            );
            expect(result.coverage, EvaluationCoverage.complete);
            expect(result.outcome, EvidenceOutcome.supported);
            evaluated++;
          }
          expect(evaluated, 2000);
        });
        measured('exact snapshot and 2000 indexed rules', phase);
        await connection.close();
        connection = null;
        phase = Stopwatch()..start();
        connection = await Connection.open(endpoint, settings: settings);
        await connection.runTx((tx) async {
          await PostgresCanonicalIntegrity(tx, fixture.universe).verify();
          await PostgresProjectionRecovery(tx, fixture.universe).rebuild();
          await read(PostgresJournal(tx, fixture.universe));
        });
        measured('restart and exact read', phase);
        final backup = '${root.path}/portable-backup.sqlite';
        phase = Stopwatch()..start();
        await connection.runTx(
          (tx) => PostgresLogicalExport(tx, fixture.universe).backup(backup),
        );
        measured('complete portable backup', phase);
        phase = Stopwatch()..start();
        final restored = OwnedSqliteDatabase.stageRestore(backup, root.path);
        try {
          expect(
            restored.package.database
                .select('SELECT count(*) AS n FROM record_versions')
                .single['n'],
            412004,
          );
          final journal = SqliteJournal(
            restored.package.database,
            fixture.universe,
          );
          expect(journal.heads(), heads);
          expect(journal.snapshot(fixture.continuity, revision), membership);
          var count = 0;
          for (final row in journal.loadMany(membership.values)) {
            expect(row.versionId, membership[row.identity.recordId]);
            expect(row.digest, digests[row.identity.recordId]);
            count++;
          }
          expect(count, 412004);
        } finally {
          restored.close();
        }
        measured('restore and exact read', phase);
        stdout.writeln(
          'postgres standard: total ${total.elapsedMilliseconds} ms',
        );
      } finally {
        try {
          await connection?.close();
          if (created) {
            await observer.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
          }
        } finally {
          await observer.close();
          source?.close();
          root?.deleteSync(recursive: true);
        }
      }
    },
    skip:
        port == null || Platform.environment['UB_RUN_STANDARD_WORKLOAD'] != '1'
        ? 'Set UB_TEST_POSTGRES_PORT and UB_RUN_STANDARD_WORKLOAD=1 for this full disposable workload'
        : false,
    timeout: const Timeout(Duration(hours: 8)),
  );
}
