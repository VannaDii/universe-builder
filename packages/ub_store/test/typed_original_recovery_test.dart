@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/src/ownership.dart';

const legacySchemas = {
  'story_time': r'''CREATE TABLE story_time_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, value TEXT NOT NULL, mode TEXT NOT NULL, reason TEXT NOT NULL, rationale TEXT NOT NULL,
 target_record TEXT NOT NULL, target_universe TEXT NOT NULL, expected_record_version TEXT NOT NULL, original TEXT NOT NULL, draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=1;
''',
  'secret': r'''CREATE TABLE secret_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 reader_disclosed INTEGER CHECK(reader_disclosed IN (0,1)), has_concealment INTEGER NOT NULL CHECK(has_concealment IN (0,1)),
 concealment TEXT NOT NULL, validity_kind TEXT NOT NULL, calendar TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL,
 start_unbounded INTEGER NOT NULL CHECK(start_unbounded IN (0,1)), end_unbounded INTEGER NOT NULL CHECK(end_unbounded IN (0,1)),
 rationale TEXT NOT NULL, target_record TEXT, target_universe TEXT, expected_record_version TEXT, original TEXT, draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE secret_reference (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('scope','fictional_knowers')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), record_input TEXT NOT NULL, universe_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES secret_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=1;
''',
  'appearance': r'''CREATE TABLE appearance_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 target_kind TEXT NOT NULL, target_entry TEXT NOT NULL, target_owner TEXT NOT NULL,
 label TEXT NOT NULL, physical_description TEXT NOT NULL, atmosphere TEXT NOT NULL,
 validity_kind TEXT NOT NULL, calendar TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL,
 start_unbounded INTEGER NOT NULL CHECK(start_unbounded IN (0,1)), end_unbounded INTEGER NOT NULL CHECK(end_unbounded IN (0,1)),
 rationale TEXT NOT NULL, target_record TEXT, target_universe TEXT, expected_record_version TEXT, original TEXT, draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE appearance_image (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), asset_record TEXT NOT NULL, asset_universe TEXT NOT NULL,
 caption TEXT NOT NULL, purpose TEXT NOT NULL, preview TEXT NOT NULL,
 staged_ref TEXT, digest TEXT, media_type TEXT, byte_size TEXT, width INTEGER, height INTEGER, original_name TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES appearance_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE appearance_link (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), entry_record TEXT NOT NULL, entry_universe TEXT NOT NULL, relationship TEXT NOT NULL, note TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES appearance_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=1;
''',
};
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
void legacy(
  String kind,
  String path,
  List<(EditorFormScope, dynamic, BigInt)> forms, {
  bool broken = false,
}) {
  final seedPath = '$path.seed';
  final dynamic seed = open(kind, seedPath);
  for (final (s, form, _) in forms) {
    seed.save(s, form, BigInt.zero);
  }
  seed.close();
  final source = sqlite3.open(seedPath, mode: OpenMode.readOnly);
  protectedFile(path, create: true);
  final target = sqlite3.open(path);
  try {
    target.execute(legacySchemas[kind]!);
    final tables = [
      '${kind}_form',
      if (kind == 'secret') 'secret_reference',
      if (kind == 'appearance')
        ...'appearance_image,appearance_link'.split(','),
    ];
    for (final table in tables) {
      final columns = source.select('PRAGMA table_info($table)');
      final projection = columns
          .map(
            (c) => c['type'] == 'TEXT'
                ? 'CAST("${c['name']}" AS BLOB) AS "${c['name']}"'
                : '"${c['name']}"',
          )
          .join(',');
      for (final row in source.select('SELECT $projection FROM $table')) {
        final values = <Object?>[
          for (final c in columns)
            row[c['name']] is List<int>
                ? decodeExactUtf8(row[c['name']] as List<int>)
                : row[c['name']],
        ];
        if (table == '${kind}_form') {
          final entry = forms.singleWhere(
            (e) =>
                e.$1.profile.value ==
                decodeExactUtf8(row['profile'] as List<int>),
          );
          values[columns.indexWhere((c) => c['name'] == 'generation')] = entry
              .$3
              .toString();
          values[columns.indexWhere(
            (c) => c['name'] == 'original',
          )] = broken && entry.$1 == forms.last.$1
              ? '{unfinished'
              : entry.$2.original?.toWire().toText();
        }
        target.execute(
          'INSERT INTO $table VALUES(${List.filled(values.length, '?').join(',')})',
          values,
        );
      }
    }
  } finally {
    target.close();
    source.close();
  }
}

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
    test(
      '$kind converts legacy text snapshots without changing input, recovery slots or generations',
      () {
        final root = Directory('/tmp')
                .createTempSync('ub-original-$kind-conversion-'),
            s = scope(),
            second = scope();
        final path = '${root.path}/forms.sqlite';
        final dynamic form = input(kind, s), other = input(kind, second);
        legacy(kind, path, [
          (s, form, BigInt.from(19)),
          (second, other, maxU64),
        ]);
        final dynamic store = open(kind, path), competing = open(kind, path);
        try {
          expect(store.load(s).form.toWire().toText(), form.toWire().toText());
          expect(
            store.load(second).form.toWire().toText(),
            other.toWire().toText(),
          );
          final dynamic changed = input(kind, s, empty: true);
          expect(
            store.save(s, changed, BigInt.from(19)).generation,
            BigInt.from(20),
          );
          expect(
            store.save(s, changed, BigInt.from(19)).generation,
            BigInt.from(20),
          );
          expect(
            () => competing.save(s, form, BigInt.from(19)),
            throwsA(
              isA<EditorRecoveryException>().having(
                (e) => e.failure,
                'failure',
                EditorRecoveryFailure.conflict,
              ),
            ),
          );
          expect(
            () => store.save(second, other, maxU64),
            throwsA(
              isA<EditorRecoveryException>().having(
                (e) => e.failure,
                'failure',
                EditorRecoveryFailure.generationExhausted,
              ),
            ),
          );
          expect(
            store.load(second).form.toWire().toText(),
            other.toWire().toText(),
          );
        } finally {
          competing.close();
          store.close();
          root.deleteSync(recursive: true);
        }
      },
    );
    test(
      '$kind malformed legacy original rolls back all typed snapshots and keeps the old fields and child rows',
      () {
        final root = Directory('/tmp')
                .createTempSync('ub-original-$kind-rollback-'),
            s = scope(),
            second = scope();
        final path = '${root.path}/forms.sqlite';
        final dynamic form = input(kind, s), other = input(kind, second);
        legacy(kind, path, [
          (s, form, BigInt.one),
          (second, other, BigInt.two),
        ], broken: true);
        try {
          expect(
            () => open(kind, path),
            throwsA(isA<EditorRecoveryException>()),
          );
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(db.select('PRAGMA user_version').single.values.single, 1);
            expect(
              db
                  .select(
                    'SELECT original FROM ${kind}_form ORDER BY generation',
                  )
                  .map((r) => r['original']),
              [form.original.toWire().toText(), '{unfinished'],
            );
            expect(
              db.select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'r_%'",
              ),
              isEmpty,
            );
            expect(db.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            db.close();
          }
        } finally {
          root.deleteSync(recursive: true);
        }
      },
    );
  }
}
