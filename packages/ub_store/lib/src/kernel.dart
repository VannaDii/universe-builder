import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_domain/ub_domain.dart';

import 'candidate_foundation.dart';
import 'candidate_references.dart';
import 'definition_index.dart';
import 'initialization.dart';
import 'journal.dart';
import 'media_bytes.dart';
import 'media_decode.dart' as media;
import 'projections.dart';
import 'revision_input.dart';
import 'workflow_storage.dart';

enum CommitFaultPoint {
  versions,
  changes,
  head,
  projections,
  receipt,
  beforeCommit,
}

/// Internal transaction coordinator. Application publication still requires the
/// service's exact approval and current authority.
final class SqliteKernel {
  SqliteKernel(this.database, UniverseId universe)
    : journal = SqliteJournal(database, universe);
  final Database database;
  final SqliteJournal journal;

  RevisionId commit(
    CommitInput input, {
    Map<String, String?> expectedWorkflow = const {},
    void Function(CommitFaultPoint)? hook,
  }) {
    if (!database.autocommit) {
      throw StateError('Kernel commit owns its transaction');
    }
    database.execute('BEGIN IMMEDIATE');
    try {
      final retry = journal.receipt(input);
      if (retry != null) {
        database.execute('ROLLBACK');
        return retry;
      }
      journal.compareWorkflow(expectedWorkflow);
      if (journal.head(input.continuity) != input.expectedHead) {
        throw const FormatException('Revision conflict');
      }
      // stageVersions enforces the expected head and assignment identities.
      // Decode changed images before any durable version can be admitted.
      for (final change in input.changes) {
        if (change.next?.identity.recordKind == RecordKind.imageAsset) {
          final asset = ImageAssetRecord.fromWire(change.next!.payload);
          final bytes = readRetainedImageBytesSync(
            asset,
            WorkflowStorage(database).get,
          );
          media.validateImageBytes(asset, bytes);
        }
      }
      final base = journal.snapshot(input.continuity, input.expectedHead);
      final candidate = journal.stageVersions(input);
      hook?.call(CommitFaultPoint.versions);
      CandidateFoundation(journal).validate(candidate);
      CandidateReferences(journal).validate(candidate);
      for (final change in input.changes) {
        if (change.next != null) {
          DefinitionIndex(journal).index(change.next!, candidate);
        }
      }
      final initialization = InitializationEvidence(journal);
      final receipts = initialization.pending(input, base, candidate);
      final revision = journal.append(input);
      for (final receipt in receipts) {
        initialization.insert(receipt.admittedAt(revision));
      }
      hook?.call(CommitFaultPoint.changes);
      journal.advanceHead(
        input.continuity,
        input.expectedHead,
        revision,
        candidate,
      );
      hook?.call(CommitFaultPoint.head);
      final generation =
          database
                  .select('SELECT generation FROM projection_state')
                  .single['generation']
              as int;
      for (final change in input.changes) {
        if (change.next != null) {
          RecordProjections(database).project(generation, change.next!);
        }
      }
      hook?.call(CommitFaultPoint.projections);
      journal.writeReceipt(input, revision);
      hook?.call(CommitFaultPoint.receipt);
      hook?.call(CommitFaultPoint.beforeCommit);
      database.execute('COMMIT');
      return revision;
    } catch (_) {
      if (!database.autocommit) database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Runs the same admission/append/projection/receipt path, then rolls it back.
  /// A fresh key prevents an existing receipt from skipping candidate checks.
  List<StoredVersion> preview(CommitInput input) {
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
    var reached = false;
    try {
      commit(
        probe,
        hook: (point) {
          if (point == CommitFaultPoint.beforeCommit) {
            reached = true;
            throw const _PreviewRollback();
          }
        },
      );
    } on _PreviewRollback {
      // Only the deliberate final checkpoint may produce a candidate.
    }
    if (!reached) throw const FormatException('Preview did not run');
    final records = {
      for (final entry
          in journal.snapshot(input.continuity, input.expectedHead).entries)
        entry.key: journal.load(entry.value),
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
    return List.unmodifiable(keys.map((id) => records[id]!));
  }

  bool identityExists(RecordId record) =>
      database.select(
        'SELECT EXISTS(SELECT 1 FROM record_identities WHERE universe_id=? AND id=?) AS present',
        [journal.universe.value, record.value],
      ).single['present'] ==
      1;

  /// Retain an imported original and its metadata atomically. The caller must
  /// authorize import; this does not create or publish a canonical record.
  ({RecordId record, ImageAssetRecord asset}) stageImageBytes(
    Uint8List bytes,
    String originalName,
  ) {
    if (!database.autocommit) {
      throw StateError('Image import owns its transaction');
    }
    final asset = media.inspectImageBytes(bytes, originalName);
    final record = RecordId.generate();
    final entries = <MapEntry<String, CanonicalValue>>[];
    for (var offset = 0; offset < bytes.length; offset += imageChunkBytes) {
      final end = offset + imageChunkBytes < bytes.length
          ? offset + imageChunkBytes
          : bytes.length;
      entries.add(
        MapEntry(
          'image-bytes:${asset.contentDigest}:${offset ~/ imageChunkBytes}',
          CanonicalString(
            base64.encode(Uint8List.sublistView(bytes, offset, end)),
          ),
        ),
      );
    }
    entries.add(MapEntry('image-asset:${record.value}', asset.toWire()));
    WorkflowStorage(database).compareAppend({}, entries);
    return (record: record, asset: asset);
  }

  Uint8List imageBytes(ImageAssetRecord asset) =>
      readRetainedImageBytesSync(asset, WorkflowStorage(database).get);
  String imagePreview(ImageAssetRecord asset) =>
      media.imagePreview(asset, imageBytes(asset));
}

final class _PreviewRollback implements Exception {
  const _PreviewRollback();
}
