import 'package:ub_service/src/universe_evidence_policy.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as rules;

void main() {
  final root = initialUniversePolicyRecords(f.u, false);
  final frame = Frame(
    universe: f.u,
    continuity: rules.frame().continuity,
    revision: f.revision,
    context: f.ref(99),
    time: const TimelessFrameTime(),
    perspective: const AuthorPerspective(),
  );
  test('brief keeps visible constraints first and reports missing dependencies as partial', () {
    final rows = [
      ...root,
      f.row(1, f.entity()),
      f.row(9, rules.rule()),
      f.row(80, f.entity()),
    ];
    final page = buildContextBrief(
      all: rows,
      accessible: rows,
      visibility: rows.map((r) => r.identity.recordId).toSet(),
      focusIds: [f.id(1)],
      frame: frame,
      world: null,
      restricted: false,
      byteBudget: 100000,
      offset: 0,
    );
    expect(page.brief.records.first.identity.recordKind, RecordKind.domainPack);
    expect(page.brief.requiredDependencies, contains(f.id(9)));
    expect(
      page.brief.records.map((r) => r.identity.recordId),
      contains(f.id(80)),
    );
    expect(page.complete, isTrue);
    final absent = buildContextBrief(
      all: rows,
      accessible: rows.where((r) => r.identity.recordId != f.id(80)).toList(),
      visibility: {f.id(1), f.id(9)},
      focusIds: [f.id(1)],
      frame: frame,
      world: null,
      restricted: false,
      byteBudget: 100000,
      offset: 0,
    );
    expect(absent.brief.coverage, Coverage.partial);
  });
  test('brief never claims complete evidence for hidden rules or a restricted perspective', () {
    final rows = [f.row(1, f.entity()), f.row(9, rules.rule()), ...root];
    final page = buildContextBrief(
      all: rows,
      accessible: [rows.first],
      visibility: {f.id(1)},
      focusIds: [f.id(1)],
      frame: frame,
      world: null,
      restricted: false,
      byteBudget: 100000,
      offset: 0,
    );
    expect(page.brief.records.length, 1);
    expect(page.brief.coverage, Coverage.partial);
    final restricted = buildContextBrief(
      all: [rows.first, ...root],
      accessible: [rows.first],
      visibility: {f.id(1)},
      focusIds: [f.id(1)],
      frame: frame,
      world: null,
      restricted: true,
      byteBudget: 100000,
      offset: 0,
    );
    expect(restricted.brief.coverage, Coverage.partial);
  });
  test('cursor preserves wide offsets and binds exact arguments without the cursor token', () {
    final principal = ProfileId.generate();
    CanonicalObject args(String purpose, {String? cursor}) => CanonicalObject([
      MapEntry('purpose', CanonicalString(purpose)),
      if (cursor != null) MapEntry('cursor', CanonicalString(cursor)),
    ]);
    String binding(CanonicalObject args) => readCursorBinding(
      args: args,
      frame: frame,
      principal: principal,
      scopeHash: 'grant',
    );
    expect(
      binding(args('research')),
      binding(args('research', cursor: 'opaque')),
    );
    expect(binding(args('research')), isNot(binding(args('different'))));
    expect(
      binding(args('research')),
      isNot(
        readCursorBinding(
          args: args('research'),
          frame: frame,
          principal: ProfileId.generate(),
          scopeHash: 'grant',
        ),
      ),
    );
    expect(
      binding(args('research')),
      isNot(
        readCursorBinding(
          args: args('research'),
          frame: frame,
          principal: principal,
          scopeHash: 'changed',
        ),
      ),
    );
    final wide = BigInt.parse('18446744073709551615');
    final cursor = StoredReadCursor(
      binding: binding(args('research')),
      offset: wide,
    );
    expect(
      StoredReadCursor.fromWire(
        CanonicalValue.parseJson(cursor.toWire().toText()),
      ).offset,
      wide,
    );
  });

  test('hidden active universe appearance prevents a complete brief', () {
    final entity = f.row(1, f.entity());
    final appearance = f.row(
      2,
      AppearanceRecord(
        target: const UniverseAppearance(),
        label: 'Hidden reference',
        physicalDescription: '',
        atmosphere: '',
        images: [],
        links: [],
        validity: const UnspecifiedValidity(),
      ),
    );
    final page = buildContextBrief(
      all: [entity, appearance, ...root],
      accessible: [entity],
      visibility: {f.id(1)},
      focusIds: [f.id(1)],
      frame: frame,
      world: null,
      restricted: false,
      byteBudget: 100000,
      offset: 0,
    );
    expect(page.brief.coverage, Coverage.partial);
    expect(page.brief.records.length, 1);
  });
}
