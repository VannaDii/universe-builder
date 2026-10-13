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
  test('unfinished fields survive reopening, exact retries and competing-window conflicts', () {
    final root = Directory('/tmp').createTempSync('ub-forms-');
    final path = '${root.path}/forms.sqlite';
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
    );
    final form = UnfinishedWorldForm(
      baseRevision: RevisionId.generate(),
      representedContext: RecordId.generate(),
      record: RecordId.generate(),
      selector: '',
      settingType: 'unfinished 😀\r\n\u0000',
      rationale: 'Still researching',
      aliases: ['', '  exact alias  '],
      labels: {'en': 'A world', 'fr': 'Un monde'},
    );
    var store = WorldFormRecoveryStore.open(path);
    try {
      expect(store.load(scope), isNull);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      store.close();
      store = WorldFormRecoveryStore.open(path);
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      final other = UnfinishedWorldForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        record: form.record,
        selector: 'Second window',
        settingType: '',
        rationale: 'Different entered fields',
      );
      expect(
        () => store.save(scope, other, BigInt.zero),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(store.load(scope)!.form.selector, '');
      expect(store.save(scope, other, BigInt.one).generation, BigInt.two);
      expect(store.load(scope)!.form.selector, 'Second window');
      final editScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        worldClientRef: 'writer/world:river😀',
      );
      final edit = UnfinishedWorldForm(
        baseRevision: form.baseRevision,
        representedContext: form.representedContext,
        record: form.record,
        selector: '',
        settingType: 'Pending edit',
        rationale: '',
        draftVersion: (BigInt.one << 64) - BigInt.one,
      );
      expect(store.load(editScope), isNull);
      store.save(editScope, edit, BigInt.zero);
      store.close();
      store = WorldFormRecoveryStore.open(path);
      expect(
        store.load(editScope)!.form.toWire().toText(),
        edit.toWire().toText(),
      );
      expect(store.load(scope)!.form.selector, 'Second window');
      for (final otherScope in [
        EditorFormScope(
          instance: OperationId.generate(),
          profile: scope.profile,
          universe: scope.universe,
          continuity: scope.continuity,
        ),
        EditorFormScope(
          instance: scope.instance,
          profile: ProfileId.generate(),
          universe: scope.universe,
          continuity: scope.continuity,
        ),
        EditorFormScope(
          instance: scope.instance,
          profile: scope.profile,
          universe: UniverseId.generate(),
          continuity: scope.continuity,
        ),
        EditorFormScope(
          instance: scope.instance,
          profile: scope.profile,
          universe: scope.universe,
          continuity: ContinuityId.generate(),
        ),
      ]) {
        expect(store.load(otherScope), isNull);
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('adding edit recovery retains version-one unfinished work', () {
    final root = Directory('/tmp').createTempSync('ub-forms-upgrade-');
    final path = '${root.path}/forms.sqlite';
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
    );
    final revision = RevisionId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate();
    protectedFile(path, create: true);
    final db = sqlite3.open(path);
    db.execute('''
CREATE TABLE world_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, generation TEXT NOT NULL,
 base_revision TEXT NOT NULL, represented_context TEXT NOT NULL,
 record_id TEXT NOT NULL, selector TEXT NOT NULL, setting_type TEXT NOT NULL,
 rationale TEXT NOT NULL, PRIMARY KEY(instance,profile,universe,continuity)
) STRICT;
CREATE TABLE world_form_alias (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, ordinal INTEGER NOT NULL, value TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity) REFERENCES world_form(instance,profile,universe,continuity) ON DELETE CASCADE
) STRICT;
CREATE TABLE world_form_label (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, language TEXT NOT NULL, value TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,language),
 FOREIGN KEY(instance,profile,universe,continuity) REFERENCES world_form(instance,profile,universe,continuity) ON DELETE CASCADE
) STRICT;
PRAGMA user_version=1;
''');
    final binding = [
      scope.instance.value,
      scope.profile.value,
      scope.universe.value,
      scope.continuity.value,
    ];
    db.execute('INSERT INTO world_form VALUES(?,?,?,?,?,?,?,?,?,?,?)', [
      ...binding,
      '7',
      revision.value,
      context.value,
      record.value,
      'Old unfinished world',
      '',
      'Keep my notes\r\nexact',
    ]);
    db.execute('INSERT INTO world_form_alias VALUES(?,?,?,?,?,?)', [
      ...binding,
      0,
      'Old name',
    ]);
    db.execute('INSERT INTO world_form_label VALUES(?,?,?,?,?,?)', [
      ...binding,
      'fr',
      'Monde',
    ]);
    db.close();
    final store = WorldFormRecoveryStore.open(path);
    try {
      final saved = store.load(scope)!;
      expect(saved.generation, BigInt.from(7));
      expect(saved.form.selector, 'Old unfinished world');
      expect(saved.form.rationale, 'Keep my notes\r\nexact');
      expect(saved.form.aliases, ['Old name']);
      expect(saved.form.labels, {'fr': 'Monde'});
      expect(saved.form.draftVersion, isNull);
      expect(
        store.save(scope, saved.form, saved.generation).generation,
        BigInt.from(8),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
