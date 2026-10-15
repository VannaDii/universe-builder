@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

import 'entity_legacy_fixture.dart';

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
  test('version eight preserves creation, draft, name, classification and operation edit slots', () {
    final root = Directory('/tmp').createTempSync('ub-entity-slots-');
    final path = '${root.path}/entity.sqlite';
    final scopes = [
      scope(),
      scope(client: 'name:rec_literal'),
      scope(name: RecordId.generate()),
      scope(classification: RecordId.generate(), index: 0),
      scope(name: RecordId.generate(), index: 12),
    ];
    final entries = [for (final s in scopes) (s, input(s), maxU64)];
    writeLegacyEntityForms(path, 8, entries);
    final store = EntityFormRecoveryStore.open(path);
    try {
      for (final (s, f, g) in entries) {
        expect(store.load(s)!.generation, g);
        expect(store.load(s)!.form.toWire().toText(), f.toWire().toText());
        expect(
          () => store.save(s, f, g),
          throwsA(
            isA<EditorRecoveryException>().having(
              (e) => e.failure,
              'failure',
              EditorRecoveryFailure.generationExhausted,
            ),
          ),
        );
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  for (var version = 1; version <= 8; version++) {
    test(
      'version $version rolls back all migrated rows on invalid generation',
      () {
        final root = Directory('/tmp').createTempSync('ub-entity-rollback-');
        final path = '${root.path}/entity.sqlite', a = scope(), b = scope();
        writeLegacyEntityForms(path, version, [
          (a, input(a), BigInt.one),
          (b, input(b), maxU64 + BigInt.one),
        ]);
        try {
          expect(
            () => EntityFormRecoveryStore.open(path),
            throwsA(isA<EditorRecoveryException>()),
          );
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(
              db.select('PRAGMA user_version').single.values.single,
              version,
            );
            expect(
              db.select('SELECT count(*) n FROM entity_form').single['n'],
              2,
            );
            expect(
              db
                  .select("SELECT name FROM sqlite_master WHERE type='table'")
                  .length,
              version >= 3 ? 3 : 2,
            );
            if (version >= 7) {
              expect(
                db
                    .select('SELECT name_input FROM entity_form')
                    .first['name_input'],
                isNotNull,
              );
            }
          } finally {
            db.close();
          }
        } finally {
          root.deleteSync(recursive: true);
        }
      },
    );
  }
  test('malformed legacy name input leaves version eight intact', () {
    final root = Directory('/tmp').createTempSync('ub-entity-malformed-');
    final path = '${root.path}/entity.sqlite', s = scope();
    writeLegacyEntityForms(path, 8, [(s, input(s), BigInt.one)]);
    final db = sqlite3.open(path);
    db.execute("UPDATE entity_form SET name_input='{unfinished'");
    db.close();
    try {
      expect(
        () => EntityFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final old = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(old.select('PRAGMA user_version').single.values.single, 8);
        expect(
          old.select('SELECT name_input FROM entity_form').single['name_input'],
          '{unfinished',
        );
      } finally {
        old.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
