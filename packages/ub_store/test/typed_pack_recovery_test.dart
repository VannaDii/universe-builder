@TestOn('vm')
library;

import 'dart:convert';
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
  typeClientRef: '\ufeffPack input',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
UnfinishedPackForm pack(EditorFormScope s, {bool editing = true}) {
  final record = RecordId.generate();
  return UnfinishedPackForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef!,
    key: '\ufeffHomebrew 記憶',
    version: '\ufeffStill choosing',
    rationale: '\ufeffReason 😀\r\n\u0000',
    draftVersion: editing ? maxU64 : null,
    dependencies: const [
      PackDependencyInput(key: '\ufeffPrerequisite', version: '\ufeffVersion'),
      PackDependencyInput(),
      PackDependencyInput(
        key: '\ufeffPrerequisite',
        version: 'another unfinished choice',
      ),
    ],
    capabilities: const ['\ufeffCapability', '', 'Repeated', 'Repeated'],
    records: const ['\ufeffPending record', '', 'Repeated', 'Repeated'],
    revisionTarget: editing
        ? const ExpressionReferenceInput(
            record: '',
            universe: '\ufeffPending universe',
          )
        : null,
    expectedRecordVersion: editing ? RecordVersionId.generate() : null,
    original: editing
        ? DomainPackRecord(
            key: '\ufeffOriginal pack',
            version: '\ufeff1',
            dependencies: {'\ufeffB': '\ufeff2', 'A': '', '\ufeffA': '\ufeff1'},
            capabilities: ['\ufeffOriginal capability', '', 'same', 'same'],
            records: [record, record],
          )
        : null,
  );
}

void main() {
  test('pack recovery retains unfinished policy choices across restart', () {
    final root = Directory('/tmp').createTempSync('ub-policy-recovery-');
    final path = '${root.path}/forms.sqlite', s = scope(), original = pack(s);
    var store = PackFormRecoveryStore.open(path);
    try {
      store.save(s, original, BigInt.zero);
      store.close();
      store = PackFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), original.toWire().toText());
      final policy = UnfinishedPackForm(
        baseRevision: RevisionId.generate(),
        representedContext: s.representedContext!,
        clientRef: s.typeClientRef!,
        key: '',
        realWorldPolicy: true,
        activatePolicy: false,
        expectedRootVersion: RecordVersionId.generate(),
        rationale: 'Still choosing the policy name 記憶.\r\n',
      );
      store.save(s, policy, BigInt.one);
      store.close();
      store = PackFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), policy.toWire().toText());
      expect(
        store
            .load(s)!
            .form
            .copyWith(realWorldPolicy: false, activatePolicy: true)
            .realWorldPolicy,
        isFalse,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('typed pack recovery retains ordered incomplete input and exact original metadata across restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-pack-');
    final path = '${root.path}/forms.sqlite', s = scope(), input = pack(s);
    var store = PackFormRecoveryStore.open(path);
    try {
      store.save(s, input, BigInt.zero);
      store.close();
      store = PackFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), input.toWire().toText());
      expect(store.save(s, input, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(pack_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select('SELECT CAST(pack_key AS BLOB) AS name FROM pack_form')
              .single['name'],
          utf8.encode(input.key),
        );
        expect(
          db
              .select(
                "SELECT CAST(dependency_key AS BLOB) AS name,CAST(dependency_version AS BLOB) AS version FROM pack_dependency WHERE list_kind='input' ORDER BY ordinal",
              )
              .map((r) => [r['name'], r['version']]),
          input.dependencies.map(
            (d) => [utf8.encode(d.key), utf8.encode(d.version)],
          ),
        );
        expect(
          db
              .select(
                "SELECT CAST(item AS BLOB) AS item FROM pack_item WHERE list_kind='capabilities' ORDER BY ordinal",
              )
              .map((r) => r['item']),
          input.capabilities.map(utf8.encode),
        );
      } finally {
        db.close();
      }
      expect(
        () => store.save(s, input.copyWith(rationale: '\ud800'), BigInt.one),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      expect(store.load(s)!.generation, BigInt.one);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
