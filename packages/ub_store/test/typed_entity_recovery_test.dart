@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope({
  String? client,
  RecordId? name,
  RecordId? classification,
  int? index,
}) => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  entityClientRef: client,
  entityNameRecord: name,
  entityClassificationRecord: classification,
  entityOperationIndex: index,
);
UnfinishedEntityForm input(EditorFormScope s, {bool empty = false}) {
  final world = WorldId.generate();
  return UnfinishedEntityForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef:
        s.entityClientRef ??
        s.entityNameRecord?.value ??
        s.entityClassificationRecord?.value ??
        '\ufeffCreation',
    name: '\ufeffName\r\n\u0000😀',
    classification: '',
    worldRole: '\ufeffRole',
    rationale: '\ufeffReason',
    draftVersion: maxU64,
    expectedRecordVersion: RecordVersionId.generate(),
    worlds: empty ? [] : [world, world],
    nameDetails: empty
        ? const EntityNameForm()
        : const EntityNameForm(
            language: '\ufeffen',
            community: '',
            role: '\ufeffRole',
            validity: UnknownValidity(),
            temporalValidity: TemporalValidityInput(
              kind: 'unfinished',
              calendar: '\ufeffCalendar',
              start: TemporalBoundInput(value: '\ufeffTime\r\n\u0000'),
            ),
          ),
    associations: empty
        ? []
        : const [
            EntityAssociationForm(
              world: '\ufeffWorld',
              role: '\ufeffRole',
              originalOrdinal: 3,
              validity: UnknownValidity(),
              temporalValidity: TemporalValidityInput(
                kind: 'unfinished',
                start: TemporalBoundInput(
                  amount: QualifierInput(kind: 'text', value: '\ufeffAmount'),
                ),
              ),
              qualifiers: [
                QualifierInput(
                  key: '\ufeffKey',
                  kind: 'sequence',
                  originalKey: '',
                  children: [
                    QualifierInput(
                      kind: 'text',
                      value: '\ufeffChild\r\n\u0000',
                    ),
                    QualifierInput(),
                  ],
                  lower: QualifierInput(value: ''),
                  upperInclusive: 'unfinished',
                ),
              ],
            ),
            EntityAssociationForm(world: '', role: '', qualifiers: []),
            EntityAssociationForm(world: '', role: ''),
          ],
  );
}

void main() {
  test('typed entity recovery preserves nested exact inputs, retry semantics and owned row cleanup', () {
    final root = Directory('/tmp').createTempSync('ub-typed-entity-');
    final path = '${root.path}/entity.sqlite', s = scope(client: '\ufeffDraft');
    final f = input(s), empty = input(s, empty: true);
    var store = EntityFormRecoveryStore.open(path);
    try {
      store.save(s, f, BigInt.zero);
      store.close();
      store = EntityFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), f.toWire().toText());
      expect(store.save(s, f, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(s, empty, BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      store.save(s, empty, BigInt.one);
      store.close();
      store = EntityFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), empty.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(entity_form)').map((r) => r['name']),
          isNot(contains('name_input')),
        );
        for (final r in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name!='entity_form'",
        )) {
          expect(
            db.select('SELECT count(*) n FROM "${r['name']}"').single['n'],
            0,
            reason: r['name'] as String,
          );
        }
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  for (var version = 1; version <= 8; version++) {}
}
