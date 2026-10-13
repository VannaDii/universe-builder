@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
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

  test('incompatible type recovery schema is refused without modifying it', () {
    final root = Directory('/tmp').createTempSync('ub-type-schema-');
    final path = '${root.path}/types.sqlite';
    final store = TypeFormRecoveryStore.open(path);
    store.close();
    final db = sqlite3.open(path);
    db.execute('PRAGMA user_version=2');
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
