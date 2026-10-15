@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/src/ownership.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending contextual input',
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
  targetRecord: 'disabled target',
  start: TemporalBoundInput(
    kind: 'unknown',
    value: 'disabled start',
    upper: '\ufeffUpper',
    amount: QualifierInput(kind: 'rational', value: '3', denominator: '0'),
  ),
);
const pendingScope = ScopeInput(
  applicability: 'undecided',
  worlds: ['\ufeffWorld', '', '\ufeffWorld'],
  contextRecord: '',
  contextUniverse: 'pending',
  hasRealm: false,
  realmRecord: 'disabled realm',
  realmUniverse: 'disabled universe',
);
const reason = '\ufeffReason\r\n\u0000記憶😀';
dynamic open(String kind, String path) => switch (kind) {
  'exception' => ExceptionFormRecoveryStore.open(path),
  'completeness' => CompletenessFormRecoveryStore.open(path),
  'boundary' => BoundaryFormRecoveryStore.open(path),
  _ => throw StateError('Unknown form'),
};
dynamic input(String kind, EditorFormScope s, {bool empty = false}) {
  final base = RevisionId.generate(),
      ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      world = WorldId.generate();
  final originalScope = Scope(
    context: ref,
    realm: RecordRef(record: ref.record),
    applicability: WorldsApplicability([world, world]),
  );
  final originalValidity = InstantValidity(
    DurationTime(
      CalendarId.generate(),
      SequenceValue([
        const RationalValue('9007199254740997', '3'),
        const TextValue('\ufeffLifetime'),
      ]),
    ),
  );
  switch (kind) {
    case 'exception':
      return empty
          ? UnfinishedExceptionForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
            )
          : UnfinishedExceptionForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              rule: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffPending universe',
              ),
              ruleVersionEnabled: false,
              ruleVersion: 'disabled version',
              fictionalDeparture: true,
              decision: const ExpressionReferenceInput(
                record: '\ufeffPending decision',
                universe: '',
              ),
              scope: pendingScope,
              validity: pendingTime,
              rationale: reason,
              draftVersion: maxU64,
              original: ExceptionRecord(
                rule: ref,
                ruleVersion: RecordVersionId.generate(),
                fictionalDeparture: true,
                scope: originalScope,
                validity: originalValidity,
                authorizingDecision: RecordRef(record: ref.record),
                rationale: '\ufeffOriginal reason\r\n\u0000😀',
              ),
            );
    case 'completeness':
      return empty
          ? UnfinishedCompletenessForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
            )
          : UnfinishedCompletenessForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              subject: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffSubject universe',
              ),
              predicate: '\ufeffPending predicate',
              kind: 'undecided',
              observer: 'disabled observer',
              members: const [
                ExpressionReferenceInput(record: '\ufeffPending member'),
                ExpressionReferenceInput(),
                ExpressionReferenceInput(record: '\ufeffPending member'),
              ],
              scope: pendingScope,
              validity: pendingTime,
              rationale: reason,
              draftVersion: maxU64,
              original: CompletenessRecord(
                subject: ref,
                predicate: '\ufeffPredicate',
                members: [
                  ref,
                  ref,
                  RecordRef(record: ref.record),
                ],
                completeness: ObserverCompleteness(RecordId.generate()),
                scope: originalScope,
                validity: originalValidity,
              ),
            );
    case 'boundary':
      return empty
          ? UnfinishedBoundaryForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
            )
          : UnfinishedBoundaryForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              key: '\ufeffBoundary',
              areaKind: 'undecided',
              record: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffArea universe',
              ),
              predicate: '\ufeffPending predicate',
              subjectEnabled: false,
              subject: const ExpressionReferenceInput(
                record: 'disabled subject',
                universe: 'disabled universe',
              ),
              category: 'disabled category',
              mode: 'undecided',
              scope: pendingScope,
              validity: pendingTime,
              rationale: reason,
              draftVersion: maxU64,
              constraints: [
                ExpressionInput(
                  kind: 'pending',
                  strings: {'\ufeffKey': '\ufeffValue\r\n\u0000😀'},
                  flags: {'yes': true, 'no': false, 'unset': null},
                  operands: {
                    '\ufeffOperand': const OperandInput(
                      kind: 'pending',
                      value: QualifierInput(
                        kind: 'rational',
                        value: '9007199254740997',
                        denominator: '0',
                        temporal: pendingTime,
                      ),
                      original: VariableOperand('\ufeffVariable'),
                    ),
                  },
                  children: {'\ufeffChild': ExpressionInput()},
                  items: [ExpressionInput(), ExpressionInput()],
                  original: const LiteralExpr(true),
                ),
                ExpressionInput(),
                ExpressionInput(),
              ],
              original: BoundaryRecord(
                key: '\ufeffOriginal key',
                area: PredicateBoundaryArea('\ufeffPredicate', ref),
                mode: BoundaryMode.openWithConstraints,
                constraints: [
                  AllExpr([
                    const LiteralExpr(true),
                    const NotExpr(LiteralExpr(false)),
                  ]),
                  const LiteralExpr(false),
                  const LiteralExpr(false),
                ],
                scope: originalScope,
                validity: originalValidity,
              ),
            );
    default:
      throw StateError('Unknown form');
  }
}

void legacy(
  String kind,
  String path,
  List<(EditorFormScope, BigInt, String)> entries,
) {
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE ${kind}_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, g, text) in entries) {
      db.execute('INSERT INTO ${kind}_form VALUES(?,?,?,?,?,?,?,?)', [
        ...binding(s),
        g.toString(),
        text,
      ]);
    }
  } finally {
    db.close();
  }
}

void main() {
  for (final kind in ['exception', 'completeness', 'boundary']) {
    test(
      '$kind typed recovery retains incomplete context, nested values, original metadata and clears replaced input',
      () {
        final root = Directory('/tmp').createTempSync('ub-typed-$kind-'),
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
          store.save(s, form, BigInt.one);
          final dynamic empty = input(kind, s, empty: true);
          store.save(s, empty, BigInt.two);
          store.close();
          store = open(kind, path);
          expect(store.load(s).form.toWire().toText(), empty.toWire().toText());
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(
              db
                  .select('PRAGMA table_info(${kind}_form)')
                  .map((r) => r['name']),
              isNot(contains('form_input')),
            );
            for (final row in db.select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name!='${kind}_form'",
            )) {
              expect(
                db
                    .select('SELECT count(*) AS n FROM "${row['name']}"')
                    .single['n'],
                row['name'] == '${kind}_temporal'
                    ? 1
                    : row['name'] == '${kind}_bound'
                    ? 2
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
    test(
      '$kind conversion preserves isolated forms, generations, retries and conflicting save handling',
      () {
        final root = Directory('/tmp').createTempSync('ub-$kind-conversion-'),
            s = scope(),
            second = scope();
        final path = '${root.path}/forms.sqlite';
        final dynamic form = input(kind, s), other = input(kind, second);
        legacy(kind, path, [
          (s, BigInt.from(19), form.toWire().toText() as String),
          (second, maxU64, other.toWire().toText() as String),
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
      '$kind failed conversion rolls back all typed rows and retains original unfinished forms',
      () {
        final root = Directory('/tmp').createTempSync('ub-$kind-rollback-'),
            s = scope(),
            second = scope();
        final path = '${root.path}/forms.sqlite',
            text = input(kind, s).toWire().toText() as String;
        legacy(kind, path, [
          (s, BigInt.one, text),
          (second, BigInt.two, '{unfinished'),
        ]);
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
                    'SELECT form_input FROM ${kind}_form ORDER BY generation',
                  )
                  .map((r) => r['form_input']),
              [text, '{unfinished'],
            );
            expect(
              db
                  .select("SELECT name FROM sqlite_master WHERE type='table'")
                  .map((r) => r['name']),
              ['${kind}_form'],
            );
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
