import 'dart:async';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_store/ub_store.dart' show StoredVersion, recordDependencies;

import 'proposal_authorization.dart';

const _denied = NotFoundOrNotAccessibleError(message: 'resource');
typedef ContextCanonReader = FutureOr<List<RecordVersion>> Function(
  ContinuityId,
  RevisionId,
);

/// Fictional perspective closure is distinct from application permissions.
/// Reader disclosures and their dependencies must match the edition's canon.
Future<Set<RecordId>> perspectiveRecordIds({
  required List<RecordVersion> records,
  required Frame frame,
  required ContextCanonReader readCanon,
}) async {
  final perspective = frame.perspective;
  if (perspective is AuthorPerspective) {
    if (frame.readerScene != null) {
      throw const InvalidArgumentError(
        field: 'reader_scene',
        message: 'requires reader perspective',
      );
    }
    return Set.unmodifiable(records.map((r) => r.identity.recordId));
  }
  final roots = <RecordId>[];
  List<RecordVersion>? readerCanon;
  if (perspective is CharacterPerspective ||
      perspective is NarratorPerspective) {
    final holder = perspective is CharacterPerspective
        ? perspective.record
        : (perspective as NarratorPerspective).record;
    final matching = records.any(
      (r) =>
          r.identity.recordId == frame.context.record &&
          r.payload is RepresentedContextRecord &&
          switch ((r.payload as RepresentedContextRecord).kind) {
            CharacterContext(:final holder) =>
              perspective is CharacterPerspective &&
                  holder.record == perspective.record,
            NarratorContext(:final narrator) =>
              perspective is NarratorPerspective &&
                  narrator.record == perspective.record,
            _ => false,
          },
    );
    if (!matching || frame.readerScene != null) throw _denied;
    roots.addAll([holder, frame.context.record]);
    for (final row in records) {
      final include = switch (row.payload) {
        AssertionRecord(:final scope, :final validity) =>
          scope.context == frame.context &&
              eventApplies(validity, frame.time, records) != false,
        EpistemicAttitudeRecord(:final holder, :final validity) =>
          holder.record ==
                  (perspective is CharacterPerspective
                      ? perspective.record
                      : (perspective as NarratorPerspective).record) &&
              eventApplies(validity, frame.time, records) != false,
        _ => false,
      };
      if (include) roots.add(row.identity.recordId);
    }
  } else if (perspective is ReaderPerspective) {
    final id = frame.readerScene;
    if (id == null) {
      throw const InvalidArgumentError(
        field: 'reader_scene',
        message: 'reader perspective requires a pinned scene',
      );
    }
    final sceneRows = records.where(
      (r) => r.identity.recordId == id && r.payload is SceneRecord,
    );
    if (sceneRows.isEmpty) throw _denied;
    final scene = sceneRows.first.payload as SceneRecord;
    final position = scene.narrativePosition;
    if (position == null) throw _denied;
    final editions = records.where(
      (r) =>
          r.identity.recordId == scene.workVersion.record &&
          r.recordVersionId == scene.workVersion.version &&
          r.payload is WorkVersionRecord,
    );
    if (editions.isEmpty) throw _denied;
    final binding = (editions.first.payload as WorkVersionRecord).binding;
    if (binding is! BoundWork || binding.continuity != frame.continuity) {
      throw _denied;
    }
    readerCanon = await readCanon(binding.continuity, binding.revision);
    for (final row in records) {
      if (row.payload case SceneRecord(
        :final workVersion,
        :final narrativePosition,
        :final disclosedRecords,
      )) {
        if (workVersion == scene.workVersion &&
            narrativePosition != null &&
            narrativePosition <= position) {
          roots.addAll(disclosedRecords.map((r) => r.record));
        }
      }
    }
  }
  final byId = {for (final row in records) row.identity.recordId: row};
  final ids = <RecordId>{};
  while (roots.isNotEmpty) {
    final id = roots.removeLast();
    if (!ids.add(id)) continue;
    final row = byId[id];
    if (row == null ||
        readerCanon != null &&
            !readerCanon.any(
              (old) =>
                  old.identity.recordId == id &&
                  old.recordVersionId == row.recordVersionId,
            )) {
      throw _denied;
    }
    roots.addAll(
      recordDependencies(
        StoredVersion(
          versionId: row.recordVersionId,
          identity: row.identity,
          payload: row.payload.toWire(),
          digest: row.payloadDigest,
        ),
      ),
    );
    if (roots.length + ids.length > 5000000) {
      throw const UnsupportedSemanticsError(
        message: 'perspective dependency budget exceeded',
      );
    }
  }
  return Set.unmodifiable(ids);
}

Future<Frame> prepareContextFrame({
  required OpenContextRequest request,
  required UniverseId universe,
  required RevisionId revision,
  required List<RecordVersion> records,
  required Set<WorldId>? worldScope,
  required ContextCanonReader readCanon,
}) async {
  if (request.temporalQuery case AtFrameTime(:final time)) {
    if (temporalRelation(time, TemporalRelation.during, time) == null) {
      throw const UnsupportedSemanticsError(
        message: 'temporal query requires an exact or bounded named-calendar interval',
      );
    }
  }
  final visible = visibleRecordIds(records: records, worldScope: worldScope);
  if (request.temporalQuery case AtEventFrameTime(:final event)) {
    final found = records.where(
      (r) =>
          r.identity.recordId == event.record &&
          event.universe == universe &&
          visible.contains(r.identity.recordId) &&
          r.payload is EventRecord,
    );
    if (found.isEmpty) throw _denied;
    final e = found.first.payload as EventRecord;
    if (e.occurrence is! SimpleOccurrence ||
        (e.occurrence as SimpleOccurrence).kind != OccurrenceKind.occurred) {
      throw _denied;
    }
    try {
      exactEventTime(e.time);
    } on EventEvaluationError {
      throw _denied;
    }
  }
  final clocks = [...request.temporalSystems];
  if (request.temporalQuery case AtFrameTime(
    time: ExactTime(:final calendar) || IntervalTime(:final calendar),
  )) {
    clocks.add(calendar);
  }
  for (final calendar in clocks) {
    final id = RecordId.parse(calendar.value.replaceFirst('cal_', 'rec_'));
    if (!records.any(
      (r) =>
          r.identity.recordId == id &&
          r.payload is CalendarRecord &&
          visible.contains(id),
    )) {
      throw _denied;
    }
  }
  bool perspectiveContext(RepresentedContextKind kind) =>
      switch (request.perspective) {
        AuthorPerspective() || ReaderPerspective() => true,
        CharacterPerspective(:final record) =>
          kind is CharacterContext && kind.holder.record == record,
        NarratorPerspective(:final record) =>
          kind is NarratorContext && kind.narrator.record == record,
      };
  final RecordId context;
  if (request.representedContext case ContextIdSelector(:final recordId)) {
    context = recordId;
  } else {
    final name = (request.representedContext as ContextNameSelector).name;
    final found = records
        .where(
          (r) =>
              visible.contains(r.identity.recordId) &&
              r.payload is RepresentedContextRecord &&
              perspectiveContext(
                (r.payload as RepresentedContextRecord).kind,
              ) &&
              (r.identity.recordId.value == name ||
                  (r.payload as RepresentedContextRecord).labels.values
                      .contains(name) ||
                  (r.payload as RepresentedContextRecord).kind
                          is AuthoredContext &&
                      ((r.payload as RepresentedContextRecord).kind
                                  as AuthoredContext)
                              .label ==
                          name),
        )
        .toList();
    if (found.length != 1) throw _denied;
    context = found.single.identity.recordId;
  }
  if (!records.any(
    (r) =>
        r.identity.recordId == context &&
        r.payload is RepresentedContextRecord &&
        visible.contains(context),
  )) {
    throw _denied;
  }
  RecordId? scene;
  if (request.readerScene case ContextIdSelector(:final recordId)) {
    scene = recordId;
  } else if (request.readerScene case ContextNameSelector(:final name)) {
    final found = records
        .where(
          (r) =>
              visible.contains(r.identity.recordId) &&
              r.payload is SceneRecord &&
              (r.payload as SceneRecord).sceneId == name,
        )
        .toList();
    if (found.length != 1) throw _denied;
    scene = found.single.identity.recordId;
  }
  final frame = Frame(
    universe: universe,
    continuity: request.continuityId,
    revision: revision,
    context: RecordRef(universe: universe, record: context),
    time: request.temporalQuery,
    perspective: request.perspective,
    readerScene: scene,
  );
  await perspectiveRecordIds(
    records: records,
    frame: frame,
    readCanon: readCanon,
  );
  return frame;
}
