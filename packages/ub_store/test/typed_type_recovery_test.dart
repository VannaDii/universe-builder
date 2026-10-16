@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope({bool edit = true}) => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: edit ? '\ufeffPending type' : null,
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef ?? '',
];
UnfinishedTypeForm input(EditorFormScope s, {bool empty = false}) {
  final world = WorldId.generate();
  return UnfinishedTypeForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef ?? '\ufeffCreation',
    namespace: '\ufeffAuthored',
    key: '\ufeffKey',
    name: empty ? '' : '\ufeffName\r\n\u0000😀',
    parentChoice: 'unfinished parent',
    applicabilityChoice: 'undecided',
    rationale: '\ufeffReason',
    classificationExecutable: empty ? null : true,
    worlds: empty ? [] : [world, world],
    draftVersion: empty ? null : maxU64,
    revisionTarget: empty
        ? null
        : RecordRef(record: RecordId.generate(), universe: s.universe),
    expectedRecordVersion: empty ? null : RecordVersionId.generate(),
    parentResolution: empty ? '' : 'unfinished resolution',
    labels: empty
        ? []
        : const [
            PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
            PropertyLabelInput(),
            PropertyLabelInput(language: '\ufeffen', text: 'Repeated'),
          ],
    original: empty
        ? null
        : EntityTypeRecord(
            namespace: '\ufeffOriginal',
            key: '\ufeffType',
            name: '',
            labels: {'\ufeffen': '\ufeffOriginal', '': '', 'ja': '記憶😀'},
            parent: RecordId.generate(),
            parentResolution: ParentResolution.resolved,
            applicability: WorldsApplicability([world, world]),
            classificationExecutable: false,
          ),
  );
}

void main() {
  test('typed type recovery retains exact revision metadata, labels, worlds and original definition through restart and replacement', () {
    final root = Directory('/tmp').createTempSync('ub-typed-type-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = TypeFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = TypeFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      store.save(s, form, BigInt.one);
      final empty = input(s, empty: true);
      store.save(s, empty, BigInt.two);
      store.close();
      store = TypeFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), empty.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(type_form)').map((r) => r['name']),
          isNot(contains('revision_input')),
        );
        for (final r in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name!='type_form'",
        )) {
          expect(
            db.select('SELECT count(*) AS n FROM "${r['name']}"').single['n'],
            0,
            reason: r['name'] as String,
          );
        }
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
