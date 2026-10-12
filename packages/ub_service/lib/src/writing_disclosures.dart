import 'dart:async';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart';

import 'writing_binding.dart';

WorkVersionRecord _edition(List<RecordVersion> rows, VersionRef edition) {
  for (final row in rows) {
    if (row.identity.recordId == edition.record &&
        row.recordVersionId == edition.version) {
      if (row.payload case final WorkVersionRecord work) return work;
      throw const FormatException('Expected edition');
    }
  }
  throw const FormatException('Select the exact published edition.');
}

/// The service supplies the edition's exact retained canon through [canonAt].
/// Current visible rows must match it through the complete dependency closure.
Future<void> checkWritingSceneDisclosures({
  required VersionRef edition,
  required List<RecordRef> disclosures,
  required List<RecordVersion> rows,
  required FutureOr<List<RecordVersion>> Function(ContinuityId, RevisionId)
  canonAt,
}) async {
  if (disclosures.isEmpty) return;
  final binding = _edition(rows, edition).binding;
  if (binding is! BoundWork) {
    throw const FormatException(
      'Reader disclosures require an edition bound to one canon revision.',
    );
  }
  final canon = await canonAt(binding.continuity, binding.revision);
  final current = <RecordId, RecordVersion>{};
  for (final row in rows) {
    current.putIfAbsent(row.identity.recordId, () => row);
  }
  final pinned = {
    for (final row in canon) (row.identity.recordId, row.recordVersionId),
  };
  final pending = disclosures.map((reference) => reference.record).toList(),
      dependencies = <RecordId>{};
  while (pending.isNotEmpty) {
    final target = pending.removeLast();
    if (!dependencies.add(target)) continue;
    final row = current[target];
    if (row == null) {
      throw const FormatException('Disclosure dependencies are unavailable.');
    }
    if (!pinned.contains((target, row.recordVersionId))) {
      throw const FormatException(
        "Disclosure and its dependencies must match the edition's pinned canon; research that revision or explicitly create a newly bound edition.",
      );
    }
    pending.addAll(
      recordDependencies(
        StoredVersion(
          versionId: row.recordVersionId,
          identity: row.identity,
          payload: row.payload.toWire(),
          digest: row.payloadDigest,
        ),
      ),
    );
    if (dependencies.length + pending.length > 5000000) {
      throw const FormatException('Disclosure dependency budget exceeded');
    }
  }
}

Future<List<RecordRef>> bindWritingDisclosures({
  required List<WritingDisclosure> disclosures,
  required VersionRef edition,
  required Frame frame,
  required List<RecordVersion> rows,
  required FutureOr<List<RecordVersion>> Function(ContinuityId, RevisionId)
  canonAt,
}) async {
  if (disclosures.isEmpty) return [];
  final binding = _edition(rows, edition).binding;
  if (binding is! BoundWork) {
    throw const FormatException(
      'Reader disclosures require an edition bound to one canon revision.',
    );
  }
  if (binding.continuity != frame.continuity) {
    throw const FormatException(
      "Open the edition's authored continuity before selecting disclosures.",
    );
  }
  final result = <RecordRef>[], seen = <RecordId>{};
  for (final disclosure in disclosures) {
    final RecordId id;
    switch (disclosure) {
      case WritingObjectDisclosure(:final name):
        id =
            resolveWritingObject(rows, name, frame) ??
            (throw const FormatException(
              'Select one accessible existing disclosure object.',
            ));
      case WritingFactDisclosure(:final factHandle):
        id = bindWritingAuthoredFact(rows, factHandle).$1.identity.recordId;
      case WritingEventDisclosure(:final eventHandle):
        final events = [
          for (final row in rows)
            if (row.recordVersionId.value == eventHandle)
              if (row.payload case EventRecord(
                occurrence: SimpleOccurrence(kind: OccurrenceKind.occurred),
              ))
                row,
        ];
        if (events.isEmpty) {
          throw const FormatException(
            'Retrieve a current occurred-event disclosure handle.',
          );
        }
        id = events.first.identity.recordId;
    }
    if (seen.add(id)) {
      result.add(RecordRef(universe: frame.universe, record: id));
    }
  }
  await checkWritingSceneDisclosures(
    edition: edition,
    disclosures: result,
    rows: rows,
    canonAt: canonAt,
  );
  return List.unmodifiable(result);
}
