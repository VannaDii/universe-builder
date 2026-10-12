import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'writing_disclosures_test.dart' as disclosures;
import 'writing_contexts_test.dart' as contexts;

List<RecordVersion> rows() => [
  for (final row in disclosures.rows())
    row.identity.recordId == f.id(70)
        ? f.row(
            70,
            f.patch<EventRecord>(row.payload as EventRecord, {
              'expansionVersion': CanonicalString(eventExpansionVersion),
            }),
          )
        : row,
  f.row(
    61,
    WorkRecord(
      kind: WorkKind.novel,
      title: 'Chronicle',
      labels: {'en': 'Book'},
      sourceRefs: [],
      versions: [],
      worldAssociations: [],
    ),
  ),
  f.row(
    62,
    RepresentedContextRecord(
      universe: f.u,
      kind: NarratorContext(f.ref(80)),
      chronology: contexts.start.$1,
      labels: {'en': 'Narration'},
    ),
  ),
];
CheckChangesRequest delta({
  List<WritingNarrativeWork> works = const [],
  List<WritingWorkEdition> editions = const [],
  List<WritingScene> scenes = const [],
  List<WritingSceneCorrection> corrections = const [],
}) => CheckChangesRequest(
  universe: const Selector('World'),
  contextId: ContextId.generate(),
  narrativeWorks: works,
  workEditions: editions,
  scenes: scenes,
  sceneCorrections: corrections,
);
WritingScene scene({
  String name = 'Opening',
  String narration = 'Narration',
  String? viewpoint = 'Mara',
  String event = '',
  BigInt? order,
  List<WritingDisclosure> selected = const [],
}) => WritingScene(
  name: name,
  introduce: true,
  work: 'Book',
  edition: 'First',
  narrationContext: narration,
  viewpoint: viewpoint,
  readerOrder: order,
  depictedEvents: event.isEmpty ? [] : [event],
  disclosures: selected,
);

void main() {
  test('works and editions require separate published dependencies and explicit universe-wide introductions', () {
    final base = rows();
    final result = compileWritingNarrative(
      frame: disclosures.frame,
      rows: base,
      canonAt: (_, _) => base,
      input: delta(
        works: [
          WritingNarrativeWork(
            name: 'Chronicle',
            introduce: false,
            kind: WorkKind.novel,
          ),
          WritingNarrativeWork(
            name: 'New book',
            introduce: true,
            kind: WorkKind.story,
          ),
        ],
        editions: [
          WritingWorkEdition(
            work: 'New book',
            name: 'First',
            introduce: true,
            binding: WritingEditionBinding.current,
          ),
          WritingWorkEdition(
            work: 'Chronicle',
            name: 'Second',
            introduce: true,
            binding: WritingEditionBinding.current,
          ),
          WritingWorkEdition(
            work: 'Chronicle',
            name: 'Draft',
            introduce: true,
            binding: WritingEditionBinding.unbound,
          ),
        ],
      ),
    );
    expect(result.operations, hasLength(3));
    expect(result.unchanged, ['Existing work: Chronicle']);
    expect(result.clarifications.single, contains('existing work'));
    final bound =
        (result.operations[1] as RecordNarrativeReferenceOperation).payload
            as WorkVersionRecord;
    expect(
      bound.binding.toWire().toText(),
      BoundWork(
        disclosures.frame.continuity,
        disclosures.frame.revision,
      ).toWire().toText(),
    );
    expect(
      ((result.operations[2] as RecordNarrativeReferenceOperation).payload
              as WorkVersionRecord)
          .binding,
      isA<UnboundWork>(),
    );
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: result.operations,
    );
    expect(candidate.length, base.length + 3);
    final scoped = compileWritingNarrative(
      frame: disclosures.frame,
      rows: base,
      canonAt: (_, _) => base,
      worldScope: {},
      input: delta(
        works: [
          WritingNarrativeWork(
            name: 'Forbidden',
            introduce: true,
            kind: WorkKind.story,
          ),
          WritingNarrativeWork(
            name: 'Chronicle',
            introduce: true,
            kind: WorkKind.play,
          ),
        ],
      ),
    );
    expect(scoped.operations, isEmpty);
    expect(scoped.clarifications, hasLength(2));
  });

  test('scenes retain exact edition narrator event and reader order without inferred disclosure', () {
    final base = rows();
    final request = scene(
      event: f.ver(70).value,
      order: BigInt.parse('9007199254740993'),
    );
    final result = compileWritingNarrative(
      frame: disclosures.frame,
      rows: base,
      canonAt: (_, _) => throw StateError('no inferred disclosures'),
      input: delta(scenes: [request]),
    );
    expect(result.clarifications, isEmpty);
    final payload =
        (result.operations.single as RecordNarrativeReferenceOperation).payload
            as SceneRecord;
    expect(payload.workVersion, disclosures.version);
    expect(payload.narrationFrame, f.ref(62));
    expect(payload.viewpoint, f.ref(80));
    expect(payload.depictedEvents, [f.ref(70)]);
    expect(payload.disclosedRecords, isEmpty);
    expect(payload.narrativePosition, BigInt.parse('9007199254740993'));
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: result.operations,
    );
    expect(
      candidate.where((r) => r.payload is AssertionRecord).length,
      base.where((r) => r.payload is AssertionRecord).length,
    );
    final duplicate = compileWritingNarrative(
      frame: disclosures.frame,
      rows: candidate,
      canonAt: (_, _) => base,
      input: delta(
        scenes: [
          request,
          scene(event: f.ver(70).value),
        ],
      ),
    );
    expect(duplicate.operations, isEmpty);
    expect(duplicate.unchanged, ['Existing scene: Opening']);
    expect(duplicate.clarifications.single, contains('does not revise'));
    for (final invalid in [
      scene(narration: 'Root'),
      scene(viewpoint: 'Hidden'),
      scene(event: f.id(70).value),
      scene(event: f.ver(71).value),
    ]) {
      final denied = compileWritingNarrative(
        frame: disclosures.frame,
        rows: base,
        canonAt: (_, _) => base,
        input: delta(scenes: [invalid]),
      );
      expect(denied.operations, isEmpty);
      expect(denied.clarifications, hasLength(1));
    }
  });

  test('scene corrections preserve edition and omitted fields and require exact current handles', () {
    final original = SceneRecord(
      workVersion: disclosures.version,
      sceneId: 'Opening',
      narrationFrame: f.ref(62),
      viewpoint: f.ref(80),
      narrativePosition: BigInt.from(9),
      depictedEvents: [f.ref(70)],
      worldAssociations: [],
    );
    final base = [...rows(), f.row(63, original)];
    final result = compileWritingNarrative(
      frame: disclosures.frame,
      rows: base,
      canonAt: (_, _) => base,
      input: delta(
        corrections: [
          WritingSceneCorrection(
            sceneHandle: f.ver(63).value,
            reason: 'Change reader sequence',
            readerOrder: BigInt.parse('18446744073709551615'),
          ),
        ],
      ),
    );
    expect(result.clarifications, isEmpty);
    final operation = result.operations.single as ReviseSceneOperation;
    expect(operation.expectedVersion, f.ver(63));
    expect(operation.replacement.workVersion, original.workVersion);
    expect(operation.replacement.viewpoint, original.viewpoint);
    expect(operation.replacement.depictedEvents, original.depictedEvents);
    expect(operation.replacement.narrationFrame, original.narrationFrame);
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: result.operations,
    );
    expect(
      (candidate.singleWhere((r) => r.identity.recordId == f.id(63)).payload
              as SceneRecord)
          .narrativePosition,
      BigInt.parse('18446744073709551615'),
    );
    final cleared = compileWritingNarrative(
      frame: disclosures.frame,
      rows: base,
      canonAt: (_, _) => base,
      input: delta(
        corrections: [
          WritingSceneCorrection(
            sceneHandle: f.ver(63).value,
            reason: 'Clear',
            clearViewpoint: true,
            clearReaderOrder: true,
            depictedEvents: [],
          ),
        ],
      ),
    );
    final replacement =
        (cleared.operations.single as ReviseSceneOperation).replacement;
    expect(replacement.viewpoint, isNull);
    expect(replacement.narrativePosition, isNull);
    expect(replacement.depictedEvents, isEmpty);
    final invalid = compileWritingNarrative(
      frame: disclosures.frame,
      rows: base,
      canonAt: (_, _) => base,
      input: delta(
        corrections: [
          WritingSceneCorrection(sceneHandle: f.id(63).value, reason: 'Stale'),
          WritingSceneCorrection(
            sceneHandle: f.ver(63).value,
            reason: 'Ambiguous',
            clearViewpoint: true,
            viewpoint: 'Mara',
          ),
          WritingSceneCorrection(
            sceneHandle: f.ver(63).value,
            reason: 'Again',
            clearViewpoint: true,
          ),
        ],
      ),
    );
    expect(invalid.operations, isEmpty);
    expect(invalid.clarifications, hasLength(3));
    final noop = compileWritingNarrative(
      frame: disclosures.frame,
      rows: base,
      canonAt: (_, _) => base,
      input: delta(
        corrections: [
          WritingSceneCorrection(
            sceneHandle: f.ver(63).value,
            reason: 'Retain',
          ),
        ],
      ),
    );
    expect(noop.operations, isEmpty);
    expect(noop.unchanged, ['Scene settings unchanged']);
  });

  test('omitted scene disclosures still recheck pinned dependency versions during corrections', () {
    final base = rows();
    final created = compileWritingNarrative(
      frame: disclosures.frame,
      rows: base,
      canonAt: (_, _) => base,
      input: delta(
        scenes: [
          scene(selected: [WritingFactDisclosure(factHandle: f.ver(3).value)]),
        ],
      ),
    );
    expect(created.clarifications, isEmpty);
    final payload =
        (created.operations.single as RecordNarrativeReferenceOperation).payload
            as SceneRecord;
    expect(payload.disclosedRecords, [f.ref(3)]);
    final original = base.singleWhere((r) => r.identity.recordId == f.id(1));
    final later = [
      for (final row in base)
        row.identity.recordId == f.id(1)
            ? RecordVersion.build(
                recordVersionId: f.ver(101),
                identity: original.identity,
                payload: original.payload,
              )
            : row,
      f.row(63, payload),
    ];
    final rejected = compileWritingNarrative(
      frame: disclosures.frame,
      rows: later,
      canonAt: (_, _) => base,
      input: delta(
        corrections: [
          WritingSceneCorrection(
            sceneHandle: f.ver(63).value,
            reason: 'Reorder',
            readerOrder: BigInt.one,
          ),
        ],
      ),
    );
    expect(rejected.operations, isEmpty);
    expect(rejected.clarifications.single, contains('dependencies must match'));
    final cleared = compileWritingNarrative(
      frame: disclosures.frame,
      rows: later,
      canonAt: (_, _) => throw StateError('empty disclosures'),
      input: delta(
        corrections: [
          WritingSceneCorrection(
            sceneHandle: f.ver(63).value,
            reason: 'Remove disclosure',
            disclosures: [],
          ),
        ],
      ),
    );
    expect(cleared.clarifications, isEmpty);
    expect(
      (cleared.operations.single as ReviseSceneOperation)
          .replacement
          .disclosedRecords,
      isEmpty,
    );
  });
}
