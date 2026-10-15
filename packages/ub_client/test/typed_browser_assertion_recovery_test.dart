@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_assertion_end_recovery.dart';
import 'package:ub_client/browser_assertion_correction_recovery.dart';
import 'package:ub_client/src/browser_input_fields.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _StoredRow._(JSObject _) implements JSObject {
  external String? get original;
  external String? get originalBasis;
  external String? get validity;
  external JSAny? get originalFields;
  external JSAny? get originalBasisFields;
  external JSAny? get evidence;
}

EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
);
RecordRef ref() =>
    RecordRef(record: RecordId.generate(), universe: UniverseId.generate());
VersionRef version() => VersionRef(
  record: RecordId.generate(),
  version: RecordVersionId.generate(),
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
      'assertion-end upgrade ${malformed ? 'rolls back all bases' : 'retains every basis variant and pinned target'}',
      () async {
        final name = 'ub-end-typed-${OperationId.generate().value}',
            table = 'assertion_end_form',
            pin = version();
        final bases = <EvidenceBasis>[
          const AuthorDecisionBasis('\ufeffNote\r\n\u0000😀'),
          SourceAnchorBasis(ref(), false),
          EventEffectBasis(ref(), '\ufeffSlot'),
          InstanceInitializationBasis(version(), pin, RevisionId.generate()),
          const ImportedClaimBasis(),
          DerivationBasis([pin, pin], '\ufeffEvaluator'),
        ];
        final forms = [
          for (final basis in bases)
            (() {
              final s = scope();
              return (
                s,
                UnfinishedAssertionEndForm(
                  baseRevision: RevisionId.generate(),
                  representedContext: s.representedContext!,
                  clientRef: '\ufeffEnding',
                  target: const ExpressionReferenceInput(
                    record: '\ufeffTarget',
                    universe: '',
                  ),
                  expectedRecordVersion: RecordVersionId.generate(),
                  calendar: CalendarId.generate(),
                  coordinate: '\ufeff900719925474099312345\r\n\u0000😀',
                  originalBasis: basis,
                  basis: const EvidenceBasisInput(
                    kind: 'source',
                    note: '\ufeffInput',
                    anchorRecord: '\ufeffAnchor',
                    verified: false,
                  ),
                  rationale: '\ufeffReason',
                  draftVersion: (BigInt.one << 64) - BigInt.one,
                ),
              );
            })(),
        ];
        await seed(name, table, [
          for (final (s, f) in forms)
            (
              s,
              {
                'generation': '9007199254740993',
                'baseRevision': f.baseRevision.value,
                'representedContext': f.representedContext.value,
                'clientRef': f.clientRef,
                'targetRecord': f.target.record,
                'targetUniverse': f.target.universe,
                'expectedRecordVersion': f.expectedRecordVersion.value,
                'calendar': f.calendar.value,
                'coordinate': f.coordinate,
                'basisKind': f.basis.kind,
                'basisNote': f.basis.note,
                'anchorRecord': f.basis.anchorRecord,
                'anchorUniverse': f.basis.anchorUniverse,
                'verified': f.basis.verified,
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'originalBasis': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.originalBasis.toWire().toText(),
              },
            ),
        ]);
        try {
          if (malformed) {
            await expectLater(
              BrowserAssertionEndFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name, table);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, table, s);
                expect(
                  row.originalBasis,
                  f == forms.last.$2
                      ? '{unfinished'
                      : f.originalBasis.toWire().toText(),
                );
                expect(row.originalBasisFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserAssertionEndFormRecoveryStore.open(
              databaseName: name,
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
              store = await BrowserAssertionEndFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.copyWith(rationale: '\ufeffReplacement').toWire().toText(),
                );
              }
              final db = await openDatabase(name, table);
              try {
                expect(db.version, 2);
                for (final (s, _) in forms) {
                  final row = await _read(db, table, s);
                  expect(row.originalBasis, isNull);
                  expect(row.originalBasisFields, isNotNull);
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
  for (final failure in [0, 1, 2]) {
    test(
      'assertion-correction upgrade ${failure == 0 ? 'retains original assertions and complete evidence' : 'rolls back malformed ${failure == 1 ? 'original' : 'validity'}'}',
      () async {
        final name = 'ub-correction-typed-${OperationId.generate().value}',
            table = 'assertion_correction_form';
        final amount = SequenceValue([
          const RationalValue('900719925474099312345', '007'),
          TextValue('\ufeffValue\r\n\u0000😀'),
        ]);
        final validity = IntervalValidity(
          ApproximateBound('\ufeffStart', amount),
          const UnboundedBound(),
        );
        final forms = [
          for (var i = 0; i < 3; i++)
            (() {
              final s = scope(), event = EventEffectRef(ref(), '\ufeffSlot');
              return (
                s,
                UnfinishedAssertionCorrectionForm(
                  baseRevision: RevisionId.generate(),
                  representedContext: s.representedContext!,
                  clientRef: '\ufeffCorrection',
                  target: const ExpressionReferenceInput(
                    record: '\ufeffTarget',
                  ),
                  expectedRecordVersion: RecordVersionId.generate(),
                  original: AssertionRecord(
                    attributeMode: AttributeMode.instance,
                    proposition: ref(),
                    polarity: Polarity.refutation,
                    scope: Scope(
                      context: ref(),
                      applicability: const UniverseApplicability(),
                    ),
                    validity: validity,
                    persistence: PersistenceSemantics.explicitInterval,
                    precision: Precision.approximate,
                    alternatives: [amount, amount],
                    basis: EventEffectBasis(event.event, event.slot),
                    establishedBy: i == 0 ? null : event,
                  ),
                  proposition: const ExpressionReferenceInput(
                    record: '\ufeffProposition',
                  ),
                  evidence: i == 0
                      ? const AttributeEvidenceInput()
                      : AttributeEvidenceInput(
                          validity: validity,
                          alternatives: const [],
                          basis: const EvidenceBasisInput(
                            kind: 'source',
                            verified: false,
                            note: '\ufeffNote',
                          ),
                          scope: const ScopeInput(
                            applicability: 'worlds',
                            worlds: ['world', '', 'world'],
                          ),
                          temporalValidity: const TemporalValidityInput(
                            kind: 'unfinished',
                          ),
                        ),
                  rationale: '\ufeffReason\r\n\u0000😀',
                  draftVersion: (BigInt.one << 64) - BigInt.one,
                ),
              );
            })(),
        ];
        await seed(name, table, [
          for (final (s, f) in forms)
            (
              s,
              {
                'generation': '9007199254740993',
                'baseRevision': f.baseRevision.value,
                'representedContext': f.representedContext.value,
                'clientRef': f.clientRef,
                'targetRecord': f.target.record,
                'targetUniverse': f.target.universe,
                'expectedRecordVersion': f.expectedRecordVersion.value,
                'original': failure == 1 && f == forms.last.$2
                    ? '{unfinished'
                    : f.original.toWire().toText(),
                'propositionRecord': f.proposition.record,
                'propositionUniverse': f.proposition.universe,
                'evidence': encodeBrowserInput(
                  CanonicalObject(
                    f.evidence.toWire().fields.where(
                      (field) => field.key != 'validity',
                    ),
                  ),
                ),
                'validity': failure == 2 && f == forms.last.$2
                    ? '{unfinished'
                    : f.evidence.validity?.toWire().toText(),
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
              },
            ),
        ]);
        try {
          if (failure != 0) {
            await expectLater(
              BrowserAssertionCorrectionFormRecoveryStore.open(
                databaseName: name,
              ),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name, table);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, table, s);
                expect(
                  row.original,
                  failure == 1 && f == forms.last.$2
                      ? '{unfinished'
                      : f.original.toWire().toText(),
                );
                expect(
                  row.validity,
                  failure == 2 && f == forms.last.$2
                      ? '{unfinished'
                      : f.evidence.validity?.toWire().toText(),
                );
                expect(row.originalFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserAssertionCorrectionFormRecoveryStore.open(
              databaseName: name,
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
              store = await BrowserAssertionCorrectionFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.copyWith(rationale: '\ufeffReplacement').toWire().toText(),
                );
              }
              final db = await openDatabase(name, table);
              try {
                expect(db.version, 2);
                for (final (s, f) in forms) {
                  final row = await _read(db, table, s);
                  expect(row.original, isNull);
                  expect(row.validity, isNull);
                  expect(row.originalFields, isNotNull);
                  expect(
                    decodeBrowserInput(row.evidence!).toText(),
                    f.evidence.toWire().toText(),
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
