@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending unit',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
const pendingTime = TemporalValidityInput(
  kind: 'still choosing',
  calendar: '\ufeffCalendar',
  relation: 'before?',
  targetUniverse: '',
  targetRecord: 'unfinished',
  start: TemporalBoundInput(
    kind: 'approximate',
    value: '\ufeffStart',
    upper: 'disabled upper',
    uncertaintyKind: 'rational',
    uncertainty: '9007199254740997',
    denominator: '',
    unit: 'pending',
    amount: QualifierInput(
      kind: 'quantity',
      value: '',
      children: [
        QualifierInput(key: 'repeated'),
        QualifierInput(key: 'repeated'),
      ],
      lower: QualifierInput(kind: 'integer', value: '00007'),
    ),
  ),
  end: TemporalBoundInput(
    kind: 'unknown',
    value: 'disabled value',
    upper: '\ufeffEnd',
    amount: QualifierInput(kind: 'text', value: '\ufeffAmount'),
  ),
);
const pendingScale = QualifierInput(
  key: '\ufeffScale',
  kind: 'unknown input kind',
  value: '\ufeff9007199254740997',
  denominator: '',
  unit: 'disabled unit',
  universe: 'pending universe',
  definition: '',
  originalKey: '',
  lowerInclusive: 'unfinished',
  upperInclusive: 'false',
  temporal: pendingTime,
  children: [
    QualifierInput(key: 'repeated', value: 'first\r\n\u0000'),
    QualifierInput(key: 'repeated', value: 'second 😀'),
  ],
  lower: QualifierInput(
    kind: 'range',
    lower: QualifierInput(kind: 'rational', value: '1', denominator: '0'),
  ),
  upper: QualifierInput(),
);
UnfinishedUnitForm input(EditorFormScope s, {bool editing = true}) =>
    UnfinishedUnitForm(
      baseRevision: RevisionId.generate(),
      representedContext: s.representedContext!,
      clientRef: s.typeClientRef!,
      namespace: '\ufeffAuthored 記憶',
      key: '\ufeffPending key',
      dimension: 'distance?',
      symbol: '\ufeffm',
      hasBase: false,
      base: 'disabled base',
      hasScale: false,
      scale: pendingScale,
      validityChoice: 'retain',
      temporalValidity: pendingTime,
      labels: const [
        PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
        PropertyLabelInput(),
        PropertyLabelInput(
          language: '\ufeffen',
          text: 'Repeated unfinished language',
        ),
      ],
      rationale: '\ufeffReason 😀\r\n\u0000',
      draftVersion: editing ? maxU64 : null,
      revisionTarget: editing
          ? const ExpressionReferenceInput(
              record: '',
              universe: '\ufeffPending universe',
            )
          : null,
      expectedRecordVersion: editing ? RecordVersionId.generate() : null,
      original: editing
          ? UnitRecord(
              namespace: '\ufeffOriginal',
              key: '\ufeffMeasure',
              dimension: '\ufeffDistance',
              symbol: '\ufeffm',
              labels: {'\ufeffen': '\ufeffName', '': '', 'ja': '記憶'},
              base: UnitId.generate(),
              scaleToBase: SequenceValue([
                const RationalValue('9007199254740997', '3'),
                StructuredValue(ValueDefinitionId.generate(), {
                  '\ufeffField': const TextValue('\ufeffValue\r\n\u0000😀'),
                  'empty': SequenceValue([]),
                }),
                SetValue([
                  const IntegerValue('00007'),
                  const DecimalValue('-0.000'),
                ]),
                QuantityValue(
                  SequenceValue([const BooleanValue(true)]),
                  UnitId.generate(),
                ),
                RangeValue(
                  lower: const IntegerValue('1'),
                  upper: const IntegerValue('2'),
                  lowerInclusive: false,
                  upperInclusive: true,
                ),
                EnumValue(ValueDefinitionId.generate(), '\ufeffChoice'),
                for (final kind in ValueReferenceKind.values)
                  ReferenceValue(
                    kind,
                    RecordRef(
                      record: RecordId.generate(),
                      universe: s.universe,
                    ),
                  ),
                TemporalValue(
                  DurationTime(
                    CalendarId.generate(),
                    const RationalValue('3', '2'),
                  ),
                ),
                const SpatialValue(UnspecifiedSpace()),
              ]),
              validity: CalendarIntervalValidity(
                CalendarId.generate(),
                const ApproximateBound('\ufeffStart', RationalValue('1', '3')),
                const UncertainBound('\ufeffLower', '\ufeffUpper'),
              ),
            )
          : null,
    );
UnfinishedUnitForm cleared(UnfinishedUnitForm f) => UnfinishedUnitForm(
  baseRevision: f.baseRevision,
  representedContext: f.representedContext,
  clientRef: f.clientRef,
);

int qualifierCount(QualifierInput q) =>
    1 +
    q.children.fold<int>(0, (n, c) => n + qualifierCount(c)) +
    (q.lower == null ? 0 : qualifierCount(q.lower!)) +
    (q.upper == null ? 0 : qualifierCount(q.upper!)) +
    temporalQualifierCount(q.temporal);
int temporalQualifierCount(TemporalValidityInput? t) => t == null
    ? 0
    : [t.start, t.end].fold<int>(
        0,
        (n, b) => n + (b.amount == null ? 0 : qualifierCount(b.amount!)),
      );

void main() {
  test('typed unit recovery retains recursive unfinished scale, disabled time fields and the complete original definition after restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-unit-');
    final path = '${root.path}/forms.sqlite', s = scope(), form = input(s);
    var store = UnitFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = UnitFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(unit_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db.select(
            'SELECT CAST(input_value AS BLOB) AS value FROM unit_qualifier WHERE input_key=?',
            [form.scale.key],
          ).single['value'],
          utf8.encode(form.scale.value),
        );
        expect(
          db.select('SELECT count(*) AS n FROM unit_child').single['n'],
          greaterThan(4),
        );
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('unit originals retain absent scales, bases and every validity family across replacement and restart', () {
    final root = Directory('/tmp').createTempSync('ub-unit-validities-');
    final path = '${root.path}/forms.sqlite',
        s = scope(),
        calendar = CalendarId.generate();
    final ref = RecordRef(record: RecordId.generate(), universe: s.universe);
    final times = <TemporalExpression>[
      ExactTime(calendar, '\ufeffExact'),
      IntervalTime(calendar, const UnknownBound(), const UnboundedBound()),
      ApproximateTime(
        calendar,
        '\ufeffApproximate',
        const DecimalValue('0.00000000000001'),
      ),
      DurationTime(calendar, SequenceValue([const TextValue('記憶 😀')])),
      RelativeTime(calendar, TemporalRelation.before, ref),
      const UnspecifiedTime(),
    ];
    final validities = <Validity>[
      const UnspecifiedValidity(),
      const UnknownValidity(),
      const ConditionalValidity(),
      const IntervalValidity(ExactBound('\ufeffStart'), UnboundedBound()),
      CalendarIntervalValidity(
        calendar,
        const UnknownBound(),
        const UnboundedBound(),
      ),
      const PersistentValidity(ExactBound('\ufeffFrom')),
      ...times.map(InstantValidity.new),
    ];
    var store = UnitFormRecoveryStore.open(path), generation = BigInt.zero;
    try {
      for (var i = 0; i < validities.length; i++) {
        final form = UnfinishedUnitForm(
          baseRevision: RevisionId.generate(),
          representedContext: s.representedContext!,
          clientRef: s.typeClientRef!,
          original: UnitRecord(
            namespace: 'authored',
            key: 'unit',
            dimension: 'length',
            symbol: 'm',
            labels: {},
            base: i.isEven ? null : UnitId.generate(),
            scaleToBase: i.isEven
                ? null
                : SequenceValue([
                    ...times.map(TemporalValue.new),
                    SpatialValue(
                      SpatialCoordinates('\ufeffReference', [
                        const IntegerValue('0007'),
                      ]),
                    ),
                    SpatialValue(
                      SpatialDistance(
                        ref,
                        const RationalValue('1', '3'),
                        UnitId.generate(),
                      ),
                    ),
                    for (final relation in SpatialRelation.values)
                      SpatialValue(SpatialLink(relation, ref)),
                  ]),
            validity: validities[i],
          ),
        );
        generation = store.save(s, form, generation).generation;
        store.close();
        store = UnitFormRecoveryStore.open(path);
        expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
