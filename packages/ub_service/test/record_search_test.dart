import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_authorization_test.dart' as permissions;

void main() {
  test('search matches secondary labels aliases and exact identities within typed accessible records', () {
    final rows = [
      f.row(1, permissions.entity(labels: {'en': 'Primary', 'fr': 'Québec'})),
      f.row(2, WorldRecord(selector: 'Earth', aliases: ['Terra'])),
      f.row(3, f.entity()),
    ];
    List<SearchHit> search(String query, {List<RecordKind> kinds = const []}) =>
        buildSearchHits(
          accessible: rows,
          indexed: {f.id(99)},
          query: query,
          filters: Filters(recordKinds: kinds),
          world: null,
          author: true,
        );
    expect(search('QUÉ').single.recordId, f.id(1));
    expect(search('terra').single.recordId, f.id(2));
    expect(search(f.id(3).value).single.recordId, f.id(3));
    expect(search('', kinds: [RecordKind.world]).single.recordId, f.id(2));
    expect(search('unavailable'), isEmpty);
  });
  test('research labels use only visible dependencies and require author perspective', () {
    final rows = [
      f.row(1, permissions.entity(labels: {'en': 'Alice'})),
      f.row(2, f.type(2, key: 'open')),
      f.row(4, f.prop(10)),
      f.row(5, f.attitude()),
      f.row(
        6,
        CommunicationRecord(
          sender: f.ref(1),
          intendedRecipients: [],
          actualRecipients: [],
          content: [f.ref(4)],
          sentAt: const UnspecifiedTime(),
          distorted: false,
        ),
      ),
      f.row(
        7,
        ItemPowerRecord(
          item: f.ref(1),
          holderPredicate: f.ref(2),
          powerPredicate: f.ref(2),
          value: const BooleanValue(true),
          scope: f.scope,
          validity: const UnspecifiedValidity(),
        ),
      ),
      f.row(
        8,
        ObservationRecord(
          observer: f.ref(1),
          observed: f.ref(4),
          sensoryAccess: false,
          time: const UnspecifiedTime(),
          basis: const ImportedClaimBasis(),
        ),
      ),
      f.row(
        9,
        MemoryRecord(
          holder: f.ref(1),
          content: f.ref(4),
          accessibility: 'Uncertain',
          altered: true,
          validity: const UnspecifiedValidity(),
        ),
      ),
    ];
    final visible = {for (final row in rows) row.identity.recordId: row};
    expect(
      recordSearchLabel(rows[3], visible, author: true),
      'Alice — Believes Alice.open',
    );
    expect(
      recordSearchLabel(rows[4], visible, author: true),
      'Alice — message Alice.open',
    );
    expect(recordSearchLabel(rows[5], visible, author: true), 'Alice — open');
    expect(
      recordSearchLabel(rows[6], visible, author: true),
      'Alice — observation of Alice.open',
    );
    expect(
      recordSearchLabel(rows[6], {f.id(8): rows[6]}, author: true),
      f.id(8).value,
    );

    expect(recordSearchLabel(rows[3], visible, author: false), f.id(5).value);
    expect(
      recordSearchLabel(rows[5], {f.id(7): rows[5]}, author: true),
      f.id(7).value,
    );
    expect(
      recordSearchLabel(rows[7], visible, author: true),
      'Alice — memory of Alice.open',
    );
    expect(
      recordSearchLabel(rows[7], {f.id(9): rows[7]}, author: true),
      f.id(9).value,
    );
  });
  test('proposition choices distinguish quantification exact values context and ordered participants', () {
    final rows = [
      f.row(1, permissions.entity(labels: {'en': 'Mara'})),
      f.row(2, f.type(2, key: 'account')),
      f.row(
        3,
        RepresentedContextRecord(
          universe: f.u,
          kind: const AuthoredContext('Diary'),
          labels: {},
        ),
      ),
      f.row(8, permissions.entity(labels: {'en': 'Nia 記憶 😀'})),
      f.row(
        4,
        PropositionRecord(
          subject: f.ref(1),
          predicate: f.ref(2),
          context: f.ref(3),
          quantification: Quantification.exists,
          value: IntegerValue('9007199254740997'),
          roles: [
            PropositionRole('listener', f.ref(8)),
            PropositionRole('listener', f.ref(8)),
          ],
        ),
      ),
    ];
    final visible = {for (final row in rows) row.identity.recordId: row};
    const expected =
        'Exists: Mara.account = 9007199254740997 — listener: Nia 記憶 😀; listener: Nia 記憶 😀 [Diary]';
    expect(recordSearchLabel(rows.last, visible, author: true), expected);
    final hit = buildSearchHits(
      accessible: rows,
      indexed: {},
      query: 'Nia 記憶',
      filters: Filters(recordKinds: [RecordKind.proposition]),
      world: null,
      author: true,
    ).single;
    expect(hit.recordId, f.id(4));
    expect(hit.label, expected);
    expect(recordSearchLabel(rows.last, visible, author: false), f.id(4).value);
    expect(
      buildSearchHits(
        accessible: rows,
        indexed: {},
        query: 'Nia 記憶',
        filters: Filters(recordKinds: [RecordKind.proposition]),
        world: null,
        author: false,
      ),
      isEmpty,
    );
    final restricted = {...visible}..remove(f.id(8));
    expect(
      recordSearchLabel(rows.last, restricted, author: true),
      f.id(4).value,
    );
    expect(
      buildSearchHits(
        accessible: rows.where((r) => r.identity.recordId != f.id(8)).toList(),
        indexed: {},
        query: 'Nia 記憶',
        filters: Filters(recordKinds: [RecordKind.proposition]),
        world: null,
        author: true,
      ),
      isEmpty,
    );
    final foreign = f.row(
      9,
      PropositionRecord(
        subject: RecordRef(universe: UniverseId.generate(), record: f.id(1)),
        predicate: f.ref(2),
        context: f.ref(3),
        quantification: Quantification.particular,
      ),
    );
    expect(recordSearchLabel(foreign, visible, author: true), f.id(9).value);
  });
  test('search preserves selected shared unassigned and required dependency categories', () {
    final rows = [
      f.row(1, permissions.entity(worlds: [50])),
      f.row(2, permissions.entity(worlds: [50, 51])),
      f.row(3, f.entity()),
      f.row(4, permissions.entity(worlds: [51])),
    ];
    final hits = buildSearchHits(
      accessible: rows,
      indexed: {},
      query: '',
      filters: Filters(recordKinds: []),
      world: permissions.world(50),
      author: true,
    );
    expect(hits.map((hit) => hit.scopeCategory), [
      ScopeCategory.selectedWorld,
      ScopeCategory.shared,
      ScopeCategory.unassigned,
      ScopeCategory.requiredDependency,
    ]);
  });
}
