import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  final calendar = CalendarId.parse('cal_000000000000000000000001');
  test(
    'exact authored digits and typed false, zero and empty stay distinct',
    () {
      final integer = const IntegerValue('+0009007199254740993');
      integer.validate();
      expect(DomainValue.fromWire(integer.toWire()), integer);
      expect(
        integer.toWire().toText(),
        '{"digits":"+0009007199254740993","kind":"integer"}',
      );
      expect(const TextValue(''), isNot(const IntegerValue('0')));
      expect(const BooleanValue(false), isNot(const IntegerValue('0')));
      expect(const DecimalValue('30.00'), isNot(const DecimalValue('30.0')));
    },
  );
  test('invalid numerics and every zero denominator spelling are rejected', () {
    for (final digits in [
      '',
      '12.3.4',
      '1e5',
      'NaN',
      'Infinity',
      '-',
      '12a',
      '1 2',
    ]) {
      expect(
        () => DecimalValue(digits).validate(),
        throwsFormatException,
        reason: digits,
      );
    }
    for (final denominator in ['0', '00', '+0', '-0', '+000', '-000']) {
      expect(
        () => RationalValue('1', denominator).validate(),
        throwsFormatException,
      );
    }
    const RationalValue('0007', '03').validate();
    expect(isExactDigits('1' * 1024, allowFraction: false), isTrue);
    expect(isExactDigits('1' * 1025, allowFraction: false), isFalse);
  });
  test(
    'range record encoding and comparison encoding retain existing field names',
    () {
      final range = RangeValue(
        lower: const IntegerValue('007'),
        upper: const IntegerValue('120'),
        lowerInclusive: true,
        upperInclusive: false,
      );
      range.validate();
      expect(range.toWire().toText(), contains('"lower_inclusive":true'));
      expect(range.toCanonical().toText(), contains('"lowerInclusive":true'));
      expect(DomainValue.fromWire(range.toWire()), range);
      expect(
        () => DomainValue.fromWire(range.toCanonical()),
        throwsFormatException,
      );
      expect(
        () => const RangeValue(
          lower: IntegerValue('120'),
          upper: IntegerValue('33'),
          lowerInclusive: true,
          upperInclusive: false,
        ).validate(),
        throwsFormatException,
      );
      expect(compareExactDigits('007', '7'), 0);
      expect(compareExactDigits('-1', '1'), -1);
      expect(compareExactDigits('120', '33'), 1);
      expect(compareExactDigits('10', '9.5'), isNull);
      expect(compareExactDigits('+7', '7'), isNull);
      expect(compareExactDigits('7\n', '7'), isNull);
    },
  );
  test('set comparison normalizes order without changing record digests or duplicates', () {
    final a = SetValue([
      const TextValue('🌲'),
      const TextValue('\ue000'),
      const TextValue('🌲'),
    ]);
    final b = SetValue([
      const TextValue('\ue000'),
      const TextValue('🌲'),
      const TextValue('🌲'),
    ]);
    expect(a.toCanonical().toText(), b.toCanonical().toText());
    expect(a, isNot(b));
    expect(a.items, hasLength(3));
    expect(a.hashCode, b.hashCode);
    expect(
      payloadDigest('entity', a.toWire()),
      isNot(payloadDigest('entity', b.toWire())),
    );
    expect(DomainValue.fromWire(a.toWire()), a);
    final sequence = SequenceValue(a.items);
    expect(
      sequence.toCanonical().toText(),
      isNot(SequenceValue(b.items).toCanonical().toText()),
    );
  });
  test('quantity and collection bounds apply recursively', () {
    final unit = UnitId.parse('unit_000000000000000000000001');
    QuantityValue(const DecimalValue('30.00'), unit).validate();
    expect(
      () => QuantityValue(const TextValue('thirty'), unit).validate(),
      throwsFormatException,
    );
    expect(
      () =>
          SequenceValue(List.filled(1001, const IntegerValue('1'))).validate(),
      throwsFormatException,
    );
    expect(
      () => SetValue([const DecimalValue('NaN')]).validate(),
      throwsFormatException,
    );
    expect(
      () => StructuredValue(
        ValueDefinitionId.parse('vdef_000000000000000000000001'),
        {for (var i = 0; i < 513; i++) '$i': const TextValue('field')},
      ).validate(),
      throwsFormatException,
    );
  });
  test(
    'temporal bounds preserve unknown, unbounded and approximate accounts',
    () {
      final unknown = IntervalTime(
        calendar,
        const UnknownBound(),
        const ExactBound('day-20'),
      );
      final unbounded = IntervalTime(
        calendar,
        const UnboundedBound(),
        const ExactBound('day-20'),
      );
      unknown.validate();
      unbounded.validate();
      expect(unknown, isNot(unbounded));
      expect(const UnknownBound().isKnown, isFalse);
      expect(const UnboundedBound().isKnown, isTrue);
      final memory = TemporalValue(
        ApproximateTime(calendar, 'summer', const IntegerValue('10')),
      );
      memory.validate();
      expect(DomainValue.fromWire(memory.toWire()), memory);
      expect(memory.temporal.isExact, isFalse);
      expect(DurationTime(calendar, const IntegerValue('0')).isExact, isTrue);
      IntervalTime(
        calendar,
        const ExactBound('day-20'),
        const ExactBound('day-20'),
      ).validate();
      expect(() => ExactTime(calendar, '').validate(), throwsFormatException);
      expect(
        () => ExactTime(calendar, 'day\u0085twenty').validate(),
        throwsFormatException,
      );
      expect(
        () => ExactTime(calendar, 'é' * 321).validate(),
        throwsFormatException,
      );
    },
  );
  test(
    'closed typed decoding rejects wrong scalar types and unknown variants',
    () {
      for (final json in [
        '{"kind":"integer","digits":1}',
        '{"kind":"text","text":"a","extra":true}',
        '{"kind":"unsupported"}',
        '{"kind":"temporal","temporal":{"kind":"unspecified","extra":true}}',
        '{"kind":"spatial","spatial":{"kind":"unsupported"}}',
      ]) {
        expect(
          () => DomainValue.fromWire(CanonicalValue.parseJson(json)),
          throwsFormatException,
        );
      }
    },
  );
}
