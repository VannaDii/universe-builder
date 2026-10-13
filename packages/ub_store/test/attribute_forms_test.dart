@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('legacy attribute value recovery retains pending fields when assertion input is added', () {
    final root = Directory('/tmp').createTempSync('ub-attribute-v1-');
    final path = '${root.path}/forms.sqlite';
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
      attributeClientRef: 'attribute',
    );
    final initial = UnfinishedAttributeForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: 'attribute',
      draftVersion: BigInt.two,
      value: const QualifierInput(kind: 'decimal', value: 'unfinished 😀'),
    );
    var store = AttributeFormRecoveryStore.open(path);
    store.save(scope, initial, BigInt.zero);
    store.close();
    final db = sqlite3.open(path);
    db.execute(
      'ALTER TABLE attribute_form DROP COLUMN evidence_input; PRAGMA user_version=1',
    );
    db.close();
    store = AttributeFormRecoveryStore.open(path);
    try {
      final legacy = store.load(scope)!;
      expect(legacy.form.toWire().toText(), initial.toWire().toText());
      expect(legacy.form.evidenceInput, isNull);
      final pending = UnfinishedAttributeForm(
        baseRevision: initial.baseRevision,
        representedContext: initial.representedContext,
        clientRef: initial.clientRef,
        draftVersion: initial.draftVersion,
        value: initial.value,
        evidenceInput: const AttributeEvidenceInput(
          polarity: Polarity.refutation,
          precision: Precision.unresolved,
          persistence: PersistenceSemantics.conditionDependent,
          temporalValidity: TemporalValidityInput(
            kind: 'instant_duration',
            calendar: 'unfinished calendar 😀',
            start: TemporalBoundInput(
              uncertaintyKind: 'typed',
              amount: QualifierInput(
                kind: 'sequence',
                children: [
                  QualifierInput(kind: 'text', value: '記憶 😀\namount'),
                ],
              ),
            ),
          ),
        ),
      );
      store.save(scope, pending, legacy.generation);
      store.close();
      store = AttributeFormRecoveryStore.open(path);
      expect(
        store.load(scope)!.form.toWire().toText(),
        pending.toWire().toText(),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
