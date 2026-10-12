import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'effective_objects_test.dart' as objects;
import '../../ub_rules/test/powers_test.dart' as powers;

void main() {
  test(
    'state keeps unresolved explicit validity without inferring absent facts',
    () {
      final rows = objects.withInstance();
      objects.edit(rows, 9, {'validity': const UnspecifiedValidity().toWire()});
      rows.add(
        f.row(
          70,
          f.patch(f.attitude(target: 8), {'holder': f.ref(4).toCanonical()}),
        ),
      );
      final state = assembleReadState(
        records: rows,
        frame: objects.frame(),
        ids: [f.id(4)],
        predicates: [f.id(5)],
        world: null,
        restricted: false,
      );
      expect(state.unresolvedAssertionIds, [f.id(9)]);
      expect(state.epistemic.single.identity.recordId, f.id(70));
      expect(state.coverage, Coverage.partial);
      expect(
        state.objects.single.initializationHistoryCoverage,
        Coverage.complete,
      );
      final restricted = assembleReadState(
        records: rows,
        frame: objects.frame(),
        ids: [f.id(4)],
        predicates: [],
        world: null,
        restricted: true,
      );
      expect(
        restricted.objects.single.initializationHistoryCoverage,
        Coverage.restricted,
      );
      expect(restricted.objects.single.initializationReceipts, isEmpty);
    },
  );
  test('state event frames require visible occurred events and distinguish entry from exit', () {
    final rows = objects.withInstance();
    objects.edit(rows, 9, {'validity': objects.interval(15, 20).toWire()});
    rows.add(
      f.row(
        80,
        EventRecord(
          occurrence: const SimpleOccurrence(OccurrenceKind.occurred),
          time: ExactTime(objects.cal, '15'),
          participants: [],
          labels: {},
        ),
      ),
    );
    final pre = stateReadFrame(
      objects.frame(),
      rows,
      f.id(80),
      EventTimeSide.before,
    );
    final post = stateReadFrame(
      objects.frame(),
      rows,
      f.id(80),
      EventTimeSide.after,
    );
    State read(Frame frame) => assembleReadState(
      records: rows,
      frame: frame,
      ids: [f.id(4)],
      predicates: [],
      world: null,
      restricted: false,
    );
    expect(read(pre).assertions, isEmpty);
    expect(read(post).assertions.single.identity.recordId, f.id(9));
    expect(
      () =>
          stateReadFrame(objects.frame(), rows, f.id(81), EventTimeSide.before),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(
      () => stateReadFrame(objects.frame(), rows, f.id(80), null),
      throwsA(isA<InvalidArgumentError>()),
    );
    final planned = [
      f.row(
        80,
        EventRecord(
          occurrence: const SimpleOccurrence(OccurrenceKind.planned),
          time: ExactTime(objects.cal, '15'),
          participants: [],
          labels: {},
        ),
      ),
    ];
    expect(
      () => stateReadFrame(
        objects.frame(),
        planned,
        f.id(80),
        EventTimeSide.after,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });
  test('state reports derived possession powers with their exact evidence without storing assertions', () {
    final rows = [...powers.fixture(), f.row(1, f.entity())];
    final frame = Frame(
      universe: f.u,
      continuity: objects.frame().continuity,
      revision: f.revision,
      context: powers.ref(10),
      time: AtFrameTime(ExactTime(powers.calendar, '11')),
      perspective: const AuthorPerspective(),
    );
    final state = assembleReadState(
      records: rows,
      frame: frame,
      ids: [f.id(1)],
      predicates: [],
      world: null,
      restricted: false,
    );
    expect(state.derived.single.value, const BooleanValue(true));
    expect(state.derived.single.evidence, [f.ver(6), f.ver(7), f.ver(8)]);
    expect(state.assertions, isEmpty);
  });
}
