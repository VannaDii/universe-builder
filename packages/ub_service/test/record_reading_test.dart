import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'proposal_authorization_test.dart' as permissions;
import 'structural_checks_test.dart' as structure;

AppearanceRecord appearance(AppearanceTarget target) => AppearanceRecord(
  target: target,
  label: 'Reference',
  physicalDescription: '',
  atmosphere: '',
  images: [],
  links: [],
  validity: const UnspecifiedValidity(),
);

void main() {
  test('read labels use canonical Unicode order and authored fallback', () {
    expect(
      recordReadLabel(
        f.row(
          1,
          permissions.entity(labels: {'\u{10000}': 'later', '\ue000': 'first'}),
        ),
      ),
      'first',
    );
    expect(
      recordReadLabel(
        f.row(
          4,
          RealmRecord(labels: {'en': 'Dream realm 記憶 😀'}, metadata: {}),
        ),
      ),
      'Dream realm 記憶 😀',
    );
    expect(
      recordReadLabel(
        f.row(
          5,
          AnchorRecord(
            sourceVersion: VersionRef(
              record: f.id(6),
              version: RecordVersionId.generate(),
            ),
            locator: ByteRangeLocator(BigInt.zero, BigInt.one),
            excerptDigest: '',
            excerpt: 'Exact excerpt 記憶 😀',
          ),
        ),
      ),
      'Exact excerpt 記憶 😀',
    );
    expect(recordReadLabel(structure.context(99)), f.id(99).value);
    expect(
      recordReadLabel(
        f.row(
          3,
          RepresentedContextRecord(
            universe: f.u,
            kind: const AuthoredContext('Diary'),
            labels: {},
          ),
        ),
      ),
      'Diary',
    );
  });

  test('dependency closure follows visible appearance attachments and ignores missing edges', () {
    final rows = [
      f.row(1, f.entity(classification: f.id(4))),
      f.row(2, appearance(EntryAppearance(f.ref(1)))),
      f.row(3, appearance(const UniverseAppearance())),
      f.row(4, f.type(4)),
      f.row(5, f.entity()),
    ];
    expect(readDependencyClosure(rows, [f.id(1)]), {
      f.id(1),
      f.id(2),
      f.id(3),
      f.id(4),
    });
    expect(
      readDependencyClosure(
        rows.where((r) => r.identity.recordId != f.id(4)).toList(),
        [f.id(1)],
      ),
      {f.id(1), f.id(2), f.id(3)},
    );
  });

  test('research follows subject evidence without reverse predicate or context leakage', () {
    final rows = [
      f.row(1, f.entity()),
      f.row(2, f.type(2)),
      structure.context(3),
      f.row(4, f.prop(10)),
      f.row(5, f.assertion()),
      f.row(6, f.entity()),
      f.row(7, f.prop(11, subject: 6)),
      f.row(8, f.assertion(target: 7)),
    ];
    expect(readResearchClosure(rows, [f.id(1)]), {
      f.id(1),
      f.id(2),
      f.id(3),
      f.id(4),
      f.id(5),
    });
    expect(readResearchClosure(rows, [f.id(2)]), {f.id(2)});
    expect(readResearchClosure(rows, [f.id(3)]), {f.id(3)});
  });
}
