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
);
dynamic open(String kind, String path) => switch (kind) {
  'story_time' => StoryTimeFormRecoveryStore.open(path),
  'secret' => SecretFormRecoveryStore.open(path),
  'appearance' => AppearanceFormRecoveryStore.open(path),
  _ => throw StateError('Unknown form'),
};
dynamic input(String kind, EditorFormScope s, {bool empty = false}) {
  final base = RevisionId.generate(),
      ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      calendar = CalendarId.generate();
  final validity = InstantValidity(
    DurationTime(
      calendar,
      SequenceValue([
        const RationalValue('9007199254740997', '3'),
        const TextValue('\ufeffLifetime'),
      ]),
    ),
  );
  switch (kind) {
    case 'story_time':
      return UnfinishedStoryTimeForm(
        baseRevision: base,
        representedContext: s.representedContext!,
        target: const ExpressionReferenceInput(
          record: '\ufeffPending context',
          universe: '',
        ),
        expectedRecordVersion: RecordVersionId.generate(),
        original: Chronology(
          calendar: calendar,
          system: empty
              ? FictionalClock('\ufeffTick', null)
              : GregorianClock(-2147483648),
          firstInteraction: '\ufeffFirst',
          current: '\ufeffCurrent',
        ),
        value: empty ? '' : '\ufeffPending time',
        mode: 'undecided',
        reason: '\ufeffReason\r\n\u0000😀',
        rationale: '\ufeffRationale',
        draftVersion: empty ? null : maxU64,
      );
    case 'secret':
      return empty
          ? UnfinishedSecretForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: '\ufeffPending secret',
            )
          : UnfinishedSecretForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: '\ufeffPending secret',
              scope: const [
                ExpressionReferenceInput(record: '\ufeffScope'),
                ExpressionReferenceInput(),
                ExpressionReferenceInput(record: '\ufeffScope'),
              ],
              fictionalKnowers: const [
                ExpressionReferenceInput(record: '\ufeffKnower'),
                ExpressionReferenceInput(record: '\ufeffKnower'),
              ],
              readerDisclosed: false,
              hasConcealment: false,
              concealment: '\ufeffDisabled concealment',
              validityKind: 'undecided',
              calendar: '\ufeffCalendar',
              start: '\ufeffStart',
              end: '\ufeffEnd',
              startUnbounded: true,
              endUnbounded: true,
              rationale: '\ufeffReason\r\n\u0000😀',
              revisionTarget: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffPending universe',
              ),
              expectedRecordVersion: RecordVersionId.generate(),
              draftVersion: maxU64,
              original: SecretRecord(
                scope: [
                  ref,
                  ref,
                  RecordRef(record: ref.record),
                ],
                fictionalKnowers: [ref, ref],
                readerDisclosed: false,
                concealment: '\ufeffOriginal concealment\r\n\u0000😀',
                validity: validity,
              ),
            );
    case 'appearance':
      if (empty) {
        return UnfinishedAppearanceForm(
          baseRevision: base,
          representedContext: s.representedContext!,
          clientRef: '\ufeffPending appearance',
        );
      }
      final image = AppearanceImageInput(
        asset: const ExpressionReferenceInput(
          record: '\ufeffPending image',
          universe: '',
        ),
        caption: '\ufeffCaption',
        purpose: 'undecided',
        stagedOperation: AddImageAssetOperation(
          clientRef: '\ufeffStaged image',
          record: ImageAssetRecord(
            contentDigest: 'sha256:${'a'.padLeft(64, 'a')}',
            mediaType: 'image/png',
            byteSize: maxU64,
            width: 4294967295,
            height: 1,
            originalName: '\ufeffImage 記憶.png',
          ),
        ),
      );
      const link = AppearanceLinkInput(
        entry: ExpressionReferenceInput(record: '\ufeffPending link'),
        relationship: 'undecided',
        note: '\ufeffNote\r\n\u0000😀',
      );
      return UnfinishedAppearanceForm(
        baseRevision: base,
        representedContext: s.representedContext!,
        clientRef: '\ufeffPending appearance',
        targetKind: 'undecided',
        target: const ExpressionReferenceInput(
          record: '',
          universe: '\ufeffTarget universe',
        ),
        label: '\ufeffLabel',
        physicalDescription: '\ufeffDescription',
        atmosphere: '\ufeffAtmosphere',
        images: [image, const AppearanceImageInput(), image],
        links: const [link, AppearanceLinkInput(), link],
        validityKind: 'undecided',
        calendar: '\ufeffCalendar',
        start: '\ufeffStart',
        end: '\ufeffEnd',
        startUnbounded: true,
        endUnbounded: true,
        rationale: '\ufeffReason\r\n\u0000😀',
        revisionTarget: const ExpressionReferenceInput(
          record: '',
          universe: '\ufeffPending universe',
        ),
        expectedRecordVersion: RecordVersionId.generate(),
        draftVersion: maxU64,
        original: AppearanceRecord(
          target: EntryAppearance(ref),
          label: '\ufeffOriginal label',
          physicalDescription: '\ufeffOriginal description',
          atmosphere: '\ufeffOriginal atmosphere',
          images: [
            AppearanceImage(
              asset: ref,
              caption: '\ufeffOriginal caption',
              purpose: ImagePurpose.detail,
            ),
            AppearanceImage(
              asset: ref,
              caption: '',
              purpose: ImagePurpose.inspiration,
            ),
          ],
          links: [
            AppearanceLink(
              entry: ref,
              relationship: AppearanceRelationship.contrasts,
              note: '\ufeffNote',
            ),
            AppearanceLink(
              entry: RecordRef(record: ref.record),
              relationship: AppearanceRelationship.detailOf,
              note: '',
            ),
          ],
          validity: validity,
        ),
      );
    default:
      throw StateError('Unknown form');
  }
}

Map<String, int> domainCounts(Database db) => {
  for (final r in db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'r_%'",
  ))
    r['name'] as String:
        db.select('SELECT count(*) AS n FROM "${r['name']}"').single['n']
            as int,
};
// Produce the prior named-field schema with original domain snapshots as text.

void main() {
  for (final kind in ['story_time', 'secret', 'appearance']) {
    test(
      '$kind retains typed originals and exact authored fields including staged image metadata after restart',
      () {
        final root = Directory('/tmp')
                .createTempSync('ub-typed-original-$kind-'),
            s = scope();
        final path = '${root.path}/forms.sqlite';
        final dynamic form = input(kind, s);
        dynamic store = open(kind, path);
        try {
          store.save(s, form, BigInt.zero);
          store.close();
          store = open(kind, path);
          expect(store.load(s).form.toWire().toText(), form.toWire().toText());
          expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
          var db = sqlite3.open(path, mode: OpenMode.readOnly);
          late Map<String, int> counts;
          try {
            counts = domainCounts(db);
          } finally {
            db.close();
          }
          store.save(s, form, BigInt.one);
          db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(domainCounts(db), counts);
            expect(
              db
                  .select('PRAGMA table_info(${kind}_form)')
                  .singleWhere((r) => r['name'] == 'original')['type'],
              'INTEGER',
            );
            expect(db.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            db.close();
          }
          final dynamic empty = input(kind, s, empty: true);
          store.save(s, empty, BigInt.two);
          store.close();
          store = open(kind, path);
          expect(store.load(s).form.toWire().toText(), empty.toWire().toText());
          if (kind != 'story_time') {
            db = sqlite3.open(path, mode: OpenMode.readOnly);
            try {
              expect(domainCounts(db).values, everyElement(0));
            } finally {
              db.close();
            }
          }
        } finally {
          store.close();
          root.deleteSync(recursive: true);
        }
      },
    );
  }
}
