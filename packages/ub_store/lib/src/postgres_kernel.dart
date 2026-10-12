import 'dart:async';

import 'package:postgres/postgres.dart';
import 'package:ub_domain/ub_domain.dart';

import 'kernel.dart' show CommitFaultPoint;
import 'media_bytes.dart';
import 'media_decode.dart' as media;
import 'postgres_candidate_admission.dart';
import 'postgres_definition_index.dart';
import 'postgres_initialization.dart';
import 'postgres_journal.dart';
import 'postgres_projection_recovery.dart';
import 'postgres_projections.dart';
import 'postgres_values.dart';
import 'postgres_workflow_storage.dart';
import 'revision_input.dart';

/// Internal publication coordinator within a caller-owned transaction. The
/// service must lock current installation authority before invoking this and
/// supply exactly-approved input. This class cannot grant approval or rights.
/// Commit exceptions must escape the owning transaction. A returned revision
/// establishes durability only after that caller commits successfully.
final class PostgresKernel {
  PostgresKernel(this._session, this.universe)
    : journal = PostgresJournal(_session, universe);
  final TxSession _session;
  final UniverseId universe;
  final PostgresJournal journal;

  Future<List<StoredVersion>> search(
    ContinuityId continuity,
    RevisionId revision,
    String query,
  ) => PostgresProjectionRecovery(
    _session,
    universe,
  ).search(continuity, revision, query);

  Future<List<InitializationReceipt>> initializationReceiptsAt(
    ContinuityId continuity,
    RevisionId revision,
  ) => PostgresInitializationEvidence(
    _session,
    universe,
  ).readAt(continuity, revision);

  Future<RevisionId> commit(
    CommitInput input, {
    Map<String, String?> expectedWorkflow = const {},
    FutureOr<void> Function(CommitFaultPoint)? hook,
  }) async {
    await journal.lockUniverse();
    final retry = await journal.receipt(input);
    if (retry != null) return retry;
    await journal.compareWorkflow(expectedWorkflow);
    if (await journal.head(input.continuity) != input.expectedHead) {
      throw const FormatException('Revision conflict');
    }
    final workflow = PostgresWorkflowStorage(_session, universe);
    for (final change in input.changes) {
      if (change.next?.identity.recordKind == RecordKind.imageAsset) {
        final asset = ImageAssetRecord.fromWire(change.next!.payload);
        final bytes = await readRetainedImageBytes(asset, workflow.get);
        media.validateImageBytes(asset, bytes);
      }
    }
    final base = await journal.snapshot(input.continuity, input.expectedHead);
    final candidate = await journal.stageVersions(input);
    await hook?.call(CommitFaultPoint.versions);
    await PostgresCandidateAdmission(journal).validate(candidate);
    for (final change in input.changes) {
      if (change.next != null) {
        await PostgresDefinitionIndex(
          _session,
          universe,
        ).index(change.next!, candidate);
      }
    }
    final initialization = PostgresInitializationEvidence(_session, universe);
    final receipts = await initialization.pending(input, base, candidate);
    final revision = await journal.append(input);
    for (final receipt in receipts) {
      await initialization.insert(receipt.admittedAt(revision));
    }
    await hook?.call(CommitFaultPoint.changes);
    await journal.advanceHead(
      input.continuity,
      input.expectedHead,
      revision,
      candidate,
    );
    await hook?.call(CommitFaultPoint.head);
    final generation =
        (await _session.execute(
              'SELECT generation FROM ${postgresUniverseSchema(universe)}.projection_state',
            )).single.single
            as int;
    for (final change in input.changes) {
      if (change.next != null) {
        await PostgresRecordProjections(
          _session,
          universe,
        ).project(generation, change.next!);
      }
    }
    await hook?.call(CommitFaultPoint.projections);
    await journal.writeReceipt(input, revision);
    await hook?.call(CommitFaultPoint.receipt);
    // The owning caller still must commit this transaction. Awaited hooks are
    // also inside its lock/rollback boundary; cancellation never replays input.
    await hook?.call(CommitFaultPoint.beforeCommit);
    return revision;
  }

  /// Exercises the exact admission/append/projection/receipt path inside a
  /// savepoint, then discards it. Authority/universe locks acquired before that
  /// savepoint remain held by the outer transaction.
  Future<List<StoredVersion>> preview(CommitInput input) async {
    await journal.lockUniverse();
    final name = 'ub_preview_${OperationId.generate().value}';
    final probe = CommitInput(
      universe: input.universe,
      continuity: input.continuity,
      expectedHead: input.expectedHead,
      principal: input.principal,
      decision: input.decision,
      reason: input.reason,
      idempotencyKey: 'preview:${RevisionId.generate().value}',
      changes: input.changes,
    );
    await _session.execute('SAVEPOINT $name');
    var reached = false;
    try {
      await commit(
        probe,
        hook: (point) {
          if (point == CommitFaultPoint.beforeCommit) {
            reached = true;
            throw const _PreviewRollback();
          }
        },
      );
    } on _PreviewRollback {
      // Only the deliberate final checkpoint yields a candidate.
    } finally {
      await _session.execute('ROLLBACK TO SAVEPOINT $name');
      await _session.execute('RELEASE SAVEPOINT $name');
    }
    if (!reached) throw const FormatException('Preview did not run');
    final records = {
      for (final entry in (await journal.snapshot(
        input.continuity,
        input.expectedHead,
      )).entries)
        entry.key: await journal.load(entry.value),
    };
    for (final change in input.changes) {
      if (change.next == null) {
        records.remove(change.recordId);
      } else {
        records[change.recordId] = change.next!;
      }
    }
    final keys = records.keys.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return List.unmodifiable([for (final key in keys) records[key]!]);
  }
}

final class _PreviewRollback implements Exception {
  const _PreviewRollback();
}
