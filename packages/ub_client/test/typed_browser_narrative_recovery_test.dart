@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_work_recovery.dart';
import 'package:ub_client/browser_scene_recovery.dart';
import 'package:ub_client/src/browser_input_fields.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _StoredRow._(JSObject _) implements JSObject {
  external String? get original;
  external String? get associationOriginal;
  external JSObject? get associationOriginalFields;
  external JSObject? get originalFields;
}

List<JSAny> key(EditorFormScope s) => [
  s.instance.value.toJS,
  s.profile.value.toJS,
  s.universe.value.toJS,
  s.continuity.value.toJS,
  s.representedContext!.value.toJS,
  (s.typeClientRef ?? '').toJS,
];
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
);
RecordRef ref() =>
    RecordRef(record: RecordId.generate(), universe: UniverseId.generate());
TemporalExpression time() => ApproximateTime(
  CalendarId.generate(),
  '\ufeffCoordinate',
  SequenceValue([
    const RationalValue('900719925474099312345', '007'),
    TextValue('\ufeffAmount\r\n\u0000😀'),
  ]),
);
Future<web.IDBDatabase> openDatabase(
  String name,
  String table, [
  int? version,
]) async {
  final done = Completer<web.IDBDatabase>(),
      request = version == null
          ? web.window.indexedDB.open(name)
          : web.window.indexedDB.open(name, version);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore(table);
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
  String table,
  List<(EditorFormScope, Map<String, Object?>)> rows,
) async {
  final db = await openDatabase(name, table, 1);
  try {
    final done = Completer<void>(),
        tx = db.transaction(table.toJS, 'readwrite');
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      StateError('Seed failed'),
    )).toJS;
    for (final (s, row) in rows) {
      tx.objectStore(table).put(row.jsify()!, key(s).toJS);
    }
    await done.future;
  } finally {
    db.close();
  }
}

Future<_StoredRow> _read(
  web.IDBDatabase db,
  String table,
  EditorFormScope s,
) async {
  final done = Completer<_StoredRow>(),
      tx = db.transaction(table.toJS, 'readonly'),
      request = tx.objectStore(table).get(key(s).toJS);
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

WorldAssociation association() => WorldAssociation(
  world: WorldId.generate(),
  role: '\ufeffSetting',
  validity: InstantValidity(time()),
  qualifiers: {
    '\ufeffKey': SequenceValue([
      const IntegerValue('900719925474099312345'),
      TextValue('\ufeffValue\r\n\u0000😀'),
    ]),
  },
);
void main() {
  for (final failure in [0, 1, 2]) {
    final malformed = failure != 0;
    test(
      'browser work originals ${failure == 2 ? 'association ' : ''}${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-work-typed-${OperationId.generate().value}',
            table = 'work_form';
        final forms = [
          for (var i = 0; i < 4; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedWorkForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                kind: 'unfinished',
                title: '\ufeffTitle\r\n\u0000😀',
                labels: const [
                  PropertyLabelInput(language: '', text: '\ufeffLabel'),
                  PropertyLabelInput(),
                ],
                sources: const [
                  ExpressionReferenceInput(record: '\ufeffSource'),
                  ExpressionReferenceInput(),
                ],
                versions: const ['', '\ufeffVersion', '\ufeffVersion'],
                associations: [
                  WorkAssociationInput(
                    world: '\ufeffWorld',
                    role: '\ufeffRole',
                    originalOrdinal: 2,
                    qualifiers: const [
                      QualifierInput(),
                      QualifierInput(value: '\ufeffQualifier'),
                    ],
                  ),
                ],
                associationTarget: const ExpressionReferenceInput(
                  record: '\ufeffTarget',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                associationOriginal: i == 0 ? null : association(),
                original: i == 0
                    ? null
                    : WorkRecord(
                        kind: WorkKind.values.first,
                        title: '\ufeffOriginal',
                        labels: {'': '', '\ufeffen': '\ufeffName\r\n\u0000😀'},
                        sourceRefs: [repeated, repeated],
                        versions: [repeated.record, repeated.record],
                        worldAssociations: [association(), association()],
                      ),
              );
              return (s, f);
            })(),
        ];
        final rows = [
          for (final (s, f) in forms)
            (
              s,
              <String, Object?>{
                'generation': '9007199254740993',
                'baseRevision': f.baseRevision.value,
                'representedContext': f.representedContext.value,
                'clientRef': f.clientRef,
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'original': failure == 1 && failure == 1 && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'kind': f.kind,
                'title': f.title,
                'labels': encodeBrowserInput(
                  CanonicalArray(f.labels.map((v) => v.toWire())),
                ),
                'sources': encodeBrowserInput(
                  CanonicalArray(f.sources.map((v) => v.toWire())),
                ),
                'versions': f.versions,
                'associations': encodeBrowserInput(
                  CanonicalArray(f.associations.map((v) => v.toWire())),
                ),
                'associationTarget': encodeBrowserInput(
                  f.associationTarget!.toWire(),
                ),
                'expectedRecordVersion': f.expectedRecordVersion!.value,
                'associationOriginal': failure == 2 && f == forms.last.$2
                    ? '{unfinished'
                    : f.associationOriginal?.toWire().toText(),
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserWorkFormRecoveryStore.open(databaseName: database),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(database, table);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, table, s);
                expect(
                  row.original,
                  failure == 1 && f == forms.last.$2
                      ? '{unfinished'
                      : f.original?.toWire().toText(),
                );
                expect(row.originalFields, isNull);
                expect(
                  row.associationOriginal,
                  failure == 2 && f == forms.last.$2
                      ? '{unfinished'
                      : f.associationOriginal?.toWire().toText(),
                );
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserWorkFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(
                  s,
                  f.copyWith(rationale: '\ufeffReplacement'),
                  saved.generation,
                );
              }
              store.close();
              store = await BrowserWorkFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.copyWith(rationale: '\ufeffReplacement').toWire().toText(),
                );
              }
              final db = await openDatabase(database, table);
              try {
                expect(db.version, 2);
                for (final (s, f) in forms) {
                  final row = await _read(db, table, s);
                  expect(row.original, isNull);
                  expect(
                    row.originalFields,
                    f.original == null ? isNull : isNotNull,
                  );
                  if (table == 'work_form') {
                    expect(row.associationOriginal, isNull);
                  }
                  if (table == 'scene_form' && row.originalFields != null) {
                    final fields = Map.fromEntries(
                      (decodeBrowserInput(
                        row.originalFields!,
                      ) as CanonicalObject).fields,
                    );
                    expect(
                      fields['narrativePosition'],
                      anyOf(isA<CanonicalString>(), isA<CanonicalNull>()),
                    );
                  }
                }
              } finally {
                db.close();
              }
            } finally {
              store.close();
            }
          }
        } finally {
          await cleanup(database);
        }
      },
    );
    if (failure != 2) {
      test(
        'browser scene originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
        () async {
          final database = 'ub-scene-typed-${OperationId.generate().value}',
              table = 'scene_form';
          final forms = [
            for (var i = 0; i < 4; i++)
              (() {
                final s = scope(), repeated = ref();
                final f = UnfinishedSceneForm(
                  baseRevision: RevisionId.generate(),
                  representedContext: s.representedContext!,
                  clientRef: '\ufeffInput',
                  rationale: '\ufeffReason\r\n\u0000😀',
                  draftVersion: (BigInt.one << 64) - BigInt.one,
                  sceneId: '\ufeffScene\r\n\u0000😀',
                  edition: const ExpressionReferenceInput(
                    record: '\ufeffEdition',
                  ),
                  editionVersion: RecordVersionId.generate().value,
                  viewpointEnabled: false,
                  viewpoint: const ExpressionReferenceInput(
                    record: '\ufeffDisabled',
                  ),
                  narrationEnabled: false,
                  narration: const ExpressionReferenceInput(
                    record: '\ufeffNarration',
                  ),
                  positionEnabled: false,
                  position: '\ufeffPending',
                  disclosed: const [
                    ExpressionReferenceInput(),
                    ExpressionReferenceInput(record: '\ufeffClaim'),
                    ExpressionReferenceInput(record: '\ufeffClaim'),
                  ],
                  depicted: const [ExpressionReferenceInput()],
                  associations: [
                    WorkAssociationInput(
                      world: '\ufeffWorld',
                      role: '\ufeffRole',
                    ),
                  ],
                  correctionTarget: const ExpressionReferenceInput(
                    record: '\ufeffCorrection',
                  ),
                  expectedRecordVersion: RecordVersionId.generate(),
                  original: i == 0
                      ? null
                      : SceneRecord(
                          workVersion: VersionRef(
                            record: repeated.record,
                            version: RecordVersionId.generate(),
                            universe: repeated.universe,
                          ),
                          sceneId: '\ufeffOriginal',
                          disclosedRecords: [repeated, repeated],
                          viewpoint: i == 1 ? null : ref(),
                          narrationFrame: i == 1 ? null : ref(),
                          narrativePosition: i == 1
                              ? (BigInt.one << 64) - BigInt.one
                              : i == 2
                              ? null
                              : BigInt.parse('9007199254740993'),
                          depictedEvents: [ref(), ref()],
                          worldAssociations: [association(), association()],
                        ),
                );
                return (s, f);
              })(),
          ];
          final rows = [
            for (final (s, f) in forms)
              (
                s,
                <String, Object?>{
                  'generation': '9007199254740993',
                  'baseRevision': f.baseRevision.value,
                  'representedContext': f.representedContext.value,
                  'clientRef': f.clientRef,
                  'rationale': f.rationale,
                  'draftVersion': f.draftVersion?.toString(),
                  'original': malformed && f == forms.last.$2
                      ? '{unfinished'
                      : f.original?.toWire().toText(),
                  'sceneId': f.sceneId,
                  'edition': encodeBrowserInput(f.edition.toWire()),
                  'editionVersion': f.editionVersion,
                  'viewpointEnabled': f.viewpointEnabled,
                  'viewpoint': encodeBrowserInput(f.viewpoint.toWire()),
                  'narrationEnabled': f.narrationEnabled,
                  'narration': encodeBrowserInput(f.narration.toWire()),
                  'positionEnabled': f.positionEnabled,
                  'position': f.position,
                  'disclosed': encodeBrowserInput(
                    CanonicalArray(f.disclosed.map((v) => v.toWire())),
                  ),
                  'depicted': encodeBrowserInput(
                    CanonicalArray(f.depicted.map((v) => v.toWire())),
                  ),
                  'associations': encodeBrowserInput(
                    CanonicalArray(f.associations.map((v) => v.toWire())),
                  ),
                  'correctionTarget': encodeBrowserInput(
                    f.correctionTarget!.toWire(),
                  ),
                  'expectedRecordVersion': f.expectedRecordVersion!.value,
                },
              ),
          ];
          await seed(database, table, rows);
          try {
            if (malformed) {
              await expectLater(
                BrowserSceneFormRecoveryStore.open(databaseName: database),
                throwsA(isA<EditorRecoveryException>()),
              );
              final db = await openDatabase(database, table);
              try {
                expect(db.version, 1);
                for (final (s, f) in forms) {
                  final row = await _read(db, table, s);
                  expect(
                    row.original,
                    f == forms.last.$2
                        ? '{unfinished'
                        : f.original?.toWire().toText(),
                  );
                  expect(row.originalFields, isNull);
                }
              } finally {
                db.close();
              }
            } else {
              var store = await BrowserSceneFormRecoveryStore.open(
                databaseName: database,
              );
              try {
                for (final (s, f) in forms) {
                  final saved = (await store.load(s))!;
                  expect(saved.generation, BigInt.parse('9007199254740993'));
                  expect(saved.form.toWire().toText(), f.toWire().toText());
                  await store.save(
                    s,
                    f.copyWith(rationale: '\ufeffReplacement'),
                    saved.generation,
                  );
                }
                store.close();
                store = await BrowserSceneFormRecoveryStore.open(
                  databaseName: database,
                );
                for (final (s, f) in forms) {
                  expect(
                    (await store.load(s))!.form.toWire().toText(),
                    f
                        .copyWith(rationale: '\ufeffReplacement')
                        .toWire()
                        .toText(),
                  );
                }
                final db = await openDatabase(database, table);
                try {
                  expect(db.version, 2);
                  for (final (s, f) in forms) {
                    final row = await _read(db, table, s);
                    expect(row.original, isNull);
                    expect(
                      row.originalFields,
                      f.original == null ? isNull : isNotNull,
                    );
                    if (table == 'work_form') {
                      expect(row.associationOriginal, isNull);
                    }
                    if (table == 'scene_form' && row.originalFields != null) {
                      final fields = Map.fromEntries(
                        (decodeBrowserInput(
                          row.originalFields!,
                        ) as CanonicalObject).fields,
                      );
                      expect(
                        fields['narrativePosition'],
                        anyOf(isA<CanonicalString>(), isA<CanonicalNull>()),
                      );
                    }
                  }
                } finally {
                  db.close();
                }
              } finally {
                store.close();
              }
            }
          } finally {
            await cleanup(database);
          }
        },
      );
    }
  }
}
