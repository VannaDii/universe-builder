import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('calculation keys trim fractional zeros without rounding', () {
    final amount = ExactAmount.tryParse('-0.12500000000000000100')!;
    expect(amount.coefficient, BigInt.parse('-125000000000000001'));
    expect(amount.scale, 18);
    expect(ExactAmount.tryParse('30.00')!.coefficient, BigInt.from(30));
    expect(ExactAmount.tryParse('30.00')!.scale, 0);
  });
  test('consequence decimal enforces existing checked i128 limits', () {
    for (final text in [
      '-0.125000000000000001',
      '1.2300',
      '170141183460469231731687303715884105727',
      '-170141183460469231731687303715884105728',
    ]) {
      expect(ExactAmount.isConsequenceDecimal(text), isTrue, reason: text);
    }
    for (final text in [
      '1e2',
      '00.1',
      '-0',
      '+1',
      '1.',
      '.1',
      '170141183460469231731687303715884105728',
      '-170141183460469231731687303715884105729',
      '0.000000000000000000000000000000000000001',
    ]) {
      expect(ExactAmount.isConsequenceDecimal(text), isFalse, reason: text);
    }
  });
}
