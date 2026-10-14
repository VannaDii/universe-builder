@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  test('version two type input upgrades without inventing revision fields', () {
    final root = Directory('/tmp').createTempSync('ub-type-v2-'),
        path = '${root.path}/types.sqlite';
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedTypeForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: 'unfinished',
      namespace: '',
      key: '',
      name: '人物 😀',
      parentChoice: '',
      applicabilityChoice: '',
      rationale: '',
    );
    var store = TypeFormRecoveryStore.open(path);
    store.save(scope, form, BigInt.zero);
    store.close();
    final db = sqlite3.open(path);
    db.execute(
      'ALTER TABLE type_form DROP COLUMN revision_input; PRAGMA user_version=2',
    );
    db.close();
    try {
      store = TypeFormRecoveryStore.open(path);
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.load(scope)!.form.revisionTarget, isNull);
      expect(store.load(scope)!.generation, BigInt.one);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('type input preserves unresolved choices and exact fields across reopen and competing saves', () {
    final root = Directory('/tmp').createTempSync('ub-type-forms-');
    final path = '${root.path}/types.sqlite';
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    UnfinishedTypeForm form({bool? executable, String key = ''}) =>
        UnfinishedTypeForm(
          baseRevision: RevisionId.parse('rev_000000000000000000000001'),
          representedContext: scope.representedContext!,
          clientRef: 'writer-provided-reference',
          namespace: '',
          key: key,
          name: ' 人物 😀\r\n\u0000 ',
          parentChoice: '',
          applicabilityChoice: '',
          classificationExecutable: executable,
          rationale: 'Keep incomplete choices',
          worlds: [WorldId.generate(), WorldId.generate()],
        );
    var store = TypeFormRecoveryStore.open(path);
    try {
      final pending = form();
      expect(store.save(scope, pending, BigInt.zero).generation, BigInt.one);
      store.close();
      store = TypeFormRecoveryStore.open(path);
      final recovered = store.load(scope)!;
      expect(recovered.form.toWire().toText(), pending.toWire().toText());
      expect(recovered.form.classificationExecutable, isNull);
      expect(recovered.form.parentChoice, '');
      expect(recovered.form.applicabilityChoice, '');
      expect(store.save(scope, pending, BigInt.zero).generation, BigInt.one);
      final completed = form(executable: false, key: 'person');
      expect(store.save(scope, completed, BigInt.one).generation, BigInt.two);
      expect(
        () => store.save(scope, pending, BigInt.one),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        store.load(scope)!.form.toWire().toText(),
        completed.toWire().toText(),
      );
      final other = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: RecordId.generate(),
      );
      expect(store.load(other), isNull);
      expect(
        () => store.save(other, completed, BigInt.zero),
        throwsFormatException,
      );
      final invalid = UnfinishedTypeForm(
        baseRevision: pending.baseRevision,
        representedContext: pending.representedContext,
        clientRef: pending.clientRef,
        namespace: '\ud800',
        key: '',
        name: '',
        parentChoice: '',
        applicabilityChoice: '',
        rationale: '',
      );
      expect(
        () => store.save(scope, invalid, BigInt.two),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      expect(store.load(scope)!.generation, BigInt.two);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test(
    'legacy input survives upgrade and draft edits recover in separate slots',
    () {
      final root = Directory('/tmp').createTempSync('ub-type-upgrade-');
      final path = '${root.path}/types.sqlite';
      final scope = EditorFormScope(
        instance: OperationId.generate(),
        profile: ProfileId.generate(),
        universe: UniverseId.generate(),
        continuity: ContinuityId.generate(),
        representedContext: RecordId.generate(),
      );
      final revision = RevisionId.generate();
      final worlds = [WorldId.generate(), WorldId.generate()];
      protectedFile(path, create: true);
      final db = sqlite3.open(path);
      db.execute("""
      CREATE TABLE type_form (
        instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
        continuity TEXT NOT NULL, context TEXT NOT NULL, generation TEXT NOT NULL,
        base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, namespace TEXT NOT NULL,
        key TEXT NOT NULL, name TEXT NOT NULL, parent_choice TEXT NOT NULL,
        applicability_choice TEXT NOT NULL, rationale TEXT NOT NULL,
        classification_executable INTEGER CHECK(classification_executable IN (0,1)),
        PRIMARY KEY(instance,profile,universe,continuity,context)
      ) STRICT;
      CREATE TABLE type_form_world (
        instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
        continuity TEXT NOT NULL, context TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK(ordinal>=0), world TEXT NOT NULL,
        PRIMARY KEY(instance,profile,universe,continuity,context,ordinal),
        FOREIGN KEY(instance,profile,universe,continuity,context)
          REFERENCES type_form(instance,profile,universe,continuity,context) ON DELETE CASCADE
      ) STRICT;
      PRAGMA user_version=1;
    """);
      final binding = [
        scope.instance.value,
        scope.profile.value,
        scope.universe.value,
        scope.continuity.value,
        scope.representedContext!.value,
      ];
      db.execute(
        'INSERT INTO type_form VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          ...binding,
          '7',
          revision.value,
          'new-type',
          '',
          '',
          '人物',
          '',
          'worlds',
          'Unfinished',
          null,
        ],
      );
      for (var i = 0; i < worlds.length; i++) {
        db.execute('INSERT INTO type_form_world VALUES(?,?,?,?,?,?,?)', [
          ...binding,
          i,
          worlds[i].value,
        ]);
      }
      db.close();
      var store = TypeFormRecoveryStore.open(path);
      try {
        final legacy = store.load(scope)!;
        expect(legacy.generation, BigInt.from(7));
        expect(legacy.form.name, '人物');
        expect(legacy.form.parentChoice, '');
        expect(legacy.form.classificationExecutable, isNull);
        expect(legacy.form.worlds, worlds);
        expect(legacy.form.draftVersion, isNull);
        final editScope = EditorFormScope(
          instance: scope.instance,
          profile: scope.profile,
          universe: scope.universe,
          continuity: scope.continuity,
          representedContext: scope.representedContext,
          typeClientRef: 'draft-type',
        );
        final edit = UnfinishedTypeForm(
          baseRevision: revision,
          representedContext: scope.representedContext!,
          clientRef: 'draft-type',
          namespace: 'authored',
          key: 'person',
          name: 'Edited',
          parentChoice: 'none',
          applicabilityChoice: 'worlds',
          worlds: worlds.reversed,
          classificationExecutable: false,
          rationale: '',
          draftVersion: BigInt.from(12),
        );
        store.save(editScope, edit, BigInt.zero);
        store.close();
        store = TypeFormRecoveryStore.open(path);
        expect(
          store.load(editScope)!.form.toWire().toText(),
          edit.toWire().toText(),
        );
        expect(
          store.load(scope)!.form.toWire().toText(),
          legacy.form.toWire().toText(),
        );
        expect(store.load(scope)!.generation, BigInt.from(7));
        expect(
          () => store.save(editScope, legacy.form, BigInt.one),
          throwsFormatException,
        );
      } finally {
        store.close();
        root.deleteSync(recursive: true);
      }
    },
  );

  test('incompatible type recovery schema is refused without modifying it', () {
    final root = Directory('/tmp').createTempSync('ub-type-schema-');
    final path = '${root.path}/types.sqlite';
    final store = TypeFormRecoveryStore.open(path);
    store.close();
    final db = sqlite3.open(path);
    db.execute('PRAGMA user_version=4');
    db.close();
    final before = File(path).readAsBytesSync();
    try {
      expect(
        () => TypeFormRecoveryStore.open(path),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.incompatibleSchema,
          ),
        ),
      );
      expect(File(path).readAsBytesSync(), before);
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
