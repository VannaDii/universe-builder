import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as facts;
import 'writing_binding_test.dart' as binding;

final start = FictionalUniverseStart(
  calendarName: 'Ashen',
  initialTick: '10',
  tickLabel: 'days',
).build(facts.calendar);
List<RecordVersion> rows() => [
  f.row(10, start.$2),
  f.row(80, binding.entity(labels: {'en': 'Mara'})),
  f.row(
    99,
    RepresentedContextRecord(
      universe: f.u,
      kind: const ObjectiveContext(),
      chronology: start.$1,
      labels: {'en': 'Root'},
    ),
  ),
];
WritingStoryContext declaration({
  String name = 'Dream',
  StoryContextKind kind = StoryContextKind.dream,
  String? narrator,
  String parent = 'Root',
  String? calendar,
  String time = '9007199254740993',
}) => WritingStoryContext(
  name: name,
  introduce: true,
  kind: kind,
  narrator: narrator,
  parent: parent,
  calendar: calendar ?? start.$2.key,
  storyTime: time,
);

void main() {
  test('explicit story contexts compile independently of parent truth and clock position', () {
    final base = rows();
    final result = compileWritingContexts(
      frame: facts.frame(),
      rows: base,
      declarations: [
        declaration(),
        declaration(
          name: 'Narration',
          kind: StoryContextKind.narrator,
          narrator: 'Mara',
          time: '20',
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    expect(result.operations, hasLength(2));
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: result.operations,
    );
    expect(candidate, hasLength(base.length + 2));
    final dream =
        candidate
                .singleWhere(
                  (r) =>
                      r.payload is RepresentedContextRecord &&
                      (r.payload as RepresentedContextRecord).labels['en'] ==
                          'Dream',
                )
                .payload
            as RepresentedContextRecord;
    expect((dream.kind as AuthoredContext).label, 'dream: Dream');
    expect(dream.parent, f.ref(99));
    expect(dream.chronology!.firstInteraction, '9007199254740993');
    expect(dream.chronology!.current, '9007199254740993');
    expect(start.$1.current, '10');
    final narrator =
        candidate
                .singleWhere(
                  (r) =>
                      r.payload is RepresentedContextRecord &&
                      (r.payload as RepresentedContextRecord).labels['en'] ==
                          'Narration',
                )
                .payload
            as RepresentedContextRecord;
    expect((narrator.kind as NarratorContext).narrator, f.ref(80));
    expect(resolveWritingContext(candidate, 'Narration'), isNotNull);
    expect(
      resolveWritingContext(
        candidate,
        dream.kind is AuthoredContext ? 'dream: Dream' : '',
      ),
      isNotNull,
    );
  });

  test('matching clock systems compare by authored values rather than object identity', () {
    final parallel = f.row(
      98,
      RepresentedContextRecord(
        universe: f.u,
        kind: const AuthoredContext('parallel'),
        labels: {},
        chronology: Chronology(
          calendar: facts.calendar,
          system: ClockSystem.fromWire(start.$1.system.toWire()),
          firstInteraction: '20',
          current: '30',
        ),
      ),
    );
    final result = compileWritingContexts(
      frame: facts.frame(),
      rows: [...rows(), parallel],
      declarations: [declaration()],
    );
    expect(result.clarifications, isEmpty);
    final conflicting = f.row(
      97,
      RepresentedContextRecord(
        universe: f.u,
        kind: const AuthoredContext('conflicting'),
        labels: {},
        chronology: Chronology(
          calendar: facts.calendar,
          system: FictionalClock('hours', null),
          firstInteraction: '20',
          current: '30',
        ),
      ),
    );
    final denied = compileWritingContexts(
      frame: facts.frame(),
      rows: [...rows(), parallel, conflicting],
      declarations: [declaration()],
    );
    expect(denied.operations, isEmpty);
    expect(
      denied.clarifications.single,
      contains('conflicting authored clock systems'),
    );
  });

  test('contexts require explicit published parents calendars narrator identity and unrestricted introductions', () {
    final result = compileWritingContexts(
      frame: facts.frame(),
      rows: rows(),
      declarations: [
        declaration(parent: 'Hidden'),
        declaration(name: 'No calendar', calendar: 'Hidden'),
        declaration(name: 'Bad time', time: 'tomorrow'),
        declaration(name: 'Unwanted narrator', narrator: 'Mara'),
        declaration(name: 'Narrator absent', kind: StoryContextKind.narrator),
        declaration(
          name: 'Wrong narrator',
          kind: StoryContextKind.narrator,
          narrator: 'Hidden',
        ),
      ],
    );
    expect(result.operations, isEmpty);
    expect(result.clarifications, hasLength(6));
    final scoped = compileWritingContexts(
      frame: facts.frame(),
      rows: rows(),
      declarations: [declaration()],
      worldScope: {},
    );
    expect(scoped.operations, isEmpty);
    expect(scoped.clarifications.single, contains('universe-wide'));
    final duplicate = compileWritingContexts(
      frame: facts.frame(),
      rows: rows(),
      declarations: [
        declaration(),
        declaration(),
        declaration(name: 'Child', parent: 'Dream'),
      ],
    );
    expect(duplicate.operations, hasLength(1));
    expect(duplicate.clarifications, hasLength(2));
  });

  test('existing contexts are retained while narrator-kind changes and ambiguous labels clarify', () {
    final result = compileWritingContexts(
      frame: facts.frame(),
      rows: rows(),
      declarations: [
        declaration(name: 'Root'),
        declaration(
          name: 'Root',
          kind: StoryContextKind.narrator,
          narrator: 'Mara',
        ),
      ],
    );
    expect(result.operations, isEmpty);
    expect(result.unchanged, ['Existing context: Root']);
    expect(result.clarifications, hasLength(1));
    final duplicate = f.row(
      98,
      RepresentedContextRecord(
        universe: f.u,
        kind: const AuthoredContext('copy'),
        labels: {'en': 'Root'},
      ),
    );
    expect(resolveWritingContext([...rows(), duplicate], 'Root'), isNull);
    final denied = compileWritingContexts(
      frame: facts.frame(),
      rows: [...rows(), duplicate],
      declarations: [declaration(name: 'Root')],
    );
    expect(denied.operations, isEmpty);
    expect(denied.clarifications.single, contains('ambiguous'));
  });
}
