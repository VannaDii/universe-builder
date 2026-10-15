@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_unit_recovery.dart';
import 'package:ub_client/browser_calendar_recovery.dart';
import 'package:ub_client/browser_issue_decision_recovery.dart';
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
      'unit upgrade ${malformed ? 'rolls back malformed originals' : 'preserves exact original fields and ordered input'}',
      () async {
        final database = 'ub-unit-fields-${OperationId.generate().value}',
            tables = ['unit_form', 'unit_form_label'];
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(i);

              final f = UnfinishedUnitForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: s.typeClientRef ?? '\ufeffCreation',
                rationale: '\ufeffReason',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                namespace: '\ufeffNamespace',
                key: '\ufeffKey',
                dimension: '\ufeffDimension',
                symbol: '\ufeffSymbol',
                labels: const [
                  PropertyLabelInput(
                    language: '',
                    text: '\ufeffLabel\r\n\u0000😀',
                  ),
                  PropertyLabelInput(),
                ],
                hasBase: false,
                base: '\ufeffDisabled',
                hasScale: false,
                scale: const QualifierInput(
                  kind: 'rational',
                  value: '900719925474099312345',
                  denominator: '007',
                ),
                validityChoice: 'unfinished',
                temporalValidity: i == 0
                    ? null
                    : const TemporalValidityInput(
                        kind: 'unfinished',
                        start: TemporalBoundInput(value: '\ufeffInput'),
                      ),
                revisionTarget: const ExpressionReferenceInput(
                  record: '\ufeffRevision',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                original: i == 0
                    ? null
                    : UnitRecord(
                        namespace: '\ufeffOriginal',
                        key: '\ufeffKey',
                        dimension: '\ufeffDimension',
                        symbol: '\ufeffSymbol',
                        labels: {'': '', '\ufeffen': '\ufeffName\r\n\u0000😀'},
                        scaleToBase: i == 1
                            ? null
                            : RationalValue('900719925474099312345', '007'),
                        base: i == 1 ? null : UnitId.generate(),
                        validity: InstantValidity(
                          ApproximateTime(
                            CalendarId.generate(),
                            '\ufeffCoordinate',
                            SequenceValue([
                              IntegerValue('900719925474099312345'),
                              TextValue('\ufeffAmount'),
                            ]),
                          ),
                        ),
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
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'namespace': f.namespace,
                'key': f.key,
                'dimension': f.dimension,
                'symbol': f.symbol,
                'hasBase': f.hasBase,
                'base': f.base,
                'hasScale': f.hasScale,
                'scale': encodeBrowserInput(f.scale.toWire()),
                'validityChoice': f.validityChoice,
                'temporal': f.temporalValidity == null
                    ? null
                    : encodeBrowserInput(f.temporalValidity!.toWire()),
                'revisionTarget': encodeBrowserInput(
                  f.revisionTarget!.toWire(),
                ),
                'expectedRecordVersion': f.expectedRecordVersion!.value,
              },
              [
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
              BrowserUnitFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserUnitFormRecoveryStore.open(
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
              store = await BrowserUnitFormRecoveryStore.open(
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
      'calendar upgrade ${malformed ? 'rolls back malformed originals' : 'preserves exact original fields and ordered input'}',
      () async {
        final database = 'ub-calendar-fields-${OperationId.generate().value}',
            tables = [
              'calendar_form',
              'calendar_unit',
              'calendar_label',
              'calendar_conversion',
            ];
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(i);
              final calendar = CalendarId.generate();

              final f = UnfinishedCalendarForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: s.typeClientRef ?? '\ufeffCreation',
                rationale: '\ufeffReason',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                namespace: '\ufeffNamespace',
                key: '\ufeffKey',
                labels: const [
                  PropertyLabelInput(
                    language: '',
                    text: '\ufeffLabel\r\n\u0000😀',
                  ),
                  PropertyLabelInput(),
                ],
                hasEpoch: false,
                epoch: '\ufeffDisabled',
                units: const [
                  CalendarUnitInput(
                    name: '\ufeffUnit',
                    structure: '900719925474099312345 ticks',
                  ),
                  CalendarUnitInput(),
                  CalendarUnitInput(name: '\ufeffUnit'),
                ],
                conversions: const [
                  CalendarConversionInput(
                    target: '\ufeffTarget',
                    hasExpression: false,
                    expression: '\ufeffDisabled',
                    valid: false,
                  ),
                  CalendarConversionInput(
                    target: '\ufeffTarget',
                    hasExpression: true,
                    expression: '',
                    valid: true,
                  ),
                ],
                revisionTarget: const ExpressionReferenceInput(
                  record: '\ufeffRevision',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                original: i == 0
                    ? null
                    : CalendarRecord(
                        namespace: '\ufeffOriginal',
                        key: '\ufeffKey',
                        labels: {'': '', '\ufeffen': '\ufeffName\r\n\u0000😀'},
                        epoch: i == 1 ? null : '',
                        unitStructure: {
                          '': '',
                          '\ufeffUnit': '900719925474099312345 ticks',
                        },
                        conversions: [
                          CalendarConversion(
                            target: calendar,
                            expression: null,
                            valid: false,
                          ),
                          CalendarConversion(
                            target: calendar,
                            expression: '',
                            valid: true,
                          ),
                          CalendarConversion(
                            target: calendar,
                            expression: '\ufeffExact\r\n\u0000😀',
                            valid: false,
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
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'namespace': f.namespace,
                'key': f.key,
                'hasEpoch': f.hasEpoch,
                'epoch': f.epoch,
                'revisionTarget': encodeBrowserInput(
                  f.revisionTarget!.toWire(),
                ),
                'expectedRecordVersion': f.expectedRecordVersion!.value,
              },
              [
                [
                  for (final u in f.units)
                    {'name': u.name, 'structure': u.structure},
                ],
                [
                  for (final l in f.labels)
                    {'language': l.language, 'text': l.text},
                ],
                [
                  for (final c in f.conversions)
                    {
                      'target': c.target,
                      'hasExpression': c.hasExpression,
                      'expression': c.expression,
                      'valid': c.valid,
                    },
                ],
              ],
            ),
        ]);
        try {
          if (malformed) {
            await expectLater(
              BrowserCalendarFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserCalendarFormRecoveryStore.open(
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
              store = await BrowserCalendarFormRecoveryStore.open(
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
      'issue_decision upgrade ${malformed ? 'rolls back malformed originals' : 'preserves exact original fields and ordered input'}',
      () async {
        final database =
                'ub-issue_decision-fields-${OperationId.generate().value}',
            tables = ['issue_decision_form'];
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(i);

              final principal = PrincipalId.parse(
                s.profile.value.replaceFirst('prf_', 'prn_'),
              );
              final f = UnfinishedIssueDecisionForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: s.typeClientRef ?? '\ufeffCreation',
                rationale: '\ufeffReason',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                principal: principal,
                mode: 'unfinished',
                fingerprints: ['\ufeffFingerprint', '', '\ufeffFingerprint'],
                scope: '\ufeffScope',
                original: i == 0
                    ? null
                    : IssueDecisionRecord(
                        fingerprints: [
                          FindingFingerprint('a' * 64),
                          FindingFingerprint('a' * 64),
                        ],
                        mode: IssueDecisionMode.values[i - 1],
                        scope: '\ufeffOriginal',
                        rationale: '\ufeffOriginal\r\n\u0000😀',
                        principal: principal,
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
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'principal': f.principal.value,
                'mode': f.mode,
                'fingerprints': f.fingerprints,
                'decisionScope': f.scope,
              },
              [],
            ),
        ]);
        try {
          if (malformed) {
            await expectLater(
              BrowserIssueDecisionFormRecoveryStore.open(
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
            var store = await BrowserIssueDecisionFormRecoveryStore.open(
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
              store = await BrowserIssueDecisionFormRecoveryStore.open(
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
