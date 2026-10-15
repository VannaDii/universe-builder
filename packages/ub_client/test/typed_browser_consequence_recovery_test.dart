@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_action_recovery.dart';
import 'package:ub_client/browser_event_recovery.dart';
import 'package:ub_client/src/browser_input_fields.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _StoredRow._(JSObject _) implements JSObject {
  external String? get original;
  external JSArray<_ChildRow>? get slots;
  external JSArray<_ChildRow>? get effects;
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

@JS()
extension type _ChildRow._(JSObject _) implements JSObject {
  external String? get original;
  external JSAny? get originalFields;
}

EffectSlot slot(int order) => EffectSlot(
  slot: 'power',
  order: order,
  presence: EffectPresence.required,
  target: EffectTarget('actor', ref()),
  condition: const AlwaysEffect(),
  change: SetEffect(Polarity.support, IntegerValue('900719925474099312345')),
  lifetime: const UntilChangedEffect(),
);
EntityEffect effect() => EntityEffect(
  slot: 'power',
  proposition: ref(),
  polarity: Polarity.refutation,
  validity: InstantValidity(time()),
  scope: Scope(context: ref(), applicability: const UniverseApplicability()),
  order: (BigInt.one << 64) - BigInt.one,
);
CanonicalObject _replacement(CanonicalObject input) => CanonicalObject([
  ...input.fields.where((field) => field.key != 'rationale'),
  MapEntry('rationale', CanonicalString('\ufeffReplacement')),
]);
UnfinishedActionForm _changedAction(UnfinishedActionForm f) =>
    UnfinishedActionForm.fromWire(_replacement(f.toWire()));
UnfinishedEventForm _changedEvent(UnfinishedEventForm f) =>
    UnfinishedEventForm.fromWire(_replacement(f.toWire()));
void main() {
  for (final failure in [0, 1, 2]) {
    final malformed = failure != 0;
    test(
      'browser action originals ${failure == 2 ? 'child ' : ''}${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-action-typed-${OperationId.generate().value}',
            table = 'action_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedActionForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                namespace: '\ufeffNamespace',
                key: '\ufeffKey',
                labels: const [
                  PropertyLabelInput(language: '', text: '\ufeffLabel'),
                  PropertyLabelInput(),
                ],
                requirements: const [
                  ActionRequirementInput(role: '\ufeffRole'),
                  ActionRequirementInput(),
                ],
                slots: i == 0
                    ? null
                    : i == 1
                    ? []
                    : [
                        ActionSlotInput(
                          fields: {
                            '\ufeffKey': '\ufeffInput\r\n\u0000😀',
                            'order': 'unfinished',
                          },
                          target: const ExpressionReferenceInput(
                            record: '\ufeffTarget',
                          ),
                          original: slot(255),
                        ),
                        ActionSlotInput(),
                      ],
                scope: const ScopeInput(
                  applicability: 'worlds',
                  worlds: ['world', '', 'world'],
                ),
                validity: const TemporalValidityInput(kind: 'unfinished'),
                revisionTarget: const ExpressionReferenceInput(
                  record: '\ufeffRevision',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                original: i == 0
                    ? null
                    : ActionDefinitionRecord(
                        namespace: '\ufeffOriginal',
                        key: '\ufeffKey',
                        labels: {'': '', '\ufeffen': '\ufeffLabel'},
                        requirements: [],
                        consequenceContract: i == 1
                            ? null
                            : ConsequenceContract([slot(63)]),
                        scope: Scope(
                          context: repeated,
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
                'original': failure == 1 && failure == 1 && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
                'namespace': f.namespace,
                'key': f.key,
                'labels': encodeBrowserInput(
                  CanonicalArray(f.labels.map((l) => l.toWire())),
                ),
                'requirements': encodeBrowserInput(
                  CanonicalArray(f.requirements.map((r) => r.toWire())),
                ),
                'slots': f.slots == null
                    ? null
                    : [
                        for (final v in f.slots!)
                          {
                            'fields': encodeBrowserInput(
                              CanonicalObject(
                                v.fields.entries.map(
                                  (e) =>
                                      MapEntry(e.key, CanonicalString(e.value)),
                                ),
                              ),
                            ),
                            'target': encodeBrowserInput(v.target.toWire()),
                            'condition': encodeBrowserInput(
                              v.condition.toWire(),
                            ),
                            'value': encodeBrowserInput(v.value.toWire()),
                            'original':
                                failure == 2 &&
                                    f == forms.last.$2 &&
                                    v == f.slots!.first
                                ? '{unfinished'
                                : v.original?.toWire().toText(),
                          },
                      ],
                'factualScope': encodeBrowserInput(f.scope.toWire()),
                'validity': encodeBrowserInput(f.validity.toWire()),
                'revisionTarget': encodeBrowserInput(
                  f.revisionTarget!.toWire(),
                ),
                'expectedRecordVersion': f.expectedRecordVersion!.value,
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserActionFormRecoveryStore.open(databaseName: database),
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
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserActionFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, _changedAction(f), saved.generation);
              }
              store.close();
              store = await BrowserActionFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  _changedAction(f).toWire().toText(),
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
      'browser event originals ${failure == 2 ? 'child ' : ''}${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-event-typed-${OperationId.generate().value}',
            table = 'event_form';
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedEventForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: '\ufeffInput',
                rationale: '\ufeffReason\r\n\u0000😀',
                draftVersion: (BigInt.one << 64) - BigInt.one,
                label: '\ufeffLabel\r\n\u0000😀',
                occurrence: 'unfinished',
                description: '\ufeffDescription',
                actionRecord: '\ufeffAction',
                actionUniverse: '',
                time: const TemporalValidityInput(kind: 'unfinished'),
                participants: const [
                  EventParticipantInput(role: '\ufeffRole'),
                  EventParticipantInput(),
                  EventParticipantInput(role: '\ufeffRole'),
                ],
                effects: i == 0
                    ? null
                    : i == 1
                    ? []
                    : [
                        EventEffectInput(
                          slot: '\ufeffSlot',
                          order: 'unfinished',
                          original: effect(),
                        ),
                        const EventEffectInput(),
                      ],
                preconditions: i == 0
                    ? null
                    : i == 1
                    ? []
                    : [
                        ExpressionInput(
                          kind: 'all',
                          items: [
                            ExpressionInput(),
                            ExpressionInput(
                              kind: 'literal',
                              flags: {'value': null},
                            ),
                          ],
                        ),
                      ],
                worlds: const ['world', '', 'world'],
                regionRecord: '\ufeffRegion',
                regionUniverse: '',
                sequence: '\ufeffSequence',
                occurrenceId: '\ufeffOccurrence',
                revisionTarget: const ExpressionReferenceInput(
                  record: '\ufeffRevision',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                original: i == 0
                    ? null
                    : EventRecord(
                        occurrence: const SimpleOccurrence(
                          OccurrenceKind.planned,
                        ),
                        action: i == 1 ? null : ref(),
                        region: i == 1 ? null : ref(),
                        worlds: [WorldId.generate()],
                        time: time(),
                        sequence: i == 1 ? null : '',
                        occurrenceId: i == 1 ? null : '',
                        participants: [
                          EventParticipant(repeated, '\ufeffRole'),
                          EventParticipant(repeated, '\ufeffRole'),
                        ],
                        preconditions: [
                          AllExpr([const LiteralExpr(false)]),
                        ],
                        effects: i == 1 ? [] : [effect()],
                        labels: {'': '', '\ufeffen': '\ufeffLabel'},
                        expansionVersion: i == 1 ? null : '',
                        basis: i == 1
                            ? null
                            : AuthorDecisionBasis('\ufeffBasis'),
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
                'label': f.label,
                'occurrence': f.occurrence,
                'description': f.description,
                'actionRecord': f.actionRecord,
                'actionUniverse': f.actionUniverse,
                'time': encodeBrowserInput(f.time.toWire()),
                'participants': encodeBrowserInput(
                  CanonicalArray(f.participants.map((r) => r.toWire())),
                ),
                'effects': f.effects == null
                    ? null
                    : [
                        for (final v in f.effects!)
                          {
                            'slot': v.slot,
                            'propositionRecord': v.propositionRecord,
                            'propositionUniverse': v.propositionUniverse,
                            'polarity': v.polarity,
                            'order': v.order,
                            'factualScope': encodeBrowserInput(
                              v.scope.toWire(),
                            ),
                            'validity': encodeBrowserInput(v.validity.toWire()),
                            'original':
                                failure == 2 &&
                                    f == forms.last.$2 &&
                                    v == f.effects!.first
                                ? '{unfinished'
                                : v.original?.toWire().toText(),
                          },
                      ],
                'preconditions': f.preconditions == null
                    ? null
                    : encodeBrowserInput(
                        CanonicalArray(f.preconditions!.map((e) => e.toWire())),
                      ),
                'worlds': f.worlds,
                'regionRecord': f.regionRecord,
                'regionUniverse': f.regionUniverse,
                'sequence': f.sequence,
                'occurrenceId': f.occurrenceId,
                'revisionTarget': encodeBrowserInput(
                  f.revisionTarget!.toWire(),
                ),
                'expectedRecordVersion': f.expectedRecordVersion!.value,
              },
            ),
        ];
        await seed(database, table, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserEventFormRecoveryStore.open(databaseName: database),
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
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserEventFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, _changedEvent(f), saved.generation);
              }
              store.close();
              store = await BrowserEventFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  _changedEvent(f).toWire().toText(),
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
