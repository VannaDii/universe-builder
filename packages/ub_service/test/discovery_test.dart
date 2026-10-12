import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_authorization_test.dart' as p;
import 'structural_checks_test.dart' as s;
import 'rule_checks_test.dart' as rules;

void main() {
  test('description filters visible definitions while retaining full visible world discovery', () {
    final rows = [
      f.row(50, WorldRecord(selector: 'Campaign')),
      f.row(51, WorldRecord(selector: 'Private')),
      f.row(20, p.entity(worlds: [50])),
      f.row(80, rules.rule(expr: const LiteralExpr(true))),
      f.row(
        81,
        rules.rule(
          expr: const LiteralExpr(true),
          applicability: WorldsApplicability([p.world(51)]),
        ),
      ),
    ];
    final result = discoveryDescription(
      records: rows,
      visibility: rows.map((r) => r.identity.recordId).toSet(),
      definitions: true,
      focus: p.world(50),
    );
    expect(result.fixture, isFalse);
    expect(result.worlds.map((w) => w.name.value), ['Campaign', 'Private']);
    expect(result.definitionIds, [f.id(80)]);
    final hidden = discoveryDescription(
      records: rows,
      visibility: {f.id(50), f.id(20)},
      definitions: true,
    );
    expect(hidden.worlds.map((w) => w.id), [p.world(50)]);
    expect(hidden.definitionIds, isEmpty);
    expect(
      result.capabilities
          .firstWhere((c) => c.id == 'knowledge.inference')
          .status,
      CapabilityStatus.unsupported,
    );
    expect(
      result.capabilities
          .firstWhere((c) => c.id == 'continuities.packs.v1')
          .status,
      CapabilityStatus.partial,
    );
  });
  test('continuity discovery omits hidden contexts and continuities without accessible contexts', () {
    final rows = [
      f.row(51, WorldRecord(selector: 'Private')),
      f.row(21, p.entity(worlds: [51])),
      f.row(
        31,
        RepresentedContextRecord(
          universe: f.u,
          kind: CharacterContext(f.ref(21)),
          labels: {'en': 'Private narrator'},
        ),
      ),
    ];
    ContinuitySummary? read(List<RecordVersion> records, Set<WorldId>? scope) =>
        discoveryContinuity(
          id: rules.frame().continuity,
          revision: f.revision,
          name: 'Alternate',
          records: records,
          worldScope: scope,
        );
    final unrestricted = read(rows, null)!;
    expect(unrestricted.name, 'Alternate');
    expect(unrestricted.representedContexts.single.id, f.id(31));
    expect(read(rows, {p.world(50)}), isNull);
    final visible = read([...rows, s.context(99)], {p.world(50)})!;
    expect(visible.representedContexts.map((c) => c.id), [f.id(99)]);
    expect(visible.revisionId, f.revision);
  });
}
