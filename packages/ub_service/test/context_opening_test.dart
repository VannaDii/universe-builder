import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/context_opening.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as frames;
import 'structural_checks_test.dart' as structure;
import 'proposal_validation_test.dart' as editions;

OpenContextRequest request({
  RepresentedContextSelector context = const ContextNameSelector('Story'),
  Perspective perspective = const AuthorPerspective(),
  FrameTime time = const TimelessFrameTime(),
  RepresentedContextSelector? scene,
}) => OpenContextRequest(
  universe: const Selector('World'),
  continuityId: frames.frame().continuity,
  revision: const HeadRevisionSelector(),
  representedContext: context,
  temporalQuery: time,
  temporalSystems: [],
  perspective: perspective,
  readerScene: scene,
);
Future<Frame> open(List<RecordVersion> rows, OpenContextRequest input) =>
    prepareContextFrame(
      request: input,
      universe: f.u,
      revision: f.revision,
      records: rows,
      worldScope: null,
      readCanon: (_, _) => rows,
    );
Frame view(Perspective perspective, {int context = 3, int? scene}) => Frame(
  universe: f.u,
  continuity: frames.frame().continuity,
  revision: f.revision,
  context: f.ref(context),
  time: const TimelessFrameTime(),
  perspective: perspective,
  readerScene: scene == null ? null : f.id(scene),
);

void main() {
  final denied = throwsA(isA<NotFoundOrNotAccessibleError>());
  test('context names require one exact authored match and supported temporal query', () async {
    final context = f.row(
      99,
      RepresentedContextRecord(
        universe: f.u,
        kind: const AuthoredContext('Story'),
        labels: {},
      ),
    );
    expect((await open([context], request())).context, f.ref(99));
    await expectLater(
      open([context, f.row(98, context.payload)], request()),
      denied,
    );
    await expectLater(
      open([context], request(time: const AtFrameTime(UnspecifiedTime()))),
      throwsA(isA<UnsupportedSemanticsError>()),
    );
    await expectLater(
      open([context], request(scene: ContextIdSelector(f.id(60)))),
      throwsA(isA<InvalidArgumentError>()),
    );
  });

  test(
    'character and narrator closure require matching represented context',
    () async {
      final rows = [
        frames.fixture().first,
        f.row(2, f.entity()),
        f.row(
          3,
          RepresentedContextRecord(
            universe: f.u,
            kind: CharacterContext(f.ref(2)),
            labels: {},
          ),
        ),
        f.row(
          4,
          PropositionRecord(
            subject: f.ref(2),
            predicate: f.ref(1),
            context: f.ref(3),
            value: const BooleanValue(true),
            quantification: Quantification.particular,
          ),
        ),
        f.row(5, f.assertion()),
        f.row(7, f.entity()),
      ];
      final selected = await perspectiveRecordIds(
        records: rows,
        frame: view(CharacterPerspective(f.id(2))),
        readCanon: (_, _) => throw StateError('No edition read'),
      );
      expect(selected, {f.id(1), f.id(2), f.id(3), f.id(4), f.id(5)});
      await expectLater(
        perspectiveRecordIds(
          records: rows,
          frame: view(NarratorPerspective(f.id(2))),
          readCanon: (_, _) => [],
        ),
        denied,
      );
      rows[2] = f.row(
        3,
        RepresentedContextRecord(
          universe: f.u,
          kind: NarratorContext(f.ref(2)),
          labels: {},
        ),
      );
      expect(
        await perspectiveRecordIds(
          records: rows,
          frame: view(NarratorPerspective(f.id(2))),
          readCanon: (_, _) => [],
        ),
        selected,
      );
    },
  );

  test('reader perspective selects disclosures through the pinned scene and edition', () async {
    RecordVersion scene(int n, int position, int disclosure) => f.row(
      n,
      SceneRecord(
        workVersion: editions.editionRef,
        sceneId: 'Scene$n',
        narrativePosition: BigInt.from(position),
        disclosedRecords: [f.ref(disclosure)],
        depictedEvents: [],
        worldAssociations: [],
      ),
    );
    final known = f.row(10, f.entity()), later = f.row(11, f.entity());
    final rows = [
      structure.context(99),
      editions.edition(),
      known,
      later,
      scene(60, 1, 10),
      scene(61, 2, 11),
    ];
    expect(
      await perspectiveRecordIds(
        records: rows,
        frame: view(const ReaderPerspective(), context: 99, scene: 60),
        readCanon: (_, _) => [known, later],
      ),
      {f.id(10)},
    );
    expect(
      await perspectiveRecordIds(
        records: rows,
        frame: view(const ReaderPerspective(), context: 99, scene: 61),
        readCanon: (_, _) => [known, later],
      ),
      {f.id(10), f.id(11)},
    );
    await expectLater(
      perspectiveRecordIds(
        records: rows,
        frame: view(const ReaderPerspective(), context: 99, scene: 61),
        readCanon: (_, _) => [known],
      ),
      denied,
    );
    await expectLater(
      perspectiveRecordIds(
        records: rows,
        frame: view(const ReaderPerspective(), context: 99),
        readCanon: (_, _) => [],
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
  });
}
