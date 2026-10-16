@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

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
        expectedRecordVersion: RecordVersionId.generate(),
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
}
