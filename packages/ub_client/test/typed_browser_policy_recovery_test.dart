@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_exception_recovery.dart';
import 'package:ub_client/browser_completeness_recovery.dart';
import 'package:ub_client/browser_boundary_recovery.dart';
import 'package:ub_client/src/browser_input_fields.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _StoredRow._(JSObject _) implements JSObject {
  external String? get original;
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

UnfinishedCompletenessForm _changedCompleteness(UnfinishedCompletenessForm f) =>
    UnfinishedCompletenessForm.fromWire(
      CanonicalObject([
        ...f.toWire().fields.where((field) => field.key != 'rationale'),
        MapEntry('rationale', CanonicalString('\ufeffReplacement')),
      ]),
    );
void main() {
  for (final malformed in [false, true]) {
    test(
      'browser exception originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-exception-typed-${OperationId.generate().value}',
            table = 'exception_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedExceptionForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                rule: const ExpressionReferenceInput(record: '\ufeffRule'),
                ruleVersionEnabled: false,
                ruleVersion: '\ufeffDisabled',
                fictionalDeparture: i == 2,
                decision: const ExpressionReferenceInput(
                  record: '\ufeffDecision',
                ),
                scope: const ScopeInput(
                  applicability: 'worlds',
                  worlds: ['world', '', 'world'],
                ),
                validity: const TemporalValidityInput(kind: 'unfinished'),
                original: i == 0
                    ? null
                    : ExceptionRecord(
                        rule: repeated,
                        ruleVersion: i == 1 ? null : RecordVersionId.generate(),
                        scope: Scope(
                          context: ref(),
                          applicability: const UniverseApplicability(),
                        ),
                        validity: InstantValidity(time()),
                        authorizingDecision: ref(),
                        rationale: '\ufeffOriginal\r\n\u0000😀',
                        fictionalDeparture: i == 2,
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
                'rule': encodeBrowserInput(f.rule.toWire()),
                'ruleVersionEnabled': f.ruleVersionEnabled,
                'ruleVersion': f.ruleVersion,
                'fictionalDeparture': f.fictionalDeparture,
                'decision': encodeBrowserInput(f.decision.toWire()),
                'factualScope': encodeBrowserInput(f.scope.toWire()),
                'validity': encodeBrowserInput(f.validity.toWire()),
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserExceptionFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserExceptionFormRecoveryStore.open(
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
              store = await BrowserExceptionFormRecoveryStore.open(
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
      'browser completeness originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database =
                'ub-completeness-typed-${OperationId.generate().value}',
            table = 'completeness_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedCompletenessForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                subject: const ExpressionReferenceInput(
                  record: '\ufeffSubject',
                ),
                predicate: '\ufeffPredicate\r\n\u0000😀',
                members: const [
                  ExpressionReferenceInput(),
                  ExpressionReferenceInput(record: '\ufeffMember'),
                  ExpressionReferenceInput(record: '\ufeffMember'),
                ],
                kind: 'unfinished',
                observer: '\ufeffObserver',
                scope: const ScopeInput(
                  applicability: 'worlds',
                  worlds: ['world', '', 'world'],
                ),
                validity: const TemporalValidityInput(kind: 'unfinished'),
                original: i == 0
                    ? null
                    : CompletenessRecord(
                        subject: ref(),
                        predicate: '\ufeffOriginal',
                        members: i == 1 ? [] : [repeated, repeated],
                        completeness: i == 1
                            ? const ObjectiveCompleteness()
                            : ObserverCompleteness(RecordId.generate()),
                        validity: InstantValidity(time()),
                        scope: Scope(
                          context: ref(),
                          applicability: const UniverseApplicability(),
                        ),
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
                'subject': encodeBrowserInput(f.subject.toWire()),
                'predicate': f.predicate,
                'members': encodeBrowserInput(
                  CanonicalArray(f.members.map((r) => r.toWire())),
                ),
                'kind': f.kind,
                'observer': f.observer,
                'factualScope': encodeBrowserInput(f.scope.toWire()),
                'validity': encodeBrowserInput(f.validity.toWire()),
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserCompletenessFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserCompletenessFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, _changedCompleteness(f), saved.generation);
              }
              store.close();
              store = await BrowserCompletenessFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  _changedCompleteness(f).toWire().toText(),
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
      'browser boundary originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-boundary-typed-${OperationId.generate().value}',
            table = 'boundary_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedBoundaryForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                key: '\ufeffKey\r\n\u0000😀',
                areaKind: 'unfinished',
                record: const ExpressionReferenceInput(record: '\ufeffRecord'),
                predicate: '\ufeffPredicate',
                subjectEnabled: false,
                subject: const ExpressionReferenceInput(
                  record: '\ufeffDisabled',
                ),
                category: '\ufeffCategory',
                mode: 'unfinished',
                constraints: [
                  ExpressionInput(
                    kind: 'all',
                    items: [
                      ExpressionInput(kind: 'literal', flags: {'value': null}),
                      ExpressionInput(),
                    ],
                  ),
                ],
                scope: const ScopeInput(
                  applicability: 'worlds',
                  worlds: ['world', '', 'world'],
                ),
                validity: const TemporalValidityInput(kind: 'unfinished'),
                original: i == 0
                    ? null
                    : BoundaryRecord(
                        key: '\ufeffOriginal',
                        area: i == 1
                            ? RecordBoundaryArea(repeated)
                            : CategoryBoundaryArea(RecordId.generate()),
                        mode: BoundaryMode.values.first,
                        constraints: [
                          AllExpr([
                            const LiteralExpr(false),
                            CompareExpr(
                              ValueOperand(
                                RationalValue('900719925474099312345', '007'),
                              ),
                              Comparator.ltEq,
                              ValueOperand(IntegerValue('003')),
                            ),
                          ]),
                        ],
                        validity: InstantValidity(time()),
                        scope: Scope(
                          context: ref(),
                          applicability: const UniverseApplicability(),
                        ),
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
                'key': f.key,
                'areaKind': f.areaKind,
                'record': encodeBrowserInput(f.record.toWire()),
                'predicate': f.predicate,
                'subjectEnabled': f.subjectEnabled,
                'subject': encodeBrowserInput(f.subject.toWire()),
                'category': f.category,
                'mode': f.mode,
                'constraints': encodeBrowserInput(
                  CanonicalArray(f.constraints.map((e) => e.toWire())),
                ),
                'factualScope': encodeBrowserInput(f.scope.toWire()),
                'validity': encodeBrowserInput(f.validity.toWire()),
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserBoundaryFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserBoundaryFormRecoveryStore.open(
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
              store = await BrowserBoundaryFormRecoveryStore.open(
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
