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
  }
}
