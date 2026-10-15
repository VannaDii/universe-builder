@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_type_recovery.dart';
import 'package:ub_client/browser_pack_recovery.dart';
import 'package:ub_client/src/browser_input_fields.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _StoredRow._(JSObject _) implements JSObject {
  external String? get original;
  external JSObject? get originalFields;
  external String? get revisionTarget;
  external JSObject? get revisionTargetFields;
}

EditorFormScope scope(int i) => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: i == 0 ? null : '\ufeffDraft',
);
List<JSAny> key(EditorFormScope s) => [
  s.instance.value.toJS,
  s.profile.value.toJS,
  s.universe.value.toJS,
  s.continuity.value.toJS,
  s.representedContext!.value.toJS,
  (s.typeClientRef ?? '').toJS,
];
Future<web.IDBDatabase> openDatabase(
  String name,
  List<String> tables, [
  int? version,
]) async {
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
  List<String> tables,
  List<
    (EditorFormScope, Map<String, Object?>, List<List<Map<String, Object?>>>)
  >
  rows,
) async {
  final db = await openDatabase(name, tables, 1);
  try {
    final done = Completer<void>(),
        tx = db.transaction(
          tables.map((t) => t.toJS).toList().toJS,
          'readwrite',
        );
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      StateError('Seed failed'),
    )).toJS;
    for (final (s, row, children) in rows) {
      tx.objectStore(tables.first).put(row.jsify()!, key(s).toJS);
      for (var table = 0; table < children.length; table++) {
        for (var i = 0; i < children[table].length; i++) {
          tx
              .objectStore(tables[table + 1])
              .put(
                {'ordinal': i, ...children[table][i]}.jsify()!,
                [...key(s), i.toJS].toJS,
              );
        }
      }
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

void main() {
  for (final failure in [0, 1, 2]) {
    test(
      'type upgrade ${failure == 0 ? 'preserves original definitions, revision targets and child rows' : 'rolls back malformed ${failure == 1 ? 'original' : 'target'}'}',
      () async {
        final name = 'ub-type-fields-${OperationId.generate().value}',
            tables = ['type_form', 'type_form_world', 'type_form_label'],
            world = WorldId.generate();
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(i);
              final f = UnfinishedTypeForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: s.typeClientRef ?? '\ufeffCreation',
                namespace: '\ufeffNamespace',
                key: '\ufeffKey',
                name: '\ufeffName\r\n\u0000😀',
                parentChoice: 'unfinished',
                applicabilityChoice: 'unfinished',
                classificationExecutable: i == 0
                    ? null
                    : i == 1
                    ? false
                    : true,
                worlds: [world, world],
                rationale: '\ufeffReason',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                revisionTarget: i == 2
                    ? RecordRef(
                        record: RecordId.generate(),
                        universe: s.universe,
                      )
                    : null,
                expectedRecordVersion: RecordVersionId.generate(),
                parentResolution: '\ufeffUnfinished',
                labels: const [
                  PropertyLabelInput(language: '', text: '\ufeffLabel'),
                  PropertyLabelInput(),
                ],
                original: i == 0
                    ? null
                    : EntityTypeRecord(
                        namespace: '\ufeffOriginal',
                        key: '\ufeffKey',
                        name: '',
                        labels: {'': '', '\ufeffen': '\ufeffName\r\n\u0000😀'},
                        parent: i == 1 ? null : RecordId.generate(),
                        parentResolution: i == 1
                            ? ParentResolution.root
                            : ParentResolution.resolved,
                        applicability: WorldsApplicability([world, world]),
                        classificationExecutable: false,
                      ),
              );
              return (s, f);
            })(),
        ];
        await seed(name, tables, [
          for (final (s, f) in forms)
            (
              s,
              {
                'generation': '9007199254740993',
                'baseRevision': f.baseRevision.value,
                'representedContext': f.representedContext.value,
                'clientRef': f.clientRef,
                'namespace': f.namespace,
                'key': f.key,
                'name': f.name,
                'parentChoice': f.parentChoice,
                'applicabilityChoice': f.applicabilityChoice,
                'classificationExecutable': f.classificationExecutable,
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'expectedRecordVersion': f.expectedRecordVersion?.value,
                'parentResolution': f.parentResolution,
                'original': failure == 1 && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'revisionTarget': failure == 2 && f == forms.last.$2
                    ? '{unfinished'
                    : f.revisionTarget?.toCanonical().toText(),
              },
              [
                [
                  for (final w in f.worlds) {'value': w.value},
                ],
                [
                  for (final l in f.labels)
                    {'language': l.language, 'text': l.text},
                ],
              ],
            ),
        ]);
        try {
          if (failure != 0) {
            await expectLater(
              BrowserTypeFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name, tables);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, tables.first, s);
                expect(
                  row.original,
                  failure == 1 && f == forms.last.$2
                      ? '{unfinished'
                      : f.original?.toWire().toText(),
                );
                expect(row.originalFields, isNull);
                expect(
                  row.revisionTarget,
                  failure == 2 && f == forms.last.$2
                      ? '{unfinished'
                      : f.revisionTarget?.toCanonical().toText(),
                );
                expect(row.revisionTargetFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserTypeFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                expect(
                  saved.form.original?.toWire().toText(),
                  f.original?.toWire().toText(),
                );
                expect(saved.form.labels.length, f.labels.length);
                expect(
                  saved.form.expectedRecordVersion,
                  f.expectedRecordVersion,
                );
                await store.save(s, f, saved.generation);
              }
              store.close();
              store = await BrowserTypeFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.toWire().toText(),
                );
              }
              final db = await openDatabase(name, tables);
              try {
                expect(db.version, 2);
                for (final (s, f) in forms) {
                  final row = await _read(db, tables.first, s);
                  expect(row.original, isNull);
                  expect(row.revisionTarget, isNull);
                  expect(
                    row.originalFields,
                    f.original == null ? isNull : isNotNull,
                  );
                  expect(
                    row.revisionTargetFields,
                    f.revisionTarget == null ? isNull : isNotNull,
                  );
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
  for (final malformed in [false, true]) {
    test(
      'pack upgrade ${malformed ? 'rolls back malformed originals' : 'preserves dependencies, capabilities, members and exact versions'}',
      () async {
        final name = 'ub-pack-fields-${OperationId.generate().value}',
            tables = [
              'pack_form',
              'pack_dependency',
              'pack_capability',
              'pack_member',
            ];
        final forms = [
          for (var i = 0; i < 2; i++)
            (() {
              final s = scope(i), record = RecordId.generate();
              return (
                s,
                UnfinishedPackForm(
                  baseRevision: RevisionId.generate(),
                  representedContext: s.representedContext!,
                  clientRef: s.typeClientRef ?? '\ufeffCreation',
                  key: '\ufeffKey',
                  version: '\ufeffVersion\r\n\u0000😀',
                  dependencies: const [
                    PackDependencyInput(key: '\ufeffPack', version: ''),
                    PackDependencyInput(),
                    PackDependencyInput(
                      key: '\ufeffPack',
                      version: '\ufeffVersion',
                    ),
                  ],
                  capabilities: ['', '\ufeffCapability', '\ufeffCapability'],
                  records: [record.value, '', record.value],
                  revisionTarget: const ExpressionReferenceInput(
                    record: '\ufeffTarget',
                  ),
                  expectedRecordVersion: RecordVersionId.generate(),
                  draftVersion: (BigInt.one << 64) - BigInt.one,
                  rationale: '\ufeffReason',
                  original: i == 0
                      ? null
                      : DomainPackRecord(
                          key: '\ufeffOriginal',
                          version: '\ufeffExact',
                          dependencies: {
                            '': '',
                            '\ufeffDependency': '\ufeffVersion\r\n\u0000😀',
                          },
                          capabilities: [
                            '',
                            '\ufeffCapability',
                            '\ufeffCapability',
                          ],
                          records: [record, record],
                        ),
                ),
              );
            })(),
        ];
        await seed(name, tables, [
          for (final (s, f) in forms)
            (
              s,
              {
                'generation': '9007199254740993',
                'baseRevision': f.baseRevision.value,
                'representedContext': f.representedContext.value,
                'clientRef': f.clientRef,
                'key': f.key,
                'version': f.version,
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'revisionTarget': encodeBrowserInput(
                  f.revisionTarget!.toWire(),
                ),
                'expectedRecordVersion': f.expectedRecordVersion!.value,
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
              },
              [
                [
                  for (final d in f.dependencies)
                    {'key': d.key, 'version': d.version},
                ],
                [
                  for (final c in f.capabilities) {'value': c},
                ],
                [
                  for (final r in f.records) {'value': r},
                ],
              ],
            ),
        ]);
        try {
          if (malformed) {
            await expectLater(
              BrowserPackFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name, tables);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, tables.first, s);
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
            var store = await BrowserPackFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, f, saved.generation);
              }
              store.close();
              store = await BrowserPackFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.toWire().toText(),
                );
              }
              final db = await openDatabase(name, tables);
              try {
                expect(db.version, 2);
                for (final (s, f) in forms) {
                  final row = await _read(db, tables.first, s);
                  expect(row.original, isNull);
                  expect(
                    row.originalFields,
                    f.original == null ? isNull : isNotNull,
                  );
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
