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
  typeClientRef: '\ufeffPending narrative input',
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
const pendingValue = QualifierInput(
  kind: 'pending',
  value: '\ufeffValue\r\n\u0000😀',
  unit: 'disabled unit',
  temporal: pendingTime,
  children: [
    QualifierInput(key: 'same'),
    QualifierInput(key: 'same'),
  ],
  lower: QualifierInput(kind: 'integer', value: '9007199254740997'),
);
const reason = '\ufeffReason\r\n\u0000記憶😀';
ExpressionInput condition() => ExpressionInput(
  kind: 'pending',
  strings: {'\ufeffKey': '\ufeffValue\r\n\u0000😀'},
  flags: {'yes': true, 'no': false, 'unset': null},
  operands: {
    '\ufeffOperand': const OperandInput(
      kind: 'pending',
      value: pendingValue,
      original: VariableOperand('\ufeffVariable'),
    ),
  },
  children: {'\ufeffChild': ExpressionInput()},
  items: [ExpressionInput(), ExpressionInput()],
  original: const LiteralExpr(true),
);
dynamic open(String kind, String path) => switch (kind) {
  'plan' => PlanFormRecoveryStore.open(path),
  'scene' => SceneFormRecoveryStore.open(path),
  'item_power' => ItemPowerFormRecoveryStore.open(path),
  _ => throw StateError('Unknown form'),
};
dynamic input(String kind, EditorFormScope s, {bool empty = false}) {
  final base = RevisionId.generate(),
      ref = RecordRef(record: RecordId.generate(), universe: s.universe),
      calendar = CalendarId.generate(),
      world = WorldId.generate();
  final time = ApproximateTime(
    calendar,
    '\ufeffCoordinate',
    SequenceValue([
      const RationalValue('9007199254740997', '3'),
      const TextValue('\ufeffUncertainty'),
    ]),
  );
  switch (kind) {
    case 'plan':
      return empty
          ? UnfinishedPlanForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
            )
          : UnfinishedPlanForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              actor: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffActor universe',
              ),
              desiredEnabled: false,
              desired: const ExpressionReferenceInput(
                record: 'disabled desired',
                universe: 'disabled universe',
              ),
              prerequisites: [condition(), ExpressionInput(), condition()],
              steps: const [
                ExpressionReferenceInput(record: '\ufeffStep'),
                ExpressionReferenceInput(),
                ExpressionReferenceInput(record: '\ufeffStep'),
              ],
              status: 'undecided',
              validity: pendingTime,
              rationale: reason,
              draftVersion: maxU64,
              original: GoalRecord(
                actor: ref,
                desired: RecordRef(record: ref.record),
                prerequisites: [
                  AllExpr([
                    const LiteralExpr(true),
                    const NotExpr(LiteralExpr(false)),
                  ]),
                  const LiteralExpr(false),
                  const LiteralExpr(false),
                ],
                steps: [
                  ref,
                  ref,
                  RecordRef(record: ref.record),
                ],
                status: PlanStatus.active,
                validity: InstantValidity(time),
              ),
            );
    case 'item_power':
      return empty
          ? UnfinishedItemPowerForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
            )
          : UnfinishedItemPowerForm(
              baseRevision: base,
              representedContext: s.representedContext!,
              clientRef: s.typeClientRef!,
              item: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffItem universe',
              ),
              holderPredicate: const ExpressionReferenceInput(
                record: '\ufeffHolder predicate',
                universe: '',
              ),
              powerPredicate: const ExpressionReferenceInput(
                record: '\ufeffPower predicate',
                universe: 'pending universe',
              ),
              value: pendingValue,
              scope: const ScopeInput(
                applicability: 'undecided',
                worlds: ['\ufeffWorld', '', '\ufeffWorld'],
                contextRecord: '',
                contextUniverse: 'pending',
                hasRealm: false,
                realmRecord: 'disabled realm',
                realmUniverse: 'disabled universe',
              ),
              validity: pendingTime,
              rationale: reason,
              draftVersion: maxU64,
              correctionTarget: const ExpressionReferenceInput(
                record: '',
                universe: '\ufeffPending target',
              ),
              expectedRecordVersion: RecordVersionId.generate(),
              original: ItemPowerRecord(
                item: ref,
                holderPredicate: RecordRef(record: ref.record),
                powerPredicate: ref,
                value: StructuredValue(ValueDefinitionId.generate(), {
                  '\ufeffKey': SequenceValue([
                    const RationalValue('9007199254740997', '3'),
                    const TextValue('\ufeffValue'),
                  ]),
                }),
                scope: Scope(
                  context: ref,
                  realm: ref,
                  applicability: WorldsApplicability([world, world]),
                ),
                validity: InstantValidity(time),
              ),
            );
    case 'scene':
      if (empty) {
        return UnfinishedSceneForm(
          baseRevision: base,
          representedContext: s.representedContext!,
          clientRef: s.typeClientRef!,
        );
      }
      final association = WorldAssociation(
        world: world,
        role: '\ufeffSetting',
        validity: InstantValidity(time),
        qualifiers: {
          '\ufeffKey': const RationalValue('9007199254740997', '3'),
          'nested': SequenceValue([const TextValue('\ufeffValue')]),
        },
      );
      final entered = WorkAssociationInput(
        world: '\ufeffPending world',
        role: '\ufeffRole',
        validity: pendingTime,
        qualifiers: const [pendingValue, pendingValue],
        originalOrdinal: 9223372036854775807,
      );
      return UnfinishedSceneForm(
        baseRevision: base,
        representedContext: s.representedContext!,
        clientRef: s.typeClientRef!,
        sceneId: '\ufeffScene',
        edition: const ExpressionReferenceInput(
          record: '',
          universe: '\ufeffEdition universe',
        ),
        editionVersion: 'pending version',
        viewpointEnabled: false,
        viewpoint: const ExpressionReferenceInput(
          record: 'disabled viewpoint',
          universe: 'disabled universe',
        ),
        narrationEnabled: false,
        narration: const ExpressionReferenceInput(
          record: 'disabled narration',
          universe: 'disabled universe',
        ),
        positionEnabled: false,
        position: '9007199254740997?',
        disclosed: const [
          ExpressionReferenceInput(record: '\ufeffDisclosure'),
          ExpressionReferenceInput(),
          ExpressionReferenceInput(record: '\ufeffDisclosure'),
        ],
        depicted: const [
          ExpressionReferenceInput(record: '\ufeffDepicted'),
          ExpressionReferenceInput(record: '\ufeffDepicted'),
        ],
        associations: [entered, WorkAssociationInput(), entered],
        rationale: reason,
        draftVersion: maxU64,
        correctionTarget: const ExpressionReferenceInput(
          record: '',
          universe: '\ufeffPending target',
        ),
        expectedRecordVersion: RecordVersionId.generate(),
        original: SceneRecord(
          workVersion: VersionRef(
            record: RecordId.generate(),
            version: RecordVersionId.generate(),
            universe: s.universe,
          ),
          sceneId: '\ufeffOriginal scene',
          disclosedRecords: [ref, ref],
          depictedEvents: [
            ref,
            ref,
            RecordRef(record: ref.record),
          ],
          viewpoint: ref,
          narrationFrame: RecordRef(record: ref.record),
          narrativePosition: maxU64,
          worldAssociations: [association, association],
        ),
      );
    default:
      throw StateError('Unknown form');
  }
}

void main() {
  for (final kind in ['plan', 'scene', 'item_power']) {
    test(
      '$kind typed recovery retains incomplete input and exact original records then removes replaced nested rows',
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
              final n = kind == 'scene'
                  ? 0
                  : row['name'] == '${kind}_temporal'
                  ? 1
                  : row['name'] == '${kind}_bound'
                  ? 2
                  : kind == 'item_power' &&
                        row['name'] == 'item_power_qualifier'
                  ? 1
                  : 0;
              expect(
                db
                    .select('SELECT count(*) AS n FROM "${row['name']}"')
                    .single['n'],
                n,
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
