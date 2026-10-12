import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

const one = IntegerValue('1'), two = IntegerValue('2');
UnitId unit(int n) =>
    UnitId.parse('unit_${n.toRadixString(16).padLeft(24, '0')}');
RangeValue range(
  String lo,
  String hi, {
  bool left = true,
  bool right = true,
  UnitId? unit,
}) => RangeValue(
  lower: IntegerValue(lo),
  upper: IntegerValue(hi),
  lowerInclusive: left,
  upperInclusive: right,
  unit: unit,
);

void main() {
  test('numeric comparisons are exact across integer, decimal and rational encodings', () {
    expect(
      compareValues(
        const IntegerValue('9007199254740993'),
        Comparator.gt,
        const IntegerValue('9007199254740992'),
      ),
      isTrue,
    );
    expect(
      compareValues(
        const DecimalValue('0.5'),
        Comparator.eq,
        const RationalValue('1', '2'),
      ),
      isTrue,
    );
    expect(
      compareValues(
        const DecimalValue('-0.125'),
        Comparator.eq,
        const RationalValue('-1', '8'),
      ),
      isTrue,
    );
    expect(
      compareValues(const IntegerValue('+0001'), Comparator.eq, one),
      isTrue,
    );
    for (final (op, expected) in [
      (Comparator.eq, false),
      (Comparator.neq, true),
      (Comparator.lt, true),
      (Comparator.ltEq, true),
      (Comparator.gt, false),
      (Comparator.gtEq, false),
    ]) {
      expect(compareValues(one, op, two), expected);
    }
  });

  test(
    'signed i128 parse and cross-product limits remain unsupported on overflow',
    () {
      final max = (BigInt.one << 127) - BigInt.one, min = -(BigInt.one << 127);
      expect(compareValues(IntegerValue('$max'), Comparator.gt, one), isTrue);
      expect(compareValues(IntegerValue('$min'), Comparator.lt, one), isTrue);
      expect(
        compareValues(IntegerValue('${max + BigInt.one}'), Comparator.gt, one),
        isNull,
      );
      expect(
        compareValues(
          IntegerValue('$max'),
          Comparator.eq,
          RationalValue('$max', '2'),
        ),
        isNull,
      );
      expect(
        compareValues(DecimalValue('0.${'0' * 38}1'), Comparator.eq, one),
        isNull,
      );
      for (final invalid in ['', '0x10', ' 1', '1\n', '1_000', '1.0']) {
        expect(
          compareValues(IntegerValue(invalid), Comparator.eq, one),
          isNull,
        );
      }
      for (final d in ['0', '-1', '${max + BigInt.one}']) {
        expect(
          compareValues(RationalValue('1', d), Comparator.eq, one),
          isNull,
        );
      }
    },
  );

  test(
    'text follows UTF-8 ordering and boolean comparisons stay type-specific',
    () {
      expect(
        compareValues(
          const TextValue('\ue000'),
          Comparator.lt,
          const TextValue('😀'),
        ),
        isTrue,
      );
      expect(
        compareValues(
          const TextValue('a'),
          Comparator.lt,
          const TextValue('aa'),
        ),
        isTrue,
      );
      expect(
        compareValues(
          const TextValue('A'),
          Comparator.neq,
          const TextValue('a'),
        ),
        isTrue,
      );
      expect(
        compareValues(
          const BooleanValue(false),
          Comparator.lt,
          const BooleanValue(true),
        ),
        isTrue,
      );
      expect(compareValues(const TextValue('1'), Comparator.eq, one), isNull);
      expect(
        compareValues(const BooleanValue(true), Comparator.eq, one),
        isNull,
      );
      expect(
        compareValues(
          SequenceValue([one]),
          Comparator.eq,
          SequenceValue([one]),
        ),
        isNull,
      );
    },
  );

  test('quantity comparison requires the identical unit without conversion or stripping', () {
    expect(
      compareValues(
        QuantityValue(one, unit(1)),
        Comparator.lt,
        QuantityValue(two, unit(1)),
      ),
      isTrue,
    );
    expect(
      compareValues(
        QuantityValue(one, unit(1)),
        Comparator.eq,
        QuantityValue(one, unit(2)),
      ),
      isNull,
    );
    expect(
      compareValues(QuantityValue(one, unit(1)), Comparator.eq, one),
      isNull,
    );
    expect(
      compareValues(
        range('1', '1', unit: unit(1)),
        Comparator.eq,
        QuantityValue(one, unit(1)),
      ),
      isTrue,
    );
    expect(
      compareValues(
        range('1', '2', unit: unit(1)),
        Comparator.lt,
        QuantityValue(const IntegerValue('3'), unit(2)),
      ),
      isNull,
    );
    expect(
      compareValues(range('1', '1', unit: unit(1)), Comparator.eq, one),
      isNull,
    );
  });

  test('overlapping uncertain ranges do not prove equality or inequality', () {
    final a = range('1', '3'), b = range('2', '4');
    for (final op in Comparator.values) {
      expect(compareValues(a, op, b), isNull);
    }
    expect(compareValues(a, Comparator.eq, a), isNull);
    expect(compareValues(range('1', '1'), Comparator.eq, one), isTrue);
    expect(
      compareValues(range('1', '2'), Comparator.eq, range('3', '4')),
      isFalse,
    );
    expect(
      compareValues(range('1', '2'), Comparator.neq, range('3', '4')),
      isTrue,
    );
    expect(
      compareValues(range('3', '4'), Comparator.gt, range('1', '2')),
      isTrue,
    );
    expect(
      compareValues(range('3', '4'), Comparator.gtEq, range('1', '2')),
      isTrue,
    );
  });

  test('open and closed endpoints retain all strict and non-strict boundary distinctions', () {
    final a = range('1', '2'), b = range('2', '3');
    expect(compareValues(a, Comparator.lt, b), isNull);
    expect(compareValues(a, Comparator.ltEq, b), isTrue);
    expect(
      compareValues(range('1', '2', right: false), Comparator.lt, b),
      isTrue,
    );
    expect(
      compareValues(a, Comparator.lt, range('2', '3', left: false)),
      isTrue,
    );
    expect(
      compareValues(a, Comparator.eq, range('2', '3', left: false)),
      isFalse,
    );
    expect(compareValues(two, Comparator.lt, a), isFalse);
    expect(
      compareValues(two, Comparator.ltEq, range('1', '2', right: false)),
      isFalse,
    );
    expect(
      compareValues(
        range('2', '3'),
        Comparator.ltEq,
        range('1', '2', right: false),
      ),
      isFalse,
    );
  });

  test('reversed, empty and nonnumeric ranges remain unresolved', () {
    for (final a in [
      range('3', '1'),
      range('1', '1', left: false),
      range('1', '1', right: false),
      const RangeValue(
        lower: TextValue('a'),
        upper: TextValue('b'),
        lowerInclusive: true,
        upperInclusive: true,
      ),
    ]) {
      expect(compareValues(a, Comparator.eq, one), isNull);
    }
    final mixed = RangeValue(
      lower: const DecimalValue('0.5'),
      upper: one,
      lowerInclusive: true,
      upperInclusive: true,
    );
    expect(compareValues(mixed, Comparator.lt, two), isTrue);
  });
}
