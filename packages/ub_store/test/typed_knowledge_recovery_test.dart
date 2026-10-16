@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending knowledge input',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
const pendingTime = TemporalValidityInput(
  kind: 'pending',
  calendar: '\ufeffCalendar',
  relation: 'before?',
  targetRecord: 'disabled target',
  start: TemporalBoundInput(
    kind: 'unknown',
    value: 'disabled start',
    upper: '\ufeffUpper',
    amount: QualifierInput(kind: 'rational', value: '3', denominator: '0'),
  ),
);
const reason = '\ufeffReason\r\n\u0000記憶😀';
dynamic open(String kind, String path) => switch (kind) {
  'communication' => CommunicationFormRecoveryStore.open(path),
  'observation' => ObservationFormRecoveryStore.open(path),
  'memory' => MemoryFormRecoveryStore.open(path),
  _ => throw StateError('Unknown form'),
};
dynamic input(
  String kind,
  EditorFormScope s, {
  bool empty = false,
  bool? flag = false,
}) {
  final base = RevisionId.generate(),
      ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      calendar = CalendarId.generate();
  final time = ApproximateTime(
    calendar,
    '\ufeffCoordinate',
    SequenceValue([
      const RationalValue('9007199254740997', '3'),
      const TextValue('\ufeffUncertainty'),
    ]),
  );
  switch (kind) {
    case 'communication':
      return empty
          ? UnfinishedCommunicationForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              distorted: flag,
            )
          : UnfinishedCommunicationForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              sender: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffSender universe',
              ),
              intendedRecipients: const [
                ExpressionReferenceInput(record: '\ufeffRecipient'),
                ExpressionReferenceInput(),
                ExpressionReferenceInput(record: '\ufeffRecipient'),
              ],
              actualRecipients: const [
                ExpressionReferenceInput(record: '\ufeffActual'),
                ExpressionReferenceInput(record: '\ufeffActual'),
              ],
              content: const [
                ExpressionReferenceInput(),
                ExpressionReferenceInput(record: '\ufeffContent'),
              ],
              channelEnabled: false,
              channel: '\ufeffDisabled channel',
              distorted: flag,
              sentAt: pendingTime,
              receivedEnabled: false,
              receivedAt: pendingTime,
              rationale: reason,
              draftVersion: maxU64,
              correctionTarget: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffPending target universe',
              ),
              expectedRecordVersion: RecordVersionId.generate(),
              original: CommunicationRecord(
                sender: ref,
                intendedRecipients: [
                  ref,
                  ref,
                  RecordRef(record: ref.record),
                ],
                actualRecipients: [ref, ref],
                content: [ref, ref],
                channel: flag == true ? '' : null,
                sentAt: time,
                receivedAt: flag == true
                    ? ExactTime(calendar, '\ufeffReceived')
                    : null,
                distorted: flag ?? false,
              ),
            );
    case 'observation':
      return empty
          ? UnfinishedObservationForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              sensoryAccess: flag,
            )
          : UnfinishedObservationForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              observer: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffObserver universe',
              ),
              observed: const ExpressionReferenceInput(
                record: '\ufeffObserved',
                universe: '',
              ),
              sensoryAccess: flag,
              time: pendingTime,
              interpretationEnabled: false,
              interpretation: const ExpressionReferenceInput(
                record: 'disabled interpretation',
                universe: 'disabled universe',
              ),
              basis: const EvidenceBasisInput(
                kind: 'pending',
                note: '\ufeffNote\r\n\u0000😀',
                anchorRecord: '',
                anchorUniverse: 'disabled',
                verified: true,
              ),
              rationale: reason,
              draftVersion: maxU64,
              original: ObservationRecord(
                observer: ref,
                observed: RecordRef(record: ref.record),
                sensoryAccess: flag ?? false,
                time: time,
                interpretation: flag == true ? ref : null,
                basis: DerivationBasis([
                  VersionRef(
                    record: ref.record,
                    version: RecordVersionId.generate(),
                    universe: s.universe,
                  ),
                ], '\ufeffEvaluator'),
              ),
            );
    case 'memory':
      return empty
          ? UnfinishedMemoryForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              altered: flag,
            )
          : UnfinishedMemoryForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              holder: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffHolder universe',
              ),
              content: const ExpressionReferenceInput(
                record: '\ufeffRemembered',
                universe: '',
              ),
              altered: flag,
              validity: pendingTime,
              allegedEnabled: false,
              alleged: const ExpressionReferenceInput(
                record: 'disabled alleged',
                universe: 'disabled universe',
              ),
              accessibility: '\ufeffAccessibility',
              rationale: reason,
              draftVersion: maxU64,
              original: MemoryRecord(
                holder: ref,
                content: RecordRef(record: ref.record),
                alleged: flag == true ? ref : null,
                accessibility: '\ufeffOriginal accessibility\r\n\u0000😀',
                altered: flag ?? false,
                validity: InstantValidity(time),
              ),
            );
    default:
      throw StateError('Unknown form');
  }
}

void main() {
  for (final kind in ['communication', 'observation', 'memory']) {
    test(
      '$kind typed recovery retains disabled inputs and original records while preserving unset versus explicit boolean choices',
      () {
        final root = Directory('/tmp').createTempSync('ub-typed-$kind-'),
            s = scope();
        final path = '${root.path}/forms.sqlite';
        dynamic store = open(kind, path);
        var generation = BigInt.zero;
        try {
          for (final flag in <bool?>[null, false, true]) {
            final dynamic form = input(kind, s, flag: flag);
            generation = store.save(s, form, generation).generation as BigInt;
            store.close();
            store = open(kind, path);
            expect(
              store.load(s).form.toWire().toText(),
              form.toWire().toText(),
            );
            expect(
              store.save(s, form, generation - BigInt.one).generation,
              generation,
            );
          }
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(
              db
                  .select('PRAGMA table_info(${kind}_form)')
                  .map((r) => r['name']),
              isNot(contains('form_input')),
            );
            expect(db.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            db.close();
          }
        } finally {
          store.close();
          root.deleteSync(recursive: true);
        }
      },
    );
    test(
      '$kind replacement removes superseded original records and nested inputs',
      () {
        final root = Directory('/tmp').createTempSync('ub-$kind-clear-'),
            s = scope();
        final path = '${root.path}/forms.sqlite';
        final dynamic form = input(kind, s),
            empty = input(kind, s, empty: true);
        dynamic store = open(kind, path);
        try {
          store.save(s, form, BigInt.zero);
          store.save(s, form, BigInt.one);
          store.save(s, empty, BigInt.two);
          store.close();
          store = open(kind, path);
          expect(store.load(s).form.toWire().toText(), empty.toWire().toText());
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            final n = kind == 'communication' ? 2 : 1;
            for (final row in db.select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name!='${kind}_form'",
            )) {
              expect(
                db
                    .select('SELECT count(*) AS n FROM "${row['name']}"')
                    .single['n'],
                row['name'] == '${kind}_temporal'
                    ? n
                    : row['name'] == '${kind}_bound'
                    ? 2 * n
                    : 0,
                reason: row['name'] as String,
              );
            }
            expect(db.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            db.close();
          }
        } finally {
          store.close();
          root.deleteSync(recursive: true);
        }
      },
    );
  }
}
