@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/installation.dart' show protectedFile;

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

void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  protectedFile(path, createNew: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE pack_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, generation, text) in entries) {
      db.execute('INSERT INTO pack_form VALUES(?,?,?,?,?,?,?,?)', [
        ...binding(s),
        generation.toString(),
        text,
      ]);
    }
  } finally {
    db.close();
  }
}

void main() {
  test('v2 pack input upgrades without changing generic fields and retains unfinished policy choices', () {
    final root = Directory('/tmp').createTempSync('ub-policy-recovery-');
    final path = '${root.path}/forms.sqlite', s = scope(), original = pack(s);
    var store = PackFormRecoveryStore.open(path);
    try {
      store.save(s, original, BigInt.zero);
      store.close();
      final db = sqlite3.open(path);
      try {
        db.execute('ALTER TABLE pack_form DROP COLUMN policy_real_world');
        db.execute('ALTER TABLE pack_form DROP COLUMN policy_activate');
        db.execute('ALTER TABLE pack_form DROP COLUMN expected_root_version');
        db.execute('PRAGMA user_version=2');
      } finally {
        db.close();
      }
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
  test('legacy pack conversion preserves separate profiles and clears replaced input while retaining the original', () {
    final root = Directory('/tmp').createTempSync('ub-pack-conversion-');
    final path = '${root.path}/forms.sqlite', s = scope(), otherScope = scope();
    final input = pack(s), other = pack(otherScope, editing: false);
    legacy(path, [
      (s, BigInt.from(19), input.toWire().toText()),
      (otherScope, maxU64, other.toWire().toText()),
    ]);
    var store = PackFormRecoveryStore.open(path);
    final competing = PackFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), input.toWire().toText());
      expect(
        store.load(otherScope)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = input.copyWith(
        dependencies: [],
        capabilities: [],
        records: [],
        rationale: '\ufeffUpdated reason',
      );
      expect(
        store.save(s, changed, BigInt.from(19)).generation,
        BigInt.from(20),
      );
      expect(
        store.save(s, changed, BigInt.from(19)).generation,
        BigInt.from(20),
      );
      expect(
        () => competing.save(s, input, BigInt.from(19)),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        () => store.save(otherScope, other, maxU64),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.generationExhausted,
          ),
        ),
      );
      store.close();
      store = PackFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), changed.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 3);
        expect(
          db.select(
            "SELECT count(*) AS n FROM pack_dependency WHERE profile=? AND list_kind='input'",
            [s.profile.value],
          ).single['n'],
          0,
        );
        expect(
          db.select(
            "SELECT count(*) AS n FROM pack_item WHERE profile=? AND list_kind IN ('capabilities','records')",
            [s.profile.value],
          ).single['n'],
          0,
        );
        expect(
          db.select(
            "SELECT count(*) AS n FROM pack_dependency WHERE profile=? AND list_kind='original'",
            [s.profile.value],
          ).single['n'],
          input.original!.dependencies.length,
        );
      } finally {
        db.close();
      }
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test(
    'failed pack conversion retains every original row and the legacy format',
    () {
      final root = Directory('/tmp').createTempSync('ub-pack-rollback-');
      final path = '${root.path}/forms.sqlite',
          s = scope(),
          otherScope = scope();
      final text = pack(s).toWire().toText();
      legacy(path, [
        (s, BigInt.one, text),
        (otherScope, BigInt.two, '{unfinished'),
      ]);
      try {
        expect(
          () => PackFormRecoveryStore.open(path),
          throwsA(isA<EditorRecoveryException>()),
        );
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          expect(db.select('PRAGMA user_version').single.values.single, 1);
          expect(
            db
                .select('SELECT form_input FROM pack_form ORDER BY generation')
                .map((r) => r['form_input']),
            [text, '{unfinished'],
          );
          expect(
            db
                .select("SELECT name FROM sqlite_master WHERE type='table'")
                .map((r) => r['name']),
            ['pack_form'],
          );
        } finally {
          db.close();
        }
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );
}
