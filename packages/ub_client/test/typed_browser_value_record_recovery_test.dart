@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_proposition_recovery.dart';
import 'package:ub_client/browser_item_power_recovery.dart';
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

UnfinishedPropositionForm _changedProposition(UnfinishedPropositionForm f) =>
    UnfinishedPropositionForm.fromWire(
      CanonicalObject([
        ...f.toWire().fields.where((field) => field.key != 'rationale'),
        MapEntry('rationale', CanonicalString('\ufeffReplacement')),
      ]),
    );
void main() {
  for (final malformed in [false, true]) {
    test(
      'browser proposition originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-proposition-typed-${OperationId.generate().value}',
            table = 'proposition_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedPropositionForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                subject: const ExpressionReferenceInput(
                  record: '\ufeffSubject',
                ),
                predicate: const ExpressionReferenceInput(
                  record: '\ufeffPredicate',
                ),
                context: const ExpressionReferenceInput(),
                roles: const [
                  PropositionRoleInput(role: '\ufeffRole'),
                  PropositionRoleInput(),
                  PropositionRoleInput(role: '\ufeffRole'),
                ],
                quantification: 'unfinished',
                hasValue: false,
                value: const QualifierInput(
                  kind: 'sequence',
                  originalKey: '',
                  children: [
                    QualifierInput(value: '\ufeffDisabled'),
                    QualifierInput(),
                  ],
                ),
                original: i == 0
                    ? null
                    : PropositionRecord(
                        predicate: ref(),
                        subject: repeated,
                        roles: [
                          PropositionRole('\ufeffRole', repeated),
                          PropositionRole('\ufeffRole', repeated),
                        ],
                        value: i == 1
                            ? null
                            : SequenceValue([
                                const IntegerValue('900719925474099312345'),
                                RationalValue('003', '002'),
                                TextValue('\ufeffOriginal\r\n\u0000😀'),
                              ]),
                        quantification: Quantification.values[i - 1],
                        context: ref(),
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
                'predicate': encodeBrowserInput(f.predicate.toWire()),
                'context': encodeBrowserInput(f.context.toWire()),
                'roles': encodeBrowserInput(
                  CanonicalArray(f.roles.map((r) => r.toWire())),
                ),
                'quantification': f.quantification,
                'hasValue': f.hasValue,
                'value': encodeBrowserInput(f.value.toWire()),
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserPropositionFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserPropositionFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, _changedProposition(f), saved.generation);
              }
              store.close();
              store = await BrowserPropositionFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  _changedProposition(f).toWire().toText(),
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
      'browser item_power originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-item_power-typed-${OperationId.generate().value}',
            table = 'item_power_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedItemPowerForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                item: const ExpressionReferenceInput(record: '\ufeffItem'),
                holderPredicate: const ExpressionReferenceInput(
                  record: '\ufeffHolder',
                ),
                powerPredicate: const ExpressionReferenceInput(),
                value: const QualifierInput(
                  kind: 'sequence',
                  originalKey: '',
                  children: [
                    QualifierInput(value: '\ufeffChild\r\n\u0000😀'),
                    QualifierInput(),
                  ],
                ),
                scope: const ScopeInput(
                  applicability: 'worlds',
                  worlds: ['world', '', 'world'],
                ),
                validity: const TemporalValidityInput(kind: 'unfinished'),
                correctionTarget: const ExpressionReferenceInput(
                  record: '\ufeffCorrection',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                original: i == 0
                    ? null
                    : ItemPowerRecord(
                        item: repeated,
                        holderPredicate: ref(),
                        powerPredicate: ref(),
                        value: i == 1
                            ? const BooleanValue(false)
                            : RangeValue(
                                lower: RationalValue(
                                  '900719925474099312345',
                                  '007',
                                ),
                                upper: IntegerValue('003'),
                                lowerInclusive: false,
                                upperInclusive: true,
                                unit: UnitId.generate(),
                              ),
                        scope: Scope(
                          context: ref(),
                          applicability: const UniverseApplicability(),
                        ),
                        validity: InstantValidity(time()),
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
                'item': encodeBrowserInput(f.item.toWire()),
                'holderPredicate': encodeBrowserInput(
                  f.holderPredicate.toWire(),
                ),
                'powerPredicate': encodeBrowserInput(f.powerPredicate.toWire()),
                'value': encodeBrowserInput(f.value.toWire()),
                'factualScope': encodeBrowserInput(f.scope.toWire()),
                'validity': encodeBrowserInput(f.validity.toWire()),
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
              BrowserItemPowerFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserItemPowerFormRecoveryStore.open(
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
              store = await BrowserItemPowerFormRecoveryStore.open(
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
