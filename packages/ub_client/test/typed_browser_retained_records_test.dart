@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_secret_recovery.dart';
import 'package:ub_client/browser_appearance_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

Future<void> cleanup(String name) async {
  final done = Completer<void>(),
      request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Cleanup failed'),
  )).toJS;
  await done.future;
}

EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
);

List<Validity?> validities() {
  final calendar = CalendarId.generate();
  final amount = SequenceValue([
    const RationalValue('900719925474099312345', '7'),
    TextValue('\ufeffAmount\r\n\u0000😀'),
  ]);
  return [
    null,
    const UnspecifiedValidity(),
    const UnknownValidity(),
    const ConditionalValidity(),
    InstantValidity(ApproximateTime(calendar, '\ufeffCoordinate', amount)),
    IntervalValidity(
      ApproximateBound('\ufeffStart', amount),
      const UncertainBound('', '\ufeffEnd'),
    ),
    CalendarIntervalValidity(
      calendar,
      const UnboundedBound(),
      const UnknownBound(),
    ),
    const PersistentValidity(ExactBound('\ufeffFrom')),
  ];
}

void main() {
  test('browser secret recovery retains nested original records and exact input across reopening', () async {
    final name = 'ub-secret-current-${OperationId.generate().value}';
    final forms = [
      for (final validity in validities())
        (() {
          final s = scope(),
              ref = RecordRef(
                record: RecordId.generate(),
                universe: UniverseId.generate(),
              );
          final f = UnfinishedSecretForm(
            baseRevision: RevisionId.generate(),
            representedContext: s.representedContext!,
            clientRef: '\ufeffSecret',
            concealment: '\ufeffPending\r\n\u0000😀',
            readerDisclosed: validity == null ? null : false,
            hasConcealment: true,
            scope: const [
              ExpressionReferenceInput(record: '\ufeffScope'),
              ExpressionReferenceInput(),
            ],
            fictionalKnowers: const [
              ExpressionReferenceInput(record: '\ufeffKnower'),
              ExpressionReferenceInput(record: '\ufeffKnower'),
            ],
            draftVersion: (BigInt.one << 64) - BigInt.one,
            original: validity == null
                ? null
                : SecretRecord(
                    scope: [ref, ref],
                    fictionalKnowers: [RecordRef(record: RecordId.generate())],
                    readerDisclosed: validity is UnknownValidity,
                    concealment: validity is UnspecifiedValidity ? null : '',
                    validity: validity,
                  ),
          );
          return (s, f);
        })(),
    ];

    var store = await BrowserSecretFormRecoveryStore.open(databaseName: name);
    try {
      for (final (scope, form) in forms) {
        await store.save(scope, form, BigInt.zero);
      }
      store.close();
      store = await BrowserSecretFormRecoveryStore.open(databaseName: name);
      for (final (scope, form) in forms) {
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          form.toWire().toText(),
        );
        expect(
          (await store.save(scope, form, BigInt.zero)).generation,
          BigInt.one,
        );
        await expectLater(
          store.save(scope, form, BigInt.two),
          throwsA(isA<EditorRecoveryException>()),
        );
      }
    } finally {
      store.close();
      await cleanup(name);
    }
  });
  test('browser appearance recovery retains nested original records and exact input across reopening', () async {
    final name = 'ub-appearance-current-${OperationId.generate().value}';
    final forms = [
      for (final validity in validities())
        (() {
          final s = scope(),
              ref = RecordRef(
                record: RecordId.generate(),
                universe: UniverseId.generate(),
              );
          final original = validity == null
              ? null
              : AppearanceRecord(
                  target: validity is UnknownValidity
                      ? const UniverseAppearance()
                      : EntryAppearance(ref),
                  label: '\ufeffLabel\r\n\u0000😀',
                  physicalDescription: '',
                  atmosphere: '\ufeffAtmosphere',
                  images: [
                    AppearanceImage(
                      asset: ref,
                      caption: '\ufeffCaption',
                      purpose: ImagePurpose.inspiration,
                    ),
                    AppearanceImage(
                      asset: ref,
                      caption: '',
                      purpose: ImagePurpose.detail,
                    ),
                  ],
                  links: [
                    AppearanceLink(
                      entry: ref,
                      relationship: AppearanceRelationship.detailOf,
                      note: '\ufeffNote',
                    ),
                  ],
                  validity: validity,
                );
          final f = UnfinishedAppearanceForm(
            baseRevision: RevisionId.generate(),
            representedContext: s.representedContext!,
            clientRef: '\ufeffAppearance',
            label: '\ufeffPending',
            images: const [
              AppearanceImageInput(caption: '\ufeffImage'),
              AppearanceImageInput(),
            ],
            links: const [
              AppearanceLinkInput(note: '\ufeffLink'),
              AppearanceLinkInput(),
            ],
            draftVersion: (BigInt.one << 64) - BigInt.one,
            original: original,
          );
          return (s, f);
        })(),
    ];

    var store = await BrowserAppearanceFormRecoveryStore.open(
      databaseName: name,
    );
    try {
      for (final (scope, form) in forms) {
        await store.save(scope, form, BigInt.zero);
      }
      store.close();
      store = await BrowserAppearanceFormRecoveryStore.open(databaseName: name);
      for (final (scope, form) in forms) {
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          form.toWire().toText(),
        );
        expect(
          (await store.save(scope, form, BigInt.zero)).generation,
          BigInt.one,
        );
        await expectLater(
          store.save(scope, form, BigInt.two),
          throwsA(isA<EditorRecoveryException>()),
        );
      }
    } finally {
      store.close();
      await cleanup(name);
    }
  });
}
