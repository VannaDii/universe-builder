@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_rule_recovery.dart';
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

UnfinishedRuleForm _changedRule(UnfinishedRuleForm f) =>
    UnfinishedRuleForm.fromWire(
      CanonicalObject([
        ...f.toWire().fields.where((field) => field.key != 'rationale'),
        MapEntry('rationale', CanonicalString('\ufeffReplacement')),
      ]),
    );
void main() {
  for (final failure in [0, 1, 2]) {
    final malformed = failure != 0;
    test(
      'browser rule originals ${failure == 2 ? 'invalid bound ' : ''}${malformed ? 'roll back every old row' : 'retain nested records and nullable choices'}',
      () async {
        final database = 'ub-rule-typed-${OperationId.generate().value}',
            table = 'rule_form';
        final forms = [
          for (var i = 0; i < 4; i++)
            (() {
              final s = scope(), repeated = ref();
              final f = UnfinishedRuleForm(
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
                kind: 'unfinished',
                commitPolicy: 'unfinished',
                scope: const ScopeInput(
                  applicability: 'worlds',
                  worlds: ['world', '', 'world'],
                ),
                subjectTypes: const ['', '\ufeffType', '\ufeffType'],
                targetPredicates: const ['\ufeffPredicate', ''],
                capabilities: const [
                  '',
                  '\ufeffCapability',
                  '\ufeffCapability',
                ],
                expression: ExpressionInput(
                  kind: 'all',
                  items: [
                    ExpressionInput(),
                    ExpressionInput(kind: 'literal', flags: {'value': null}),
                  ],
                ),
                executable: i == 0
                    ? null
                    : i == 1
                    ? false
                    : true,
                validity: const TemporalValidityInput(kind: 'unfinished'),
                knowledge: i == 0
                    ? null
                    : const RuleKnowledgeInput(
                        policyEnabled: false,
                        boundaryEnabled: true,
                        mode: '\ufeffMode',
                      ),
                constraints: i == 0
                    ? null
                    : const RuleConstraintInput(
                        cardinalityEnabled: true,
                        maximum: '900719925474099312345',
                        chronologyEnabled: false,
                        maximumEnabled: false,
                        maximumDelay: '\ufeffDisabled',
                      ),
                evidence: i == 0
                    ? null
                    : RuleEvidenceInput(
                        enabled: false,
                        categories: [
                          RuleEvidenceCategoryInput(record: '\ufeffCategory'),
                        ],
                        reviewMethods: [
                          'external_model_review',
                          'external_model_review',
                        ],
                      ),
                revisionTarget: const ExpressionReferenceInput(
                  record: '\ufeffRevision',
                ),
                expectedRecordVersion: RecordVersionId.generate(),
                original: i == 0
                    ? null
                    : RuleRecord(
                        namespace: '\ufeffOriginal',
                        key: '\ufeffKey',
                        labels: {'': '', '\ufeffen': '\ufeffName\r\n\u0000😀'},
                        kind: RuleKind.descriptive,
                        commitPolicy: CommitPolicy.reportUnsupported,
                        applicability: const UniverseApplicability(),
                        subjectTypes: [repeated.record, repeated.record],
                        targetPredicates: ['', '\ufeffPredicate'],
                        expression: AllExpr([
                          const LiteralExpr(false),
                          CompareExpr(
                            ValueOperand(
                              RationalValue('900719925474099312345', '007'),
                            ),
                            Comparator.ltEq,
                            ValueOperand(IntegerValue('003')),
                          ),
                        ]),
                        capabilities: ['\ufeffCapability', '\ufeffCapability'],
                        executable: false,
                        validity: InstantValidity(time()),
                        requiredEvidence: i == 1
                            ? null
                            : RequiredEvidence(
                                sourceCategories: [
                                  VersionRef(
                                    record: repeated.record,
                                    version: RecordVersionId.generate(),
                                  ),
                                ],
                                reviewMethods: i == 2
                                    ? []
                                    : EvidenceReviewMethod.values,
                              ),
                        knowledgeBoundary: i == 1
                            ? null
                            : KnowledgeBoundary(
                                holder: repeated,
                                proposition: ref(),
                                context: ref(),
                              ),
                        knowledgePolicy: i == 1
                            ? null
                            : KnowledgePolicy(
                                context: ref(),
                                mode: KnowledgeMode.values.first,
                              ),
                        relationCardinality: i == 1
                            ? null
                            : RelationCardinality(
                                relation: ref(),
                                grouping: i == 2
                                    ? const SubjectCardinalityKey()
                                    : const RoleCardinalityKey('\ufeffRole'),
                                countedRole: '\ufeffRole',
                                maximum: i == 2 ? 0 : 4294967295,
                                scope: Scope(
                                  context: ref(),
                                  applicability: const UniverseApplicability(),
                                ),
                                validity: InstantValidity(time()),
                              ),
                        channelChronology: i == 1
                            ? null
                            : ChannelChronology(
                                channel: '\ufeffChannel',
                                forwardOnly: false,
                                minimumDelay: i == 2 ? null : '',
                                maximumDelay: '\ufeffDelay',
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
                'original': f == forms.last.$2 && failure == 1
                    ? '{unfinished'
                    : f == forms.last.$2 && failure == 2
                    ? f.original!.toWire().toText().replaceFirst(
                        '"maximum":4294967295',
                        '"maximum":4294967296',
                      )
                    : f.original?.toWire().toText(),
                'namespace': f.namespace,
                'key': f.key,
                'labels': encodeBrowserInput(
                  CanonicalArray(f.labels.map((l) => l.toWire())),
                ),
                'kind': f.kind,
                'commitPolicy': f.commitPolicy,
                'factualScope': encodeBrowserInput(f.scope.toWire()),
                'subjectTypes': f.subjectTypes,
                'targetPredicates': f.targetPredicates,
                'capabilities': f.capabilities,
                'expression': encodeBrowserInput(f.expression.toWire()),
                'executable': f.executable,
                'validity': encodeBrowserInput(f.validity.toWire()),
                'knowledge': f.knowledge == null
                    ? null
                    : encodeBrowserInput(f.knowledge!.toWire()),
                'constraints': f.constraints == null
                    ? null
                    : encodeBrowserInput(f.constraints!.toWire()),
                'evidence': f.evidence == null
                    ? null
                    : encodeBrowserInput(f.evidence!.toWire()),
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
              BrowserRuleFormRecoveryStore.open(databaseName: database),
              throwsA(isA<EditorRecoveryException>()),
            );
            final db = await openDatabase(database, table);
            try {
              expect(db.version, 1);
              for (final (s, f) in forms) {
                final row = await _read(db, table, s);
                expect(
                  row.original,
                  f == forms.last.$2 && failure == 1
                      ? '{unfinished'
                      : f == forms.last.$2 && failure == 2
                      ? f.original!.toWire().toText().replaceFirst(
                          '"maximum":4294967295',
                          '"maximum":4294967296',
                        )
                      : f.original?.toWire().toText(),
                );
                expect(row.originalFields, isNull);
              }
            } finally {
              db.close();
            }
          } else {
            var store = await BrowserRuleFormRecoveryStore.open(
              databaseName: database,
            );
            try {
              for (final (s, f) in forms) {
                final saved = (await store.load(s))!;
                expect(saved.generation, BigInt.parse('9007199254740993'));
                expect(saved.form.toWire().toText(), f.toWire().toText());
                await store.save(s, _changedRule(f), saved.generation);
              }
              store.close();
              store = await BrowserRuleFormRecoveryStore.open(
                databaseName: database,
              );
              for (final (s, f) in forms) {
                expect(
                  (await store.load(s))!.form.toWire().toText(),
                  _changedRule(f).toWire().toText(),
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
