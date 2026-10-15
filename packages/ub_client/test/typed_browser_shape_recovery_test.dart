@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_property_recovery.dart';
import 'package:ub_client/browser_relation_recovery.dart';
import 'package:ub_client/browser_value_definition_recovery.dart';
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
  for (final malformed in [false, true]) {
    test(
      'property upgrade ${malformed ? 'rolls back malformed originals' : 'preserves nested definitions, labels and ordered child input'}',
      () async {
        final database = 'ub-property-fields-${OperationId.generate().value}',
            tables = [
              'property_form',
              'property_form_subject',
              'property_form_label',
            ];
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(i), record = RecordId.generate();
              final f = UnfinishedPropertyForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: s.typeClientRef ?? '\ufeffCreation',
                namespace: '\ufeffNamespace',
                key: '\ufeffKey',
                labels: const [
                  PropertyLabelInput(
                    language: '',
                    text: '\ufeffLabel\r\n\u0000😀',
                  ),
                  PropertyLabelInput(),
                ],
                rationale: '\ufeffReason',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                revisionTarget: const ExpressionReferenceInput(
                  record: '\ufeffTarget',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                shape: ValueShapeInput(
                  kind: 'sequence',
                  item: ValueShapeInput(
                    kind: 'unfinished',
                    unit: '\ufeffDisabled',
                  ),
                ),
                subjectTypes: ['', '\ufeffType', '\ufeffType'],
                multiplicity: 'unfinished',
                persistence: 'unfinished',
                hasUnitDimension: false,
                unitDimension: '\ufeffDisabled',
                hasInverse: false,
                inverse: '\ufeffInverse',
                exclusive: i == 1,
                symmetric: i == 2,
                transitive: false,
                original: i == 0
                    ? null
                    : PropertyRecord(
                        namespace: '\ufeffOriginal',
                        key: '\ufeffKey',
                        labels: {'': '', '\ufeffen': '\ufeffName\r\n\u0000😀'},
                        subjectTypes: [record, record],
                        value: i == 1
                            ? SequenceShape(
                                SequenceShape(
                                  EnumShape(ValueDefinitionId.generate()),
                                ),
                              )
                            : SequenceShape(EntityRefShape([record, record])),
                        multiplicity: Multiplicity.multiple,
                        unitDimension: i == 1 ? null : '',
                        persistence: PersistenceSemantics.explicitInterval,
                        exclusive: false,
                        inverse: i == 1 ? null : '',
                        symmetric: true,
                        transitive: false,
                      ),
              );
              return (s, f);
            })(),
        ];
        await seed(database, tables, [
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
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'revisionTarget': encodeBrowserInput(
                  f.revisionTarget!.toWire(),
                ),
                'expectedRecordVersion': f.expectedRecordVersion!.value,
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'shape': encodeBrowserInput(f.shape.toWire()),
                'multiplicity': f.multiplicity,
                'persistence': f.persistence,
                'hasUnitDimension': f.hasUnitDimension,
                'unitDimension': f.unitDimension,
                'hasInverse': f.hasInverse,
                'inverse': f.inverse,
                'exclusive': f.exclusive,
                'symmetric': f.symmetric,
                'transitive': f.transitive,
              },
              [
                [
                  for (final v in f.subjectTypes) {'value': v},
                ],
                [
                  for (final l in f.labels)
                    {'language': l.language, 'text': l.text},
                ],
              ],
            ),
        ]);
        try {
          if (malformed) {
            await expectLater(
              BrowserPropertyFormRecoveryStore.open(databaseName: database),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(database, tables);
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
            var store = await BrowserPropertyFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, f, saved.generation);
              }
              store.close();
              store = await BrowserPropertyFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.toWire().toText(),
                );
              }
              final db = await openDatabase(database, tables);
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
          await cleanup(database);
        }
      },
    );
    test(
      'relation upgrade ${malformed ? 'rolls back malformed originals' : 'preserves nested definitions, labels and ordered child input'}',
      () async {
        final database = 'ub-relation-fields-${OperationId.generate().value}',
            tables = ['relation_form', 'relation_role', 'relation_label'];
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(i), record = RecordId.generate();
              final f = UnfinishedRelationForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: s.typeClientRef ?? '\ufeffCreation',
                namespace: '\ufeffNamespace',
                key: '\ufeffKey',
                labels: const [
                  PropertyLabelInput(
                    language: '',
                    text: '\ufeffLabel\r\n\u0000😀',
                  ),
                  PropertyLabelInput(),
                ],
                rationale: '\ufeffReason',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                revisionTarget: const ExpressionReferenceInput(
                  record: '\ufeffTarget',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                roles: [
                  RelationRoleInput(
                    name: '\ufeffRole',
                    participantTypes: ['', '\ufeffType', '\ufeffType'],
                    multiplicity: 'unfinished',
                    ordered: true,
                  ),
                  RelationRoleInput(),
                  RelationRoleInput(name: '\ufeffRole', ordered: false),
                ],
                original: i == 0
                    ? null
                    : RelationRecord(
                        namespace: '\ufeffOriginal',
                        key: '\ufeffKey',
                        labels: {'': '', '\ufeffen': '\ufeffName\r\n\u0000😀'},
                        roles: [
                          RoleDefinition(
                            name: '\ufeffRole',
                            participantTypes: [record, record],
                            multiplicity: Multiplicity.multiple,
                            ordered: true,
                          ),
                          RoleDefinition(
                            name: '\ufeffRole',
                            multiplicity: Multiplicity.single,
                            ordered: false,
                          ),
                        ],
                      ),
              );
              return (s, f);
            })(),
        ];
        await seed(database, tables, [
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
                  for (final v in f.roles)
                    {
                      'name': v.name,
                      'participantTypes': v.participantTypes,
                      'multiplicity': v.multiplicity,
                      'ordered': v.ordered,
                    },
                ],
                [
                  for (final l in f.labels)
                    {'language': l.language, 'text': l.text},
                ],
              ],
            ),
        ]);
        try {
          if (malformed) {
            await expectLater(
              BrowserRelationFormRecoveryStore.open(databaseName: database),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(database, tables);
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
            var store = await BrowserRelationFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, f, saved.generation);
              }
              store.close();
              store = await BrowserRelationFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.toWire().toText(),
                );
              }
              final db = await openDatabase(database, tables);
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
          await cleanup(database);
        }
      },
    );
    test(
      'value_definition upgrade ${malformed ? 'rolls back malformed originals' : 'preserves nested definitions, labels and ordered child input'}',
      () async {
        final database =
                'ub-value_definition-fields-${OperationId.generate().value}',
            tables = [
              'value_definition_form',
              'value_definition_field',
              'value_definition_label',
            ];
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(i), record = RecordId.generate();
              final f = UnfinishedValueDefinitionForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: s.typeClientRef ?? '\ufeffCreation',
                namespace: '\ufeffNamespace',
                key: '\ufeffKey',
                labels: const [
                  PropertyLabelInput(
                    language: '',
                    text: '\ufeffLabel\r\n\u0000😀',
                  ),
                  PropertyLabelInput(),
                ],
                rationale: '\ufeffReason',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                revisionTarget: const ExpressionReferenceInput(
                  record: '\ufeffTarget',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                fields: [
                  ValueDefinitionFieldInput(
                    name: '\ufeffField',
                    shape: ValueShapeInput(
                      kind: 'sequence',
                      item: ValueShapeInput(
                        kind: 'unfinished',
                        definition: '\ufeffDisabled',
                      ),
                    ),
                    required: false,
                    allowsUnknown: true,
                  ),
                  ValueDefinitionFieldInput(shape: ValueShapeInput()),
                  ValueDefinitionFieldInput(
                    name: '\ufeffField',
                    shape: ValueShapeInput(),
                    required: true,
                  ),
                ],
                original: i == 0
                    ? null
                    : ValueDefinitionRecord(
                        namespace: '\ufeffOriginal',
                        key: '\ufeffKey',
                        labels: {'': '', '\ufeffen': '\ufeffName\r\n\u0000😀'},
                        fields: [
                          ValueDefinitionField(
                            name: '\ufeffField',
                            shape: SequenceShape(
                              StructuredShape(ValueDefinitionId.generate()),
                            ),
                            required: false,
                            allowsUnknown: true,
                          ),
                          ValueDefinitionField(
                            name: '\ufeffField',
                            shape: EntityRefShape([record, record]),
                            required: true,
                            allowsUnknown: false,
                          ),
                        ],
                      ),
              );
              return (s, f);
            })(),
        ];
        await seed(database, tables, [
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
                  for (final v in f.fields)
                    {
                      'name': v.name,
                      'shape': encodeBrowserInput(v.shape.toWire()),
                      'required': v.required,
                      'allowsUnknown': v.allowsUnknown,
                    },
                ],
                [
                  for (final l in f.labels)
                    {'language': l.language, 'text': l.text},
                ],
              ],
            ),
        ]);
        try {
          if (malformed) {
            await expectLater(
              BrowserValueDefinitionFormRecoveryStore.open(
                databaseName: database,
              ),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(database, tables);
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
            var store = await BrowserValueDefinitionFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, f, saved.generation);
              }
              store.close();
              store = await BrowserValueDefinitionFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.toWire().toText(),
                );
              }
              final db = await openDatabase(database, tables);
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
          await cleanup(database);
        }
      },
    );
  }
}
