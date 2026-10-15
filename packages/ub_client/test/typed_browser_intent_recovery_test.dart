@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_attitude_recovery.dart';
import 'package:ub_client/browser_commitment_recovery.dart';
import 'package:ub_client/browser_plan_recovery.dart';
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

void main() {
  for (final malformed in [false, true]) {
    test(
      'browser attitude originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-attitude-typed-${OperationId.generate().value}',
            table = 'attitude_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedAttitudeForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                holder: const ExpressionReferenceInput(record: '\ufeffHolder'),
                proposition: const ExpressionReferenceInput(),
                attitude: 'unfinished',
                certaintyEnabled: false,
                certainty: '\ufeffDisabled',
                validity: const TemporalValidityInput(kind: 'unfinished'),
                basis: const EvidenceBasisInput(
                  kind: 'source',
                  verified: false,
                  note: '\ufeffBasis',
                ),
                acquisition: const KnowledgeAcquisitionInput(
                  enabled: false,
                  worldEnabled: false,
                  interpretationEnabled: false,
                  communication: ExpressionReferenceInput(
                    record: '\ufeffMessage',
                  ),
                ),
                correctionTarget: const ExpressionReferenceInput(
                  record: '\ufeffCorrection',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                original: i == 0
                    ? null
                    : EpistemicAttitudeRecord(
                        holder: repeated,
                        proposition: ref(),
                        attitude: EpistemicAttitudeKind.values[i - 1],
                        certainty: i == 1 ? null : '',
                        validity: InstantValidity(time()),
                        basis: SourceAnchorBasis(ref(), i == 2),
                        acquisition: KnowledgeAcquisition(
                          truthContext: ref(),
                          time: time(),
                          world: i == 1 ? null : ref(),
                          basis: i == 1
                              ? const AuthorEstablishedKnowledge()
                              : CommunicationKnowledge(
                                  communication: ref(),
                                  interpretation: ref(),
                                ),
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
                'holder': encodeBrowserInput(f.holder.toWire()),
                'proposition': encodeBrowserInput(f.proposition.toWire()),
                'attitude': f.attitude,
                'certaintyEnabled': f.certaintyEnabled,
                'certainty': f.certainty,
                'validity': encodeBrowserInput(f.validity.toWire()),
                'basis': encodeBrowserInput(f.basis.toWire()),
                'acquisition': encodeBrowserInput(f.acquisition.toWire()),
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
              BrowserAttitudeFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserAttitudeFormRecoveryStore.open(
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
              store = await BrowserAttitudeFormRecoveryStore.open(
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
      'browser commitment originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-commitment-typed-${OperationId.generate().value}',
            table = 'commitment_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedCommitmentForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                parties: const [
                  CommitmentPartyInput(role: '\ufeffRole'),
                  CommitmentPartyInput(record: '\ufeffParty'),
                  CommitmentPartyInput(role: '\ufeffRole'),
                ],
                obligated: const ExpressionReferenceInput(
                  record: '\ufeffObligation',
                ),
                conditions: [
                  ExpressionInput(
                    kind: 'all',
                    items: [
                      ExpressionInput(),
                      ExpressionInput(kind: 'literal', flags: {'value': null}),
                    ],
                  ),
                ],
                deadlineEnabled: false,
                deadline: const TemporalValidityInput(kind: 'unfinished'),
                status: '\ufeffUnfinished',
                original: i == 0
                    ? null
                    : CommitmentRecord(
                        parties: [
                          CommitmentParty(
                            repeated,
                            '\ufeffPromisor\r\n\u0000😀',
                          ),
                          CommitmentParty(repeated, ''),
                        ],
                        obligated: ref(),
                        conditions: [
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
                        deadline: i == 1 ? null : time(),
                        status: i == 1
                            ? CommitmentStatus.fulfilled
                            : CommitmentStatus.breached,
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
                'parties': encodeBrowserInput(
                  CanonicalArray(f.parties.map((p) => p.toWire())),
                ),
                'obligated': encodeBrowserInput(f.obligated.toWire()),
                'conditions': encodeBrowserInput(
                  CanonicalArray(f.conditions.map((e) => e.toWire())),
                ),
                'deadlineEnabled': f.deadlineEnabled,
                'deadline': encodeBrowserInput(f.deadline.toWire()),
                'status': f.status,
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserCommitmentFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserCommitmentFormRecoveryStore.open(
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
              store = await BrowserCommitmentFormRecoveryStore.open(
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
      'browser plan originals ${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-plan-typed-${OperationId.generate().value}',
            table = 'plan_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedPlanForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                actor: const ExpressionReferenceInput(record: '\ufeffActor'),
                desiredEnabled: false,
                desired: const ExpressionReferenceInput(
                  record: '\ufeffDisabled',
                ),
                prerequisites: [
                  ExpressionInput(
                    kind: 'all',
                    items: [
                      ExpressionInput(),
                      ExpressionInput(kind: 'literal', flags: {'value': null}),
                    ],
                  ),
                ],
                steps: const [
                  ExpressionReferenceInput(),
                  ExpressionReferenceInput(record: '\ufeffStep'),
                  ExpressionReferenceInput(record: '\ufeffStep'),
                ],
                status: '\ufeffUnfinished',
                validity: const TemporalValidityInput(kind: 'unfinished'),
                original: i == 0
                    ? null
                    : GoalRecord(
                        actor: repeated,
                        desired: i == 1 ? null : ref(),
                        prerequisites: [
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
                        steps: [repeated, repeated],
                        status: i == 1
                            ? PlanStatus.abandoned
                            : PlanStatus.achieved,
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
                'actor': encodeBrowserInput(f.actor.toWire()),
                'desiredEnabled': f.desiredEnabled,
                'desired': encodeBrowserInput(f.desired.toWire()),
                'prerequisites': encodeBrowserInput(
                  CanonicalArray(f.prerequisites.map((e) => e.toWire())),
                ),
                'steps': encodeBrowserInput(
                  CanonicalArray(f.steps.map((r) => r.toWire())),
                ),
                'status': f.status,
                'validity': encodeBrowserInput(f.validity.toWire()),
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserPlanFormRecoveryStore.open(databaseName: database),
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
            var store = await BrowserPlanFormRecoveryStore.open(
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
              store = await BrowserPlanFormRecoveryStore.open(
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
