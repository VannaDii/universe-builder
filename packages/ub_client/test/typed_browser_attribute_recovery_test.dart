@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_attribute_recovery.dart';
import 'package:ub_client/src/browser_input_fields.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

@JS()
extension type _StoredRow._(JSObject _) implements JSObject {
  external String? get validity;
  external JSAny? get evidence;
}

List<JSAny> key(EditorFormScope s) => [
  s.instance.value.toJS,
  s.profile.value.toJS,
  s.universe.value.toJS,
  s.continuity.value.toJS,
  s.representedContext!.value.toJS,
  s.attributeClientRef!.toJS,
];
Future<web.IDBDatabase> openDatabase(String name, [int? version]) async {
  final done = Completer<web.IDBDatabase>(),
      request = version == null
          ? web.window.indexedDB.open(name)
          : web.window.indexedDB.open(name, version);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore('attribute_form');
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
  List<(EditorFormScope, UnfinishedAttributeForm)> forms,
  bool malformed,
) async {
  final db = await openDatabase(name, 1);
  try {
    final done = Completer<void>(),
        tx = db.transaction('attribute_form'.toJS, 'readwrite');
    tx.oncomplete = ((web.Event _) => done.complete()).toJS;
    tx.onabort = ((web.Event _) => done.completeError(
      StateError('Fixture save failed'),
    )).toJS;
    for (final (s, f) in forms) {
      tx
          .objectStore('attribute_form')
          .put(
            {
              'generation': '9007199254740993',
              'baseRevision': f.baseRevision.value,
              'representedContext': f.representedContext.value,
              'clientRef': f.clientRef,
              'draftVersion': f.draftVersion.toString(),
              'value': encodeBrowserInput(f.value.toWire()),
              'evidence': f.evidenceInput == null
                  ? null
                  : encodeBrowserInput(
                      CanonicalObject(
                        f.evidenceInput!.toWire().fields.where(
                          (field) => field.key != 'validity',
                        ),
                      ),
                    ),
              'validity': malformed && f == forms.last.$2
                  ? '{unfinished'
                  : f.evidenceInput?.validity?.toWire().toText(),
              'creation': f.creationInput == null
                  ? null
                  : encodeBrowserInput(f.creationInput!.toWire()),
              'roles': f.roles == null
                  ? null
                  : encodeBrowserInput(
                      CanonicalArray(f.roles!.map((r) => r.toWire())),
                    ),
            }.jsify()!,
            key(s).toJS,
          );
    }
    await done.future;
  } finally {
    db.close();
  }
}

Future<_StoredRow> _read(web.IDBDatabase db, EditorFormScope s) async {
  final done = Completer<_StoredRow>(),
      tx = db.transaction('attribute_form'.toJS, 'readonly'),
      request = tx.objectStore('attribute_form').get(key(s).toJS);
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
      'browser attribute upgrade ${malformed ? 'rolls back evidence and other fields' : 'preserves complete evidence, creation bindings and roles'}',
      () async {
        final name = 'ub-attribute-typed-${OperationId.generate().value}',
            calendar = CalendarId.generate();
        final validity = CalendarIntervalValidity(
          calendar,
          ApproximateBound(
            '\ufeffStart',
            SequenceValue([
              const IntegerValue('9007199254740993123456789'),
              TextValue('\ufeffAmount\r\n\u0000😀'),
            ]),
          ),
          const UnboundedBound(),
        );
        final forms = [
          for (var i = 0; i < 4; i++)
            (() {
              final s = EditorFormScope(
                instance: OperationId.generate(),
                profile: ProfileId.generate(),
                universe: UniverseId.generate(),
                continuity: ContinuityId.generate(),
                representedContext: RecordId.generate(),
                attributeClientRef: '\ufeffAttribute',
              );
              final f = UnfinishedAttributeForm(
                baseRevision: RevisionId.generate(),
                representedContext: s.representedContext!,
                clientRef: s.attributeClientRef!,
                draftVersion: (BigInt.one << 64) - BigInt.one,
                value: const QualifierInput(
                  kind: 'sequence',
                  originalKey: '',
                  children: [
                    QualifierInput(value: '\ufeffChild\r\n\u0000😀'),
                    QualifierInput(),
                  ],
                ),
                evidenceInput: i == 0
                    ? null
                    : i == 1
                    ? const AttributeEvidenceInput()
                    : AttributeEvidenceInput(
                        validity: validity,
                        basis: const EvidenceBasisInput(
                          kind: 'source',
                          verified: false,
                          note: '\ufeffNote',
                        ),
                        scope: const ScopeInput(
                          applicability: 'worlds',
                          worlds: ['', 'world', 'world'],
                        ),
                        alternatives: const [
                          QualifierInput(),
                          QualifierInput(value: '\ufeffAlternative'),
                        ],
                        temporalValidity: const TemporalValidityInput(
                          kind: 'unfinished',
                        ),
                      ),
                creationInput: AttributeCreationInput(
                  subject: VersionRef(
                    record: RecordId.generate(),
                    version: RecordVersionId.generate(),
                    universe: s.universe,
                  ),
                  operationRef: '\ufeffOperation',
                  propertyRecord: '\ufeffProperty',
                  relationship: true,
                ),
                roles: i == 0
                    ? null
                    : i == 1
                    ? []
                    : const [
                        PropositionRoleInput(role: '\ufeffRole'),
                        PropositionRoleInput(),
                      ],
              );
              return (s, f);
            })(),
        ];
        await seed(name, forms, malformed);
        try {
          if (malformed) {
            await expectLater(
              BrowserAttributeFormRecoveryStore.open(databaseName: name),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(name);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, s);
                expect(
                  row.validity,
                  f == forms.last.$2
                      ? '{unfinished'
                      : f.evidenceInput?.validity?.toWire().toText(),
                );
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserAttributeFormRecoveryStore.open(
              databaseName: name,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, f, saved.generation);
              }
              store.close();
              store = await BrowserAttributeFormRecoveryStore.open(
                databaseName: name,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  f.toWire().toText(),
                );
              }
              final db = await openDatabase(name);
              try {
                expect(db.version, 2);
                for (final (s, f) in forms) {
                  final row = await _read(db, s);
                  expect(row.validity, isNull);
                  expect(
                    row.evidence == null
                        ? null
                        : decodeBrowserInput(row.evidence!).toText(),
                    f.evidenceInput?.toWire().toText(),
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
