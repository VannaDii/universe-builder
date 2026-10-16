@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test(
    'entity associations retain pending fields across saves and reopening',
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
      var store = EntityFormRecoveryStore.open(path);
      try {
        UnfinishedEntityForm form(List<EntityAssociationForm> rows) =>
            UnfinishedEntityForm(
              baseRevision: revision,
              representedContext: scope.representedContext!,
              clientRef: 'draft-person',
              name: '人物',
              nameDetails: const EntityNameForm(
                language: 'en',
                community: '記憶 😀',
                role: '',
                temporalValidity: TemporalValidityInput(
                  calendar: 'unfinished 😀',
                  kind: 'instant',
                  start: TemporalBoundInput(value: 'unfinished time'),
                ),
              ),
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
            qualifiers: [
              QualifierInput(key: '', kind: 'text', value: '記憶 😀\nunfinished'),
              QualifierInput(
                key: 'target',
                kind: 'entity_ref',
                universe: 'unfinished universe 😀',
                value: 'unfinished record',
              ),
              QualifierInput(
                key: 'entry',
                kind: 'enum',
                definition: 'unfinished definition 😀',
                value: '記憶',
              ),
              QualifierInput(
                key: 'list',
                kind: 'sequence',
                children: [
                  QualifierInput(
                    kind: 'structured',
                    definition: 'unfinished 😀',
                    children: [
                      QualifierInput(
                        key: '',
                        kind: 'text',
                        value: 'nested 記憶 😀',
                      ),
                    ],
                  ),
                ],
              ),
              QualifierInput(
                key: 'range',
                kind: 'range',
                lower: QualifierInput(kind: 'decimal', value: 'unfinished 😀'),
                upperInclusive: 'false',
              ),
              QualifierInput(
                key: 'time',
                kind: 'temporal',
                temporal: TemporalValidityInput(
                  kind: 'instant_relative',
                  calendar: 'unfinished 😀',
                  relation: 'after',
                  targetRecord: 'unfinished record',
                  start: TemporalBoundInput(uncertainty: '記憶 😀'),
                ),
              ),
              QualifierInput(
                key: 'space',
                kind: 'spatial_distance',
                value: 'unfinished target',
                universe: 'unfinished universe',
                unit: 'unfinished unit',
                lower: QualifierInput(kind: 'decimal', value: 'unfinished 😀'),
              ),
              QualifierInput(
                key: 'amount',
                kind: 'rational',
                value: '1',
                denominator: '',
              ),
            ],
            validity: UnknownValidity(),
            temporalValidity: TemporalValidityInput(
              calendar: 'unfinished',
              kind: 'instant_relative',
              relation: 'after',
              targetUniverse: 'unfinished universe',
              targetRecord: 'unfinished record',
              start: TemporalBoundInput(
                value: 'unknown text',
                uncertaintyKind: 'typed',
                amount: QualifierInput(
                  kind: 'sequence',
                  children: [
                    QualifierInput(kind: 'decimal', value: 'unfinished 記憶 😀'),
                  ],
                ),
              ),
            ),
            originalOrdinal: 1,
          ),
          const EntityAssociationForm(
            world: '',
            role: '',
            temporalValidity: TemporalValidityInput(
              kind: 'instant_duration',
              start: TemporalBoundInput(
                uncertaintyKind: 'text',
                uncertainty: '記憶 😀\nunfinished amount',
              ),
            ),
          ),
        ]);
        store.save(scope, pending, BigInt.zero);
        store.close();
        store = EntityFormRecoveryStore.open(path);
        expect(
          store.load(scope)!.form.toWire().toText(),
          pending.toWire().toText(),
        );
        store.save(scope, form([]), BigInt.one);
        expect(store.load(scope)!.form.associations, isEmpty);
        store.save(scope, pending, BigInt.two);
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
      db.execute('PRAGMA user_version=99');
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
