@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  for (final schemaVersion in [1, 2, 3]) {
    test(
      'legacy v$schemaVersion attribute recovery retains pending fields with creation input',
      () {
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
          'ALTER TABLE attribute_form DROP COLUMN roles_input; '
          '${schemaVersion < 3 ? 'ALTER TABLE attribute_form DROP COLUMN creation_input; ' : ''}'
          '${schemaVersion == 1 ? 'ALTER TABLE attribute_form DROP COLUMN evidence_input; ' : ''}'
          'PRAGMA user_version=$schemaVersion',
        );
        db.close();
        store = AttributeFormRecoveryStore.open(path);
        try {
          final legacy = store.load(scope)!;
          expect(legacy.form.toWire().toText(), initial.toWire().toText());
          expect(legacy.form.evidenceInput, isNull);
          expect(legacy.form.roles, isNull);
          final pending = UnfinishedAttributeForm(
            baseRevision: initial.baseRevision,
            representedContext: initial.representedContext,
            clientRef: initial.clientRef,
            draftVersion: initial.draftVersion,
            value: initial.value,
            roles: const [
              PropositionRoleInput(
                role: 'role 記憶 😀',
                record: 'unfinished record',
                universe: 'unfinished universe',
              ),
              PropositionRoleInput(
                role: 'role 記憶 😀',
                record: 'unfinished record',
              ),
            ],
            creationInput: AttributeCreationInput(
              relationship: true,
              subject: VersionRef(
                universe: scope.universe,
                record: RecordId.generate(),
                version: RecordVersionId.generate(),
              ),
              operationRef: RecordId.generate().value,
              propertyRecord: 'unfinished property 記憶 😀',
              propertyUniverse: 'unfinished universe',
            ),
            evidenceInput: const AttributeEvidenceInput(
              basis: EvidenceBasisInput(
                kind: 'source_anchor',
                note: 'unfinished account 記憶 😀',
                anchorRecord: 'unfinished anchor',
                anchorUniverse: 'unfinished universe',
                verified: true,
              ),
              attributeMode: AttributeMode.initialValue,
              scope: ScopeInput(
                applicability: 'worlds',
                worlds: [
                  'unfinished world 記憶 😀',
                  '',
                  'unfinished world 記憶 😀',
                ],
                contextRecord: 'unfinished context',
                contextUniverse: 'unfinished universe',
                hasRealm: true,
                realmRecord: 'unfinished realm',
                realmUniverse: 'unfinished realm universe',
              ),
              alternatives: [
                QualifierInput(kind: 'retain', originalKey: '1'),
                QualifierInput(
                  kind: 'sequence',
                  children: [
                    QualifierInput(kind: 'decimal', value: 'unfinished 記憶 😀'),
                  ],
                ),
              ],
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
      },
    );
  }
}
