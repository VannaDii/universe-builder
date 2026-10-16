@TestOn('vm')
library;

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
  typeClientRef: '\ufeffPending end',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedAssertionEndForm input(EditorFormScope s, EvidenceBasis original) =>
    UnfinishedAssertionEndForm(
      baseRevision: RevisionId.generate(),
      representedContext: s.representedContext!,
      clientRef: s.typeClientRef!,
      target: const ExpressionReferenceInput(
        record: '',
        universe: '\ufeffUnfinished universe',
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      calendar: CalendarId.generate(),
      originalBasis: original,
      coordinate: '\ufeffPending coordinate',
      basis: const EvidenceBasisInput(
        kind: 'still choosing',
        note: '\ufeffNote\r\n\u0000😀',
        anchorRecord: 'disabled anchor',
        anchorUniverse: '',
        verified: true,
      ),
      rationale: '\ufeffReason\r\n記憶',
      draftVersion: maxU64,
    );
VersionRef version({UniverseId? universe}) => VersionRef(
  record: RecordId.generate(),
  version: RecordVersionId.generate(),
  universe: universe,
);
List<EvidenceBasis> bases() {
  final ref = RecordRef(
        record: RecordId.generate(),
        universe: UniverseId.generate(),
      ),
      v = version();
  return [
    const AuthorDecisionBasis('\ufeffAuthor note\r\n\u0000'),
    SourceAnchorBasis(ref, true),
    SourceAnchorBasis(RecordRef(record: ref.record), false),
    EventEffectBasis(ref, '\ufeffEffect slot'),
    InstanceInitializationBasis(
      v,
      version(universe: ref.universe),
      RevisionId.generate(),
    ),
    const ImportedClaimBasis(),
    DerivationBasis([v, version(universe: ref.universe), v], '\ufeffEvaluator'),
    DerivationBasis([], null),
    DerivationBasis([], ''),
  ];
}

void main() {
  test('assertion ending retains exact input and every evidence basis across typed recovery and replacement', () {
    final root = Directory('/tmp').createTempSync('ub-typed-assertion-end-'),
        s = scope();
    final path = '${root.path}/forms.sqlite';
    var store = AssertionEndFormRecoveryStore.open(path),
        generation = BigInt.zero;
    try {
      for (final basis in bases()) {
        final form = input(s, basis);
        generation = store.save(s, form, generation).generation;
        store.close();
        store = AssertionEndFormRecoveryStore.open(path);
        expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
        expect(
          store.save(s, form, generation - BigInt.one).generation,
          generation,
        );
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          expect(
            db
                .select('PRAGMA table_info(assertion_end_form)')
                .map((r) => r['name']),
            isNot(contains('form_input')),
          );
          expect(db.select('PRAGMA foreign_key_check'), isEmpty);
          expect(
            db
                .select('SELECT count(*) AS n FROM assertion_end_basis_version')
                .single['n'],
            basis is DerivationBasis
                ? basis.chain.length
                : basis is InstanceInitializationBasis
                ? 2
                : 0,
          );
        } finally {
          db.close();
        }
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
