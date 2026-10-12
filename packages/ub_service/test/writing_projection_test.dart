import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'effective_objects_test.dart' as objects;

CanonicalValue field(CanonicalValue value, String name) =>
    (value as CanonicalObject).fields.firstWhere((e) => e.key == name).value;
List<CanonicalValue> list(CanonicalValue value, String name) =>
    (field(value, name) as CanonicalArray).items;

void main() {
  test('plain facts retain inherited and initial evidence separately from explicit instance conflicts', () async {
    final rows = objects.withInstance();
    objects.edit(rows, 4, {
      'labels': CanonicalObject([MapEntry('en', CanonicalString('Cedar'))]),
    });
    rows.add(f.row(12, objects.assertion(6, mode: AttributeMode.initialValue)));
    rows.add(f.row(13, objects.assertion(8, refute: true)));
    final frame = objects.frame();
    final result = await projectWritingFacts(
      request: ReadFactsRequest(
        universe: const Selector('World'),
        contextId: ContextId.generate(),
        objectNames: ['Cedar'],
      ),
      records: rows,
      frame: frame,
      restricted: false,
      readState: (id) => assembleReadState(
        records: rows,
        frame: frame,
        ids: [id],
        predicates: [],
        world: null,
        restricted: false,
      ),
    );
    final object = list(result, 'objects').single;
    expect(
      list(object, 'facts').map((f) => wireString(field(f, 'state'))),
      everyElement('conflicting'),
    );
    expect(list(object, 'inherited_attributes').length, 1);
    expect(list(object, 'initial_value_candidates').length, 1);
    expect(
      wireString(
        field(list(object, 'initial_value_candidates').single, 'group'),
      ),
      'initial_candidate',
    );
    expect(wireString(field(result, 'coverage')), 'bounded');
    final absent = await projectWritingFacts(
      request: ReadFactsRequest(
        universe: const Selector('World'),
        contextId: ContextId.generate(),
        objectNames: ['Missing'],
      ),
      records: rows,
      frame: frame,
      restricted: true,
      readState: (_) => throw StateError('No unique identity'),
    );
    expect(
      wireString(field(list(absent, 'objects').single, 'identity')),
      'not_found',
    );
    expect(
      wireString(field(list(absent, 'objects').single, 'coverage')),
      'restricted',
    );
  });
  test('plain numeric tokens remain exact and unsupported presentations do not manufacture values', () {
    String? label(RecordId id) => id == f.id(1)
        ? 'Cedar'
        : id == f.id(2)
        ? 'metre'
        : null;
    final exact = plainWritingValue(
      const IntegerValue('9007199254740993'),
      label,
    )!;
    expect(exact.toText(), '9007199254740993');
    expect(
      plainWritingValue(const DecimalValue('1.2300'), label)!.toText(),
      '1.2300',
    );
    expect(plainWritingValue(const IntegerValue('+1'), label), isNull);
    expect(plainWritingValue(const RationalValue('1', '3'), label), isNull);
    expect(
      plainWritingValue(
        ReferenceValue(ValueReferenceKind.entity, f.ref(9)),
        label,
      ),
      isNull,
    );
    expect(
      plainWritingValue(
        QuantityValue(
          const IntegerValue('9007199254740993'),
          UnitId.fromRecordId(f.id(2)),
        ),
        label,
      )!.toText(),
      '{"amount":9007199254740993,"unit":"metre"}',
    );
    expect(
      plainWritingTime(
        CalendarIntervalValidity(
          objects.cal,
          const ExactBound('1'),
          const UnboundedBound(),
        ).toWire(),
        (_) => 'clock',
      ),
      'clock: from 1 inclusive to unbounded exclusive',
    );
  });
  test('plain occurrence research excludes planned events and keeps unresolved named validity', () async {
    final rows = objects.withInstance();
    objects.edit(rows, 4, {
      'names': CanonicalArray([
        ContextualName(
          text: 'Cedar',
          validity: const UnknownValidity(),
        ).toWire(),
      ]),
    });
    rows.add(
      f.row(
        80,
        ActionDefinitionRecord(
          namespace: 'test',
          key: 'Act',
          labels: {},
          requirements: [],
          scope: objects.scope(),
          validity: const UnspecifiedValidity(),
        ),
      ),
    );
    for (final (n, kind) in [
      (81, OccurrenceKind.occurred),
      (82, OccurrenceKind.planned),
    ]) {
      rows.add(
        f.row(
          n,
          EventRecord(
            occurrence: SimpleOccurrence(kind),
            action: f.ref(80),
            time: ExactTime(objects.cal, '15'),
            participants: [EventParticipant(f.ref(4), 'actor')],
            labels: {},
          ),
        ),
      );
    }
    final frame = objects.frame();
    final result = await projectWritingFacts(
      request: ReadFactsRequest(
        universe: const Selector('World'),
        contextId: ContextId.generate(),
        objectNames: ['Cedar'],
      ),
      records: rows,
      frame: frame,
      restricted: false,
      readState: (id) => assembleReadState(
        records: rows,
        frame: frame,
        ids: [id],
        predicates: [],
        world: null,
        restricted: false,
      ),
    );
    final object = list(result, 'objects').single;
    expect(list(object, 'occurred_events').length, 1);
    expect(
      wireString(field(list(object, 'occurred_events').single, 'handle')),
      f.id(81).value,
    );
    expect(
      field(list(object, 'names').single, 'time_applicable'),
      isA<CanonicalNull>(),
    );
  });
}
