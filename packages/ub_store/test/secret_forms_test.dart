@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('secret recovery retains partial ordered references and distinguishes unanswered disclosure', () {
    final root = Directory.systemTemp.createTempSync('ub-secret-forms-');
    final path = '${root.path}/forms.sqlite';
    var store = SecretFormRecoveryStore.open(path);
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedSecretForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: 'heir',
      scope: [
        const ExpressionReferenceInput(record: ''),
        const ExpressionReferenceInput(record: 'pending-name 記憶'),
      ],
      fictionalKnowers: [
        const ExpressionReferenceInput(record: 'character'),
        const ExpressionReferenceInput(record: 'character'),
      ],
      hasConcealment: true,
      concealment: 'Mémoire 😀\r\n',
      start: '-9007199254740993',
      end: '',
      draftVersion: BigInt.parse('18446744073709551615'),
    );
    try {
      final saved = store.save(scope, form, BigInt.zero);
      expect(saved.generation, BigInt.one);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      store.close();
      store = SecretFormRecoveryStore.open(path);
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.load(scope)!.form.readerDisclosed, isNull);
      final answered = form.copyWith(readerDisclosed: false, concealment: '');
      expect(store.save(scope, answered, BigInt.one).generation, BigInt.two);
      expect(store.load(scope)!.form.readerDisclosed, isFalse);
      expect(store.load(scope)!.form.hasConcealment, isTrue);
      expect(store.load(scope)!.form.concealment, isEmpty);
      expect(
        () => store.save(scope, form, BigInt.one),
        throwsA(isA<EditorRecoveryException>()),
      );
      final other = EditorFormScope(
        instance: scope.instance,
        profile: ProfileId.generate(),
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
      );
      expect(store.load(other), isNull);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
