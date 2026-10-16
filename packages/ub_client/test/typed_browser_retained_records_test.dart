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
    final db = request.result as web.IDBDatabase;
    for (final table in tables) {
      db.createObjectStore(table);
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

Future<void> cleanup(String name) async {
  final done = Completer<void>(),
      request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Cleanup failed'),
  )).toJS;
  await done.future;
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

Future<void> seed(
  String name,
  List<String> tables,
  List<
    (
      EditorFormScope,
      Map<String, Object?>,
      List<Map<String, Object?>>,
      List<Map<String, Object?>>,
    )
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
    for (final (s, main, first, second) in rows) {
      tx.objectStore(tables[0]).put(main.jsify()!, key(s).toJS);
      for (final (table, children) in [
        (tables[1], first),
        (tables[2], second),
      ]) {
        for (var i = 0; i < children.length; i++) {
          tx
              .objectStore(table)
              .put(
                {'ordinal': i, ...children[i]}.jsify()!,
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

void main() {
  for (final malformed in [false, true]) {
    test(
      'browser secret originals ${malformed ? 'roll back without disturbing entered references' : 'retain nested validity, disclosure and null distinctions'}',
      () async {
        final name = 'ub-secret-retained-${OperationId.generate().value}',
            tables = ['secret_form', 'secret_scope', 'secret_knowers'];
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
                        fictionalKnowers: [
                          RecordRef(record: RecordId.generate()),
                        ],
                        readerDisclosed: validity is UnknownValidity,
                        concealment: validity is UnspecifiedValidity
                            ? null
                            : '',
                        validity: validity,
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
                'concealment': f.concealment,
                'validityKind': f.validityKind,
                'calendar': f.calendar,
                'start': f.start,
                'end': f.end,
                'rationale': f.rationale,
                'hasConcealment': f.hasConcealment,
                'startUnbounded': f.startUnbounded,
                'endUnbounded': f.endUnbounded,
                'readerDisclosed': f.readerDisclosed,
                'draftVersion': f.draftVersion?.toString(),
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
              },
              [
                for (final ref in f.scope)
                  <String, Object?>{
                    'record': ref.record,
                    'universe': ref.universe,
                  },
              ],
              [
                for (final ref in f.fictionalKnowers)
                  <String, Object?>{
                    'record': ref.record,
                    'universe': ref.universe,
                  },
              ],
            ),
        ];
        await seed(name, tables, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserSecretFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name, tables);
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
            var store = await BrowserSecretFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(
                  s,
                  f.copyWith(concealment: '\ufeffReplacement', scope: []),
                  saved.generation,
                );
              }
              store.close();
              store = await BrowserSecretFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f
                      .copyWith(concealment: '\ufeffReplacement', scope: [])
                      .toWire()
                      .toText(),
                );
              }
              final db = await openDatabase(name, tables);
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
          await cleanup(name);
        }
      },
    );
    test(
      'browser appearance originals ${malformed ? 'roll back without disturbing image and link rows' : 'retain targets, ordered media and nested validity'}',
      () async {
        final name = 'ub-appearance-retained-${OperationId.generate().value}',
            tables = ['appearance_form', 'appearance_image', 'appearance_link'];
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
        final rows = [
          for (final (s, f) in forms)
            (
              s,
              <String, Object?>{
                'generation': '9007199254740993',
                'baseRevision': f.baseRevision.value,
                'representedContext': f.representedContext.value,
                'clientRef': f.clientRef,
                'targetKind': f.targetKind,
                'targetEntry': f.target.record,
                'targetOwner': f.target.universe,
                'label': f.label,
                'physicalDescription': f.physicalDescription,
                'atmosphere': f.atmosphere,
                'validityKind': f.validityKind,
                'calendar': f.calendar,
                'start': f.start,
                'end': f.end,
                'startUnbounded': f.startUnbounded,
                'endUnbounded': f.endUnbounded,
                'rationale': f.rationale,
                'draftVersion': f.draftVersion?.toString(),
                'original': malformed && f == forms.last.$2
                    ? '{unfinished'
                    : f.original?.toWire().toText(),
              },
              [
                for (final i in f.images)
                  <String, Object?>{
                    'record': i.asset.record,
                    'universe': i.asset.universe,
                    'caption': i.caption,
                    'purpose': i.purpose,
                    'preview': i.preview,
                  },
              ],
              [
                for (final l in f.links)
                  <String, Object?>{
                    'record': l.entry.record,
                    'universe': l.entry.universe,
                    'relationship': l.relationship,
                    'note': l.note,
                  },
              ],
            ),
        ];
        await seed(name, tables, rows);
        try {
          if (malformed) {
            await expectLater(
              BrowserAppearanceFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name, tables);
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
            var store = await BrowserAppearanceFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(
                  s,
                  f.copyWith(images: [], label: '\ufeffReplacement'),
                  saved.generation,
                );
              }
              store.close();
              store = await BrowserAppearanceFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f
                      .copyWith(images: [], label: '\ufeffReplacement')
                      .toWire()
                      .toText(),
                );
              }
              final db = await openDatabase(name, tables);
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
          await cleanup(name);
        }
      },
    );
  }
}
