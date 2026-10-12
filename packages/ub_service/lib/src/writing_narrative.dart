import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_binding.dart';
import 'writing_contexts.dart';
import 'writing_disclosures.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

/// Compiles narrative metadata against already admitted pinned rows. New works,
/// editions and narrator contexts must be published before later references.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> unchanged,
  List<String> clarifications,
})
compileWritingNarrative({
  required Frame frame,
  required List<RecordVersion> rows,
  required CheckChangesRequest input,
  required List<RecordVersion> Function(ContinuityId, RevisionId) canonAt,
  Set<WorldId>? worldScope,
}) {
  final operations = <DomainOperation>[],
      additions = <String>[],
      unchanged = <String>[],
      clarifications = <String>[];
  final declared = <String>{};
  RecordVersion work(String name) {
    final found = rows
        .where(
          (r) =>
              r.payload is WorkRecord &&
              ((r.payload as WorkRecord).title == name ||
                  (r.payload as WorkRecord).labels.values.contains(name)),
        )
        .toList();
    if (found.length != 1) {
      throw FormatException(
        "Select one accessible existing work named '$name'.",
      );
    }
    return found.single;
  }

  RecordRef narrator(String name, String missing, String invalid) {
    final id = resolveWritingContext(rows, name);
    if (id == null) throw FormatException(missing);
    if (!rows.any(
      (r) =>
          r.identity.recordId == id &&
          r.payload is RepresentedContextRecord &&
          (r.payload as RepresentedContextRecord).kind is NarratorContext &&
          (r.payload as RepresentedContextRecord).chronology != null,
    )) {
      throw FormatException(invalid);
    }
    return RecordRef(universe: frame.universe, record: id);
  }

  RecordRef viewpoint(String name, String message) => RecordRef(
    universe: frame.universe,
    record:
        resolveWritingObject(rows, name, frame) ??
        (throw FormatException(message)),
  );
  List<RecordRef> events(List<String> handles, String message) => [
    for (final handle in handles)
      (() {
        for (final row in rows) {
          if (row.recordVersionId.value == handle) {
            if (row.payload case EventRecord(
              occurrence: SimpleOccurrence(kind: OccurrenceKind.occurred),
            )) {
              return RecordRef(
                universe: frame.universe,
                record: row.identity.recordId,
              );
            }
          }
        }
        throw FormatException(message);
      })(),
  ];
  for (final declaration in input.narrativeWorks) {
    try {
      if (!_nonWhitespace.hasMatch(declaration.name)) {
        throw const FormatException('Name the work explicitly.');
      }
      RecordVersion? existing;
      try {
        existing = work(declaration.name);
      } on FormatException {
        /* New or ambiguous. */
      }
      if (existing != null) {
        if ((existing.payload as WorkRecord).kind != declaration.kind) {
          throw const FormatException(
            'The existing work has another authored kind; this declaration does not revise it.',
          );
        }
        unchanged.add('Existing work: ${declaration.name}');
        continue;
      }
      if (rows.any(
            (r) =>
                r.payload is WorkRecord &&
                ((r.payload as WorkRecord).title == declaration.name ||
                    (r.payload as WorkRecord).labels.values.contains(
                      declaration.name,
                    )),
          ) ||
          !declaration.introduce ||
          worldScope != null ||
          !declared.add('work:${declaration.name}')) {
        throw const FormatException(
          'Select one work or explicitly introduce a unique new work with universe-wide access.',
        );
      }
      operations.add(
        CreateWorkOperation(
          clientRef: RecordId.generate().value,
          record: WorkRecord(
            kind: declaration.kind,
            title: declaration.name,
            labels: {},
            sourceRefs: [],
            versions: [],
            worldAssociations: [],
          ),
        ),
      );
      additions.add(
        'New work: ${declaration.name}. Publish before declaring its edition.',
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  for (final declaration in input.workEditions) {
    try {
      if (!_nonWhitespace.hasMatch(declaration.name)) {
        throw const FormatException('Name the edition explicitly.');
      }
      final selected = work(declaration.work);
      final found = rows
          .where(
            (r) =>
                r.payload is WorkVersionRecord &&
                (r.payload as WorkVersionRecord).work.record ==
                    selected.identity.recordId &&
                (r.payload as WorkVersionRecord).versionLabel ==
                    declaration.name,
          )
          .toList();
      if (found.length == 1) {
        unchanged.add(
          'Existing edition: ${declaration.work} / ${declaration.name}',
        );
        continue;
      }
      if (found.isNotEmpty ||
          !declaration.introduce ||
          worldScope != null ||
          !declared.add('edition:${declaration.work}:${declaration.name}')) {
        throw const FormatException(
          'Select one edition or explicitly introduce it with universe-wide access.',
        );
      }
      operations.add(
        RecordNarrativeReferenceOperation(
          clientRef: RecordId.generate().value,
          record: RecordKind.workVersion,
          payload: WorkVersionRecord(
            work: RecordRef(
              universe: frame.universe,
              record: selected.identity.recordId,
            ),
            versionLabel: declaration.name,
            binding: declaration.binding == WritingEditionBinding.current
                ? BoundWork(frame.continuity, frame.revision)
                : const UnboundWork(),
          ),
        ),
      );
      additions.add(
        'New edition: ${declaration.work} / ${declaration.name}. Publish before referencing it from a scene.',
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  for (final declaration in input.scenes) {
    try {
      if (!_nonWhitespace.hasMatch(declaration.name)) {
        throw const FormatException('Name the scene explicitly.');
      }
      final selected = work(declaration.work);
      final editions = rows
          .where(
            (r) =>
                r.payload is WorkVersionRecord &&
                (r.payload as WorkVersionRecord).work.record ==
                    selected.identity.recordId &&
                (r.payload as WorkVersionRecord).versionLabel ==
                    declaration.edition,
          )
          .toList();
      if (editions.length != 1) {
        throw const FormatException(
          'Select one published accessible edition explicitly.',
        );
      }
      final edition = editions.single;
      final narration = narrator(
        declaration.narrationContext,
        'Select one accessible narration context explicitly.',
        'Select an actual narrator context with explicit authored narration time.',
      );
      final view = declaration.viewpoint == null
          ? null
          : viewpoint(
              declaration.viewpoint!,
              'Select one accessible viewpoint entity explicitly.',
            );
      final depicted = events(
        declaration.depictedEvents,
        'Retrieve the current occurred-event handle; absent/restricted/stale events cannot be linked.',
      );
      final version = VersionRef(
        universe: frame.universe,
        record: edition.identity.recordId,
        version: edition.recordVersionId,
      );
      final payload = SceneRecord(
        workVersion: version,
        sceneId: declaration.name,
        disclosedRecords: bindWritingDisclosures(
          disclosures: declaration.disclosures,
          edition: version,
          frame: frame,
          rows: rows,
          canonAt: canonAt,
        ),
        viewpoint: view,
        narrativePosition: declaration.readerOrder,
        depictedEvents: depicted,
        narrationFrame: narration,
        worldAssociations: [],
      );
      final found = rows
          .where(
            (r) =>
                r.payload is SceneRecord &&
                (r.payload as SceneRecord).workVersion == version &&
                (r.payload as SceneRecord).sceneId == declaration.name,
          )
          .toList();
      if (found.length == 1) {
        if (found.single.payload.toWire().toText() !=
            payload.toWire().toText()) {
          throw const FormatException(
            'This scene already exists with other authored settings; declaration does not revise it.',
          );
        }
        unchanged.add('Existing scene: ${declaration.name}');
        continue;
      }
      if (found.isNotEmpty ||
          !declaration.introduce ||
          worldScope != null ||
          !declared.add(
            'scene:${declaration.work}:${declaration.edition}:${declaration.name}',
          )) {
        throw const FormatException(
          'Select one scene or explicitly introduce it with universe-wide access.',
        );
      }
      operations.add(
        RecordNarrativeReferenceOperation(
          clientRef: RecordId.generate().value,
          record: RecordKind.sceneRef,
          payload: payload,
        ),
      );
      additions.add(
        'Scene: ${declaration.name}. Narration context, depicted events and reader order are separate; no reader disclosure inferred.',
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  final corrected = <RecordId>{};
  for (final correction in input.sceneCorrections) {
    try {
      final found = rows
          .where(
            (r) =>
                r.recordVersionId.value == correction.sceneHandle &&
                r.payload is SceneRecord,
          )
          .toList();
      if (found.isEmpty) {
        throw const FormatException(
          'Retrieve one current accessible scene handle; stale or missing scenes cannot be corrected.',
        );
      }
      final row = found.first;
      if (!_nonWhitespace.hasMatch(correction.reason) ||
          !corrected.add(row.identity.recordId)) {
        throw const FormatException(
          'Explain each scene correction and edit a scene only once per delta.',
        );
      }
      final old = row.payload as SceneRecord;
      final narration = correction.narrationContext == null
          ? old.narrationFrame
          : narrator(
              correction.narrationContext!,
              'Select one accessible narration context.',
              'Select an actual narrator context with explicit narration time.',
            );
      if (correction.clearViewpoint && correction.viewpoint != null ||
          correction.clearReaderOrder && correction.readerOrder != null) {
        throw const FormatException(
          'Choose replacement or explicit clearing, not both.',
        );
      }
      final view = correction.clearViewpoint
          ? null
          : correction.viewpoint == null
          ? old.viewpoint
          : viewpoint(
              correction.viewpoint!,
              'Select one accessible viewpoint.',
            );
      final order = correction.clearReaderOrder
          ? null
          : correction.readerOrder ?? old.narrativePosition;
      final depicted = correction.depictedEvents == null
          ? old.depictedEvents
          : events(
              correction.depictedEvents!,
              'Retrieve current occurred-event handles before linking them.',
            );
      final disclosed = correction.disclosures == null
          ? old.disclosedRecords
          : bindWritingDisclosures(
              disclosures: correction.disclosures!,
              edition: old.workVersion,
              frame: frame,
              rows: rows,
              canonAt: canonAt,
            );
      checkWritingSceneDisclosures(
        edition: old.workVersion,
        disclosures: disclosed,
        rows: rows,
        canonAt: canonAt,
      );
      final replacement = SceneRecord(
        workVersion: old.workVersion,
        sceneId: old.sceneId,
        disclosedRecords: disclosed,
        viewpoint: view,
        narrativePosition: order,
        depictedEvents: depicted,
        narrationFrame: narration,
        worldAssociations: old.worldAssociations,
      );
      if (replacement.toWire().toText() == old.toWire().toText()) {
        unchanged.add('Scene settings unchanged');
        continue;
      }
      operations.add(
        ReviseSceneOperation(
          record: RecordRef(
            universe: frame.universe,
            record: row.identity.recordId,
          ),
          expectedVersion: row.recordVersionId,
          replacement: replacement,
          rationale: correction.reason,
        ),
      );
      additions.add(
        'Historical scene correction; unchanged edition, explicitly selected fields only. Reason: ${correction.reason}',
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    unchanged: List.unmodifiable(unchanged),
    clarifications: List.unmodifiable(clarifications),
  );
}
