import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_store/ub_store.dart';

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'event', message: message);
StoredVersion _stored(RecordVersion r) => StoredVersion(
  versionId: r.recordVersionId,
  identity: r.identity,
  payload: r.payload.toWire(),
  digest: r.payloadDigest,
);

/// Freezes complete event effects into the exact changes submitted for review.
/// Callers discard a failed compilation; this never writes canonical state.
void freezeEventEffects({
  required UniverseId universe,
  required List<RecordVersion> base,
  required List<Assignment> changes,
}) {
  final candidate = <RecordId, RecordVersion>{
    for (final r in base) r.identity.recordId: r,
  };
  for (final change in changes) {
    final old = candidate[change.recordId]?.payload,
        next = change.next == null
            ? null
            : RecordVersion.fromWire(change.next!.toCanonical());
    if (old is AssertionRecord && old.establishedBy != null ||
        next?.payload is AssertionRecord &&
            (next!.payload as AssertionRecord).establishedBy != null) {
      throw _invalid(
        'generated assertions can only change through their event',
      );
    }
    if (next == null) {
      candidate.remove(change.recordId);
    } else {
      candidate[change.recordId] = next;
    }
  }
  for (final row in candidate.values) {
    final a = row.payload;
    if (a is AssertionRecord && a.basis is InstanceInitializationBasis) {
      final start = (a.basis as InstanceInitializationBasis).start;
      if (changes.any((c) => c.recordId == start.record && c.next == null)) {
        throw _invalid(
          'surviving initialization requires its occurred start; its once-only receipt is retained',
        );
      }
    }
  }
  final ids = candidate.keys.toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  Map<RecordId, AssertionRecord> expected;
  try {
    expected = Map.of(expandEvents(ids.map((id) => candidate[id]!).toList()));
  } on EventEvaluationError catch (e) {
    throw _invalid(e.message);
  }
  for (final old in base) {
    if (old.payload is! AssertionRecord ||
        (old.payload as AssertionRecord).establishedBy == null) {
      continue;
    }
    final next = expected.remove(old.identity.recordId);
    if (next == old.payload) continue;
    changes.add(
      Assignment(
        recordId: old.identity.recordId,
        expected: old.recordVersionId,
        next: next == null
            ? null
            : _stored(
                RecordVersion.build(
                  recordVersionId: RecordVersionId.generate(),
                  identity: old.identity,
                  payload: next,
                ),
              ),
      ),
    );
  }
  for (final entry in expected.entries) {
    if (candidate.containsKey(entry.key)) {
      throw _invalid(
        'generated effect identity collides with an existing record',
      );
    }
    changes.add(
      Assignment(
        recordId: entry.key,
        next: _stored(
          RecordVersion.build(
            recordVersionId: RecordVersionId.generate(),
            identity: RecordIdentity(
              universeId: universe,
              recordId: entry.key,
              recordKind: RecordKind.assertion,
            ),
            payload: entry.value,
          ),
        ),
      ),
    );
  }
}
