import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_authorization_test.dart' as p;

void main() {
  final records = [
    f.row(50, WorldRecord(selector: 'Campaign')),
    f.row(51, WorldRecord(selector: 'Private')),
    f.row(20, p.entity(worlds: [50])),
    f.row(21, p.entity(worlds: [51])),
  ];
  test('impact retains conservative unrelated closure and canonical budget boundary', () {
    Impact read(int budget) => conservativeImpact(
      records: records.reversed.toList(),
      changedRecords: [f.id(20)],
      worldScope: null,
      byteBudget: budget,
    );
    final result = read(65536);
    expect(result.records, [f.id(20), f.id(21), f.id(50), f.id(51)]);
    expect(result.worldIds, [p.world(50), p.world(51)]);
    expect(result.coverage, Coverage.complete);
    final exact = result.toWire().toBytes().length;
    expect(read(exact).toWire().toText(), result.toWire().toText());
    expect(() => read(exact - 1), throwsA(isA<EvaluationLimitReachedError>()));
  });
  test('impact denies hidden or missing seeds before budget and discloses restricted closure', () {
    Impact read(RecordId seed, int budget) => conservativeImpact(
      records: records,
      changedRecords: [seed],
      worldScope: {p.world(50)},
      byteBudget: budget,
    );
    final result = read(f.id(20), 65536);
    expect(result.records, [f.id(20), f.id(50)]);
    expect(result.worldIds, [p.world(50)]);
    expect(result.coverage, Coverage.restricted);
    for (final seed in [f.id(21), f.id(999)]) {
      expect(() => read(seed, 0), throwsA(isA<NotFoundOrNotAccessibleError>()));
    }
  });
}
