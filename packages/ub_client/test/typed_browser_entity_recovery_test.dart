@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_entity_recovery.dart';
import 'package:ub_client/src/browser_input_fields.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _StoredRow._(JSObject _) implements JSObject {
  external String? get validity;
  external JSObject? get validityFields;
}

const tables = ['entity_form', 'entity_form_world', 'entity_form_association'];
List<JSAny> key(EditorFormScope s) {
  final target = s.entityNameRecord ?? s.entityClassificationRecord;
  final editor = target == null
      ? s.entityClientRef ?? ''
      : '${s.entityNameRecord == null ? 'classification' : 'name'}:${target.value}${s.entityOperationIndex == null ? '' : ':edit:${s.entityOperationIndex}'}';
  return [
    s.instance.value.toJS,
    s.profile.value.toJS,
    s.universe.value.toJS,
    s.continuity.value.toJS,
    s.representedContext!.value.toJS,
    editor.toJS,
  ];
}

Future<web.IDBDatabase> openDatabase(String name, [int? version]) async {
  final done = Completer<web.IDBDatabase>(),
      request = version == null
          ? web.window.indexedDB.open(name)
          : web.window.indexedDB.open(name, version);
  request.onupgradeneeded = ((web.Event _) {
    for (final table in tables) {
      (request.result as web.IDBDatabase).createObjectStore(table);
    }
  }).toJS;
  request.onsuccess = ((web.Event _) => done.complete(
    request.result as web.IDBDatabase,
  )).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Fixture failed'),
  )).toJS;
  return done.future;
}

Future<void> seed(
  String name,
  List<(EditorFormScope, UnfinishedEntityForm)> forms,
  int failure,
) async {
  final db = await openDatabase(name, 1);
  try {
    final done = Completer<void>(),
        tx = db.transaction(
          tables.map((t) => t.toJS).toList().toJS,
          'readwrite',
        );
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      StateError('Fixture save failed'),
    )).toJS;
    for (final (s, f) in forms) {
      tx
          .objectStore(tables[0])
          .put(
            {
              'generation': '9007199254740993',
              'baseRevision': f.baseRevision.value,
              'representedContext': f.representedContext.value,
              'clientRef': f.clientRef,
              'name': f.name,
              'classification': f.classification,
              'worldRole': f.worldRole,
              'rationale': f.rationale,
              'associationsPresent': f.associations != null,
              'draftVersion': f.draftVersion?.toString(),
              'expectedRecordVersion': f.expectedRecordVersion?.value,
              'namePresent': f.nameDetails != null,
              'language': f.nameDetails?.language,
              'community': f.nameDetails?.community,
              'role': f.nameDetails?.role,
              'validity': failure == 1 && f == forms.last.$2
                  ? '{unfinished'
                  : f.nameDetails?.validity?.toWire().toText(),
              'temporal': f.nameDetails?.temporalValidity == null
                  ? null
                  : encodeBrowserInput(
                      f.nameDetails!.temporalValidity!.toWire(),
                    ),
            }.jsify()!,
            key(s).toJS,
          );
      for (var i = 0; i < f.worlds.length; i++) {
        tx
            .objectStore(tables[1])
            .put(
              {'ordinal': i, 'value': f.worlds[i].value}.jsify()!,
              [...key(s), i.toJS].toJS,
            );
      }
      final associations = f.associations ?? <EntityAssociationForm>[];
      for (var i = 0; i < associations.length; i++) {
        final a = associations[i];
        tx
            .objectStore(tables[2])
            .put(
              {
                'ordinal': i,
                'world': a.world,
                'role': a.role,
                'originalOrdinal': a.originalOrdinal,
                'validity': failure == 2 && f == forms.last.$2 && i == 0
                    ? '{unfinished'
                    : a.validity?.toWire().toText(),
                'temporal': a.temporalValidity == null
                    ? null
                    : encodeBrowserInput(a.temporalValidity!.toWire()),
                'qualifiers': a.qualifiers == null
                    ? null
                    : encodeBrowserInput(
                        CanonicalArray(a.qualifiers!.map((q) => q.toWire())),
                      ),
              }.jsify()!,
              [...key(s), i.toJS].toJS,
            );
      }
    }
    await done.future;
  } finally {
    db.close();
  }
}

Future<_StoredRow> _read(web.IDBDatabase db, String table, JSAny rowKey) async {
  final done = Completer<_StoredRow>(),
      tx = db.transaction(table.toJS, 'readonly'),
      request = tx.objectStore(table).get(rowKey);
  tx.oncomplete = ((web.Event _) => done.complete(
    request.result as _StoredRow,
  )).toJS;
  tx.onabort = ((web.Event _) => done.completeError(
    StateError('Read failed'),
  )).toJS;
  return done.future;
}

Future<void> cleanup(String name) async {
  final done = Completer<void>(),
      request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Cleanup failed'),
  )).toJS;
  await done.future;
}

void main() {
  for (final failure in [0, 1, 2]) {
    test(
      'browser entity upgrade ${failure == 0 ? 'preserves creation and publication edit slots' : 'rolls back malformed ${failure == 1 ? 'name' : 'association'} validity'}',
      () async {
        final name = 'ub-entity-typed-${OperationId.generate().value}',
            record = RecordId.generate(),
            world = WorldId.generate(),
            calendar = CalendarId.generate();
        final scopes = [
          for (var i = 0; i < 4; i++)
            EditorFormScope(
              instance: OperationId.generate(),
              profile: ProfileId.generate(),
              universe: UniverseId.generate(),
              continuity: ContinuityId.generate(),
              representedContext: RecordId.generate(),
              entityClientRef: i == 1 ? '\ufeffDraft' : null,
              entityNameRecord: i == 2 ? record : null,
              entityClassificationRecord: i == 3 ? record : null,
              entityOperationIndex: i == 3 ? 12 : null,
            ),
        ];
        final validity = InstantValidity(
          DurationTime(
            calendar,
            SequenceValue([
              const RationalValue('900719925474099312345', '7'),
              TextValue('\ufeffAmount\r\n\u0000😀'),
            ]),
          ),
        );
        final forms = [
          for (final s in scopes)
            (
              s,
              UnfinishedEntityForm(
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
                rationale: '',
                worlds: [world, world],
                draftVersion: (BigInt.one << 64) - BigInt.one,
                expectedRecordVersion: RecordVersionId.generate(),
                nameDetails: EntityNameForm(
                  language: '',
                  community: '\ufeffCommunity',
                  role: null,
                  validity: validity,
                  temporalValidity: const TemporalValidityInput(
                    kind: 'unfinished',
                    start: TemporalBoundInput(value: '\ufeffPending'),
                  ),
                ),
                associations: [
                  EntityAssociationForm(
                    world: '\ufeffWorld',
                    role: '\ufeffRole',
                    originalOrdinal: 2,
                    validity: validity,
                    qualifiers: const [
                      QualifierInput(
                        kind: 'sequence',
                        originalKey: '',
                        children: [
                          QualifierInput(value: '\ufeffChild'),
                          QualifierInput(),
                        ],
                      ),
                    ],
                  ),
                  const EntityAssociationForm(
                    world: '',
                    role: '',
                    qualifiers: [],
                  ),
                  const EntityAssociationForm(world: '', role: ''),
                ],
              ),
            ),
        ];
        await seed(name, forms, failure);
        try {
          if (failure != 0) {
            await expectLater(
              BrowserEntityFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, tables[0], key(s).toJS);
                expect(
                  row.validity,
                  failure == 1 && f == forms.last.$2
                      ? '{unfinished'
                      : f.nameDetails!.validity!.toWire().toText(),
                );
                expect(row.validityFields, isNull);
                final association = await _read(
                  db,
                  tables[2],
                  [...key(s), 0.toJS].toJS,
                );
                expect(
                  association.validity,
                  failure == 2 && f == forms.last.$2
                      ? '{unfinished'
                      : validity.toWire().toText(),
                );
                expect(association.validityFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserEntityFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                final empty = UnfinishedEntityForm(
                  baseRevision: f.baseRevision,
                  representedContext: f.representedContext,
                  clientRef: f.clientRef,
                  name: '',
                  classification: '',
                  worldRole: '',
                  rationale: '',
                  nameDetails: const EntityNameForm(),
                  associations: [],
                );
                await store.save(s, empty, saved.generation);
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  empty.toWire().toText(),
                );
                await store.save(s, f, saved.generation + BigInt.one);
              }
              store.close();
              store = await BrowserEntityFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.toWire().toText(),
                );
              }
              final db = await openDatabase(name);
              try {
                expect(db.version, 2);
                for (final (s, _) in forms) {
                  final row = await _read(db, tables[0], key(s).toJS),
                      association = await _read(
                        db,
                        tables[2],
                        [...key(s), 0.toJS].toJS,
                      );
                  expect(row.validity, isNull);
                  expect(row.validityFields, isNotNull);
                  expect(association.validity, isNull);
                  expect(association.validityFields, isNotNull);
                }
              } finally {
                db.close();
              }
            } finally {
              store.close();
            }
          }
        } finally {
          await cleanup(name);
        }
      },
    );
  }
}
