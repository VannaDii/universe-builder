import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as facts;
import 'writing_contexts_test.dart' as contexts;

final frame = facts.frame();
final edition = f.row(
  60,
  WorkVersionRecord(
    work: f.ref(61),
    versionLabel: 'First',
    binding: BoundWork(frame.continuity, frame.revision),
  ),
);
final version = VersionRef(
  universe: f.u,
  record: edition.identity.recordId,
  version: edition.recordVersionId,
);
List<RecordVersion> rows() => [
  ...contexts.rows(),
  f.row(1, facts.fixture().first.payload),
  facts.fixture()[1],
  facts.assertion(),
  edition,
  f.row(
    70,
    EventRecord(
      participants: [],
      occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
      time: ExactTime(facts.calendar, '10'),
      labels: {},
    ),
  ),
  f.row(
    71,
    EventRecord(
      participants: [],
      occurrence: const SimpleOccurrence(OccurrenceKind.planned),
      time: ExactTime(facts.calendar, '10'),
      labels: {},
    ),
  ),
];
Matcher fails(String message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', contains(message)),
);

void main() {
  test('disclosures preserve authored selection order deduplicate identities and check exact canon dependencies', () {
    final current = rows();
    var reads = 0;
    final result = bindWritingDisclosures(
      edition: version,
      frame: frame,
      rows: current,
      disclosures: [
        WritingObjectDisclosure(name: 'Mara'),
        WritingFactDisclosure(factHandle: f.ver(3).value),
        WritingObjectDisclosure(name: 'Mara'),
        WritingEventDisclosure(eventHandle: f.ver(70).value),
      ],
      canonAt: (continuity, revision) {
        reads++;
        expect(continuity, frame.continuity);
        expect(revision, frame.revision);
        return current;
      },
    );
    expect(result, [f.ref(80), f.ref(3), f.ref(70)]);
    expect(reads, 1);
    final original = current.singleWhere((r) => r.identity.recordId == f.id(1));
    final changed = RecordVersion.build(
      recordVersionId: f.ver(101),
      identity: original.identity,
      payload: original.payload,
    );
    final later = [
      for (final row in current)
        row.identity.recordId == f.id(1) ? changed : row,
    ];
    expect(
      () => bindWritingDisclosures(
        edition: version,
        frame: frame,
        rows: later,
        disclosures: [WritingFactDisclosure(factHandle: f.ver(3).value)],
        canonAt: (_, _) => current,
      ),
      fails('dependencies must match'),
    );
    expect(
      () => checkWritingSceneDisclosures(
        edition: version,
        disclosures: [f.ref(3)],
        rows: current.where((r) => r.identity.recordId != f.id(1)).toList(),
        canonAt: (_, _) => current,
      ),
      fails('dependencies are unavailable'),
    );
  });

  test('disclosures require exact published editions and their authored continuity', () {
    final current = rows();
    final unbound = f.row(
      60,
      WorkVersionRecord(
        work: f.ref(61),
        versionLabel: 'First',
        binding: const UnboundWork(),
      ),
    );
    final unboundRows = [
      for (final row in current)
        row.identity.recordId == f.id(60) ? unbound : row,
    ];
    expect(
      () => bindWritingDisclosures(
        edition: version,
        frame: frame,
        rows: unboundRows,
        disclosures: [WritingObjectDisclosure(name: 'Mara')],
        canonAt: (_, _) => throw StateError('must not read'),
      ),
      fails('bound to one canon revision'),
    );
    final stale = VersionRef(
      universe: f.u,
      record: f.id(60),
      version: f.ver(160),
    );
    expect(
      () => bindWritingDisclosures(
        edition: stale,
        frame: frame,
        rows: current,
        disclosures: [WritingObjectDisclosure(name: 'Mara')],
        canonAt: (_, _) => current,
      ),
      fails('exact published edition'),
    );
    final foreign = Frame(
      universe: frame.universe,
      continuity: ContinuityId.parse('cont_${f.suffix(2)}'),
      revision: frame.revision,
      context: frame.context,
      time: frame.time,
      perspective: frame.perspective,
    );
    expect(
      () => bindWritingDisclosures(
        edition: version,
        frame: foreign,
        rows: current,
        disclosures: [WritingObjectDisclosure(name: 'Mara')],
        canonAt: (_, _) => throw StateError('must not read'),
      ),
      fails('authored continuity'),
    );
    expect(
      bindWritingDisclosures(
        edition: stale,
        frame: foreign,
        rows: [],
        disclosures: [],
        canonAt: (_, _) => throw StateError('must not read'),
      ),
      isEmpty,
    );
  });

  test('current disclosure handles cannot link planned events absent facts or generated effects', () {
    final current = rows();
    for (final disclosure in [
      WritingEventDisclosure(eventHandle: f.ver(71).value),
      WritingEventDisclosure(eventHandle: f.id(70).value),
      WritingFactDisclosure(factHandle: f.id(3).value),
      WritingObjectDisclosure(name: 'Hidden'),
    ]) {
      expect(
        () => bindWritingDisclosures(
          edition: version,
          frame: frame,
          rows: current,
          disclosures: [disclosure],
          canonAt: (_, _) => current,
        ),
        throwsFormatException,
      );
    }
    final original = current.singleWhere((r) => r.identity.recordId == f.id(3));
    final generated = f.row(
      3,
      f.patch<AssertionRecord>(original.payload as AssertionRecord, {
        'establishedBy': EventEffectRef(f.ref(70), 'authored_slot').toWire(),
      }),
    );
    final generatedRows = [
      for (final row in current)
        row.identity.recordId == f.id(3) ? generated : row,
    ];
    expect(
      () => bindWritingDisclosures(
        edition: version,
        frame: frame,
        rows: generatedRows,
        disclosures: [WritingFactDisclosure(factHandle: f.ver(3).value)],
        canonAt: (_, _) => generatedRows,
      ),
      fails('correct the authored cause'),
    );
  });
}
