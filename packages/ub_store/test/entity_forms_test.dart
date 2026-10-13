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
  test(
    'version-two drafts retain pending input when association editing is added',
    () {
      final root = Directory('/tmp').createTempSync('ub-entity-v2-');
      final path = '${root.path}/entities.sqlite';
      final scope = EditorFormScope(
        instance: OperationId.generate(),
        profile: ProfileId.generate(),
        universe: UniverseId.generate(),
        continuity: ContinuityId.generate(),
        representedContext: RecordId.generate(),
        entityClientRef: 'draft-person',
      );
      final revision = RevisionId.generate();
      protectedFile(path, create: true);
      final db = sqlite3.open(path);
      db.execute("""
      CREATE TABLE entity_form (
        instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
        continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, generation TEXT NOT NULL,
        base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, name TEXT NOT NULL,
        classification TEXT NOT NULL, world_role TEXT NOT NULL, rationale TEXT NOT NULL, draft_version TEXT,
        PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
      ) STRICT;
      CREATE TABLE entity_form_world (
        instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
        continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), world TEXT NOT NULL,
        PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
        FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES entity_form(instance,profile,universe,continuity,context,editor_key) ON DELETE CASCADE
      ) STRICT;
      PRAGMA user_version=2;
    """);
      db.execute(
        'INSERT INTO entity_form VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          scope.instance.value,
          scope.profile.value,
          scope.universe.value,
          scope.continuity.value,
          scope.representedContext!.value,
          'draft-person',
          '7',
          revision.value,
          'draft-person',
          '人物',
          '',
          '',
          '',
          '12',
        ],
      );
      db.close();
      var store = EntityFormRecoveryStore.open(path);
      try {
        final original = store.load(scope)!;
        expect(original.generation, BigInt.from(7));
        expect(original.form.name, '人物');
        expect(original.form.draftVersion, BigInt.from(12));
        expect(original.form.associations, isNull);
        UnfinishedEntityForm form(List<EntityAssociationForm> rows) =>
            UnfinishedEntityForm(
              baseRevision: revision,
              representedContext: scope.representedContext!,
              clientRef: 'draft-person',
              name: '人物',
              classification: '',
              worldRole: '',
              rationale: '',
              draftVersion: BigInt.from(12),
              associations: rows,
            );
        final pending = form([
          const EntityAssociationForm(
            world: '',
            role: 'Unfinished',
            validity: UnknownValidity(),
            temporalValidity: TemporalValidityInput(
              calendar: 'unfinished',
              start: TemporalBoundInput(value: 'unknown text'),
            ),
            originalOrdinal: 1,
          ),
          const EntityAssociationForm(world: '', role: ''),
        ]);
        store.save(scope, pending, BigInt.from(7));
        store.close();
        store = EntityFormRecoveryStore.open(path);
        expect(
          store.load(scope)!.form.toWire().toText(),
          pending.toWire().toText(),
        );
        store.save(scope, form([]), BigInt.from(8));
        expect(store.load(scope)!.form.associations, isEmpty);
        store.save(scope, pending, BigInt.from(9));
        store.close();
        final legacy = sqlite3.open(path);
        legacy.execute(
          'ALTER TABLE entity_form_association DROP COLUMN validity; ALTER TABLE entity_form_association DROP COLUMN temporal_input; PRAGMA user_version=3',
        );
        legacy.close();
        store = EntityFormRecoveryStore.open(path);
        final upgraded = store.load(scope)!;
        expect(upgraded.form.associations!.first.temporalValidity, isNull);
        expect(upgraded.generation, BigInt.from(10));
        expect(upgraded.form.associations!.first.world, '');
        expect(upgraded.form.associations!.first.role, 'Unfinished');
        expect(upgraded.form.associations!.first.originalOrdinal, 1);
        expect(upgraded.form.associations!.first.validity, isNull);
        store.save(scope, pending, upgraded.generation);
        store.close();
        store = EntityFormRecoveryStore.open(path);
        expect(
          store.load(scope)!.form.toWire().toText(),
          pending.toWire().toText(),
        );
        store.close();
        final v4 = sqlite3.open(path);
        v4.execute(
          'ALTER TABLE entity_form_association DROP COLUMN temporal_input; PRAGMA user_version=4',
        );
        v4.close();
        store = EntityFormRecoveryStore.open(path);
        final priorValidity = store.load(scope)!;
        expect(
          priorValidity.form.associations!.first.validity,
          const UnknownValidity(),
        );
        expect(priorValidity.form.associations!.first.temporalValidity, isNull);
        store.save(scope, pending, priorValidity.generation);
        store.close();
        store = EntityFormRecoveryStore.open(path);
        expect(
          store.load(scope)!.form.toWire().toText(),
          pending.toWire().toText(),
        );
      } finally {
        store.close();
        root.deleteSync(recursive: true);
      }
    },
  );

  test(
    'legacy entity input survives upgrade while edits recover separately',
    () {
      final root = Directory('/tmp').createTempSync('ub-entity-upgrade-');
      final path = '${root.path}/entities.sqlite';
      final scope = EditorFormScope(
        instance: OperationId.generate(),
        profile: ProfileId.generate(),
        universe: UniverseId.generate(),
        continuity: ContinuityId.generate(),
        representedContext: RecordId.generate(),
      );
      final revision = RevisionId.generate(), world = WorldId.generate();
      protectedFile(path, create: true);
      final db = sqlite3.open(path);
      db.execute("""
      CREATE TABLE entity_form (
        instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
        continuity TEXT NOT NULL, context TEXT NOT NULL, generation TEXT NOT NULL,
        base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, name TEXT NOT NULL,
        classification TEXT NOT NULL, world_role TEXT NOT NULL, rationale TEXT NOT NULL,
        PRIMARY KEY(instance,profile,universe,continuity,context)
      ) STRICT;
      CREATE TABLE entity_form_world (
        instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
        continuity TEXT NOT NULL, context TEXT NOT NULL, ordinal INTEGER NOT NULL CHECK(ordinal>=0), world TEXT NOT NULL,
        PRIMARY KEY(instance,profile,universe,continuity,context,ordinal),
        FOREIGN KEY(instance,profile,universe,continuity,context) REFERENCES entity_form(instance,profile,universe,continuity,context) ON DELETE CASCADE
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
      db.execute('INSERT INTO entity_form VALUES(?,?,?,?,?,?,?,?,?,?,?,?)', [
        ...binding,
        '7',
        revision.value,
        'new-person',
        '人物',
        '',
        'home',
        'Pending',
      ]);
      db.execute('INSERT INTO entity_form_world VALUES(?,?,?,?,?,?,?)', [
        ...binding,
        0,
        world.value,
      ]);
      db.close();
      var store = EntityFormRecoveryStore.open(path);
      try {
        final original = store.load(scope)!;
        expect(original.generation, BigInt.from(7));
        expect(original.form.name, '人物');
        expect(original.form.worlds, [world]);
        expect(original.form.worldRole, 'home');
        expect(original.form.draftVersion, isNull);
        final editScope = EditorFormScope(
          instance: scope.instance,
          profile: scope.profile,
          universe: scope.universe,
          continuity: scope.continuity,
          representedContext: scope.representedContext,
          entityClientRef: 'draft-person',
        );
        final edit = UnfinishedEntityForm(
          baseRevision: revision,
          representedContext: scope.representedContext!,
          clientRef: 'draft-person',
          name: 'Edited',
          classification: '',
          worldRole: '',
          rationale: '',
          draftVersion: BigInt.from(12),
        );
        store.save(editScope, edit, BigInt.zero);
        store.close();
        store = EntityFormRecoveryStore.open(path);
        expect(
          store.load(editScope)!.form.toWire().toText(),
          edit.toWire().toText(),
        );
        expect(
          store.load(scope)!.form.toWire().toText(),
          original.form.toWire().toText(),
        );
        expect(
          () => store.save(editScope, original.form, BigInt.one),
          throwsFormatException,
        );
      } finally {
        store.close();
        root.deleteSync(recursive: true);
      }
    },
  );

  test('entity input keeps exact fields and world order across reopen and competing saves', () {
    final root = Directory('/tmp').createTempSync('ub-entity-forms-');
    final path = '${root.path}/entities.sqlite';
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final worlds = [WorldId.generate(), WorldId.generate()];
    UnfinishedEntityForm form(String name) => UnfinishedEntityForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: 'writer-person',
      name: name,
      classification: RecordId.generate().value,
      worldRole: 'Shared setting',
      rationale: '人物 😀\r\n\u0000',
      worlds: worlds,
    );
    var store = EntityFormRecoveryStore.open(path);
    try {
      final pending = form(' 人物 ');
      store.save(scope, pending, BigInt.zero);
      store.close();
      store = EntityFormRecoveryStore.open(path);
      expect(
        store.load(scope)!.form.toWire().toText(),
        pending.toWire().toText(),
      );
      expect(store.load(scope)!.form.worlds, worlds);
      expect(store.save(scope, pending, BigInt.zero).generation, BigInt.one);
      final changed = form('Revised');
      store.save(scope, changed, BigInt.one);
      expect(
        () => store.save(scope, pending, BigInt.one),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        store.load(scope)!.form.toWire().toText(),
        changed.toWire().toText(),
      );
      expect(
        () => store.save(scope, form('\ud800'), BigInt.two),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
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
    'incompatible entity recovery schema is refused without modifying it',
    () {
      final root = Directory('/tmp').createTempSync('ub-entity-schema-');
      final path = '${root.path}/entities.sqlite';
      final store = EntityFormRecoveryStore.open(path);
      store.close();
      final db = sqlite3.open(path);
      db.execute('PRAGMA user_version=6');
      db.close();
      final before = File(path).readAsBytesSync();
      try {
        expect(
          () => EntityFormRecoveryStore.open(path),
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
    },
  );
}
