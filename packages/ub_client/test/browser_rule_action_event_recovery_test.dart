@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_rule_recovery.dart';
import 'package:ub_client/browser_action_recovery.dart';
import 'package:ub_client/browser_event_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

CanonicalObject replace(
  CanonicalObject form,
  Map<String, CanonicalValue?> changes,
) => CanonicalObject([
  for (final field in form.fields)
    if (!changes.containsKey(field.key)) field,
  for (final field in changes.entries)
    if (field.value != null) MapEntry(field.key, field.value!),
]);

Future<void> deleteDatabase(String name) async {
  final done = Completer<void>();
  final request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Test cleanup failed'),
  )).toJS;
  await done.future;
}

void main() {
  for (final family in ['rule', 'action', 'event']) {
    test(
      '$family browser recovery retains typed declarations, exact originals and omitted fields',
      () async {
        final name = 'ub-$family-test-${OperationId.generate().value}';
        final context = RecordId.generate(),
            universe = UniverseId.generate(),
            calendar = CalendarId.generate();
        final scope = EditorFormScope(
          instance: OperationId.generate(),
          profile: ProfileId.generate(),
          universe: universe,
          continuity: ContinuityId.generate(),
          representedContext: context,
          typeClientRef: family,
        );
        final factualScope = Scope(
          context: RecordRef(record: context),
          applicability: UniverseApplicability(),
        );
        final validity = InstantValidity(
          ExactTime(calendar, '9007199254740993123'),
        );
        final comparison = CompareExpr(
          ValueOperand(IntegerValue('9007199254740993123')),
          Comparator.ltEq,
          ValueOperand(RationalValue('003', '02')),
        );
        final slot = EffectSlot(
          slot: 'power',
          order: 63,
          presence: EffectPresence.required,
          target: EffectTarget('actor', RecordRef(record: RecordId.generate())),
          condition: AlwaysEffect(),
          change: SetEffect(
            Polarity.support,
            IntegerValue('9007199254740993123'),
          ),
          lifetime: UntilChangedEffect(),
        );
        final effect = EntityEffect(
          slot: 'power',
          proposition: RecordRef(record: RecordId.generate()),
          polarity: Polarity.support,
          validity: validity,
          scope: factualScope,
          order: BigInt.parse('18446744073709551615'),
        );
        final commonScope = ScopeInput(
          applicability: 'worlds',
          worlds: ['a', '', 'a', 'b'],
          hasRealm: true,
          realmRecord: 'unfinished realm',
        );
        final commonTime = TemporalValidityInput(
          calendar: calendar.value,
          start: TemporalBoundInput(value: '9007199254740993123'),
          end: TemporalBoundInput(value: 'unfinished-'),
        );
        final labels = [
          PropertyLabelInput(language: 'en', text: 'Name 記憶 😀\r\n'),
          PropertyLabelInput(language: 'en', text: ''),
        ];
        final target = ExpressionReferenceInput(
          record: RecordId.generate().value,
          universe: universe.value,
        );
        final pin = RecordVersionId.generate();
        final revision = RevisionId.generate();
        final draft = BigInt.parse('9007199254740993123');
        late CanonicalObject input;
        late Future<void> Function(CanonicalObject, BigInt) save;
        late Future<CanonicalObject?> Function(EditorFormScope) load;
        late Future<void> Function() reopen;
        late void Function() close;
        late Map<String, CanonicalValue?> reordered, cleared;
        switch (family) {
          case 'rule':
            var store = await BrowserRuleFormRecoveryStore.open(
              databaseName: name,
            );
            input = UnfinishedRuleForm(
              baseRevision: revision,
              representedContext: context,
              clientRef: family,
              namespace: 'authored',
              key: 'rule',
              labels: labels,
              kind: 'unfinished',
              commitPolicy: '',
              scope: commonScope,
              subjectTypes: ['a', '', 'a', 'b'],
              targetPredicates: ['p', 'q'],
              capabilities: ['first', '', 'first', 'last'],
              expression: ExpressionInput(
                kind: 'compare',
                original: comparison,
              ),
              executable: false,
              validity: commonTime,
              knowledge: RuleKnowledgeInput(
                policyEnabled: true,
                boundaryEnabled: false,
                mode: 'unfinished',
                holder: ExpressionReferenceInput(record: 'unresolved holder'),
              ),
              constraints: RuleConstraintInput(
                cardinalityEnabled: true,
                chronologyEnabled: true,
                maximum: '9007199254740993123',
                maximumEnabled: true,
                maximumDelay: 'unfinished-',
                forwardOnly: false,
              ),
              revisionTarget: target,
              expectedRecordVersion: pin,
              draftVersion: draft,
              original: RuleRecord(
                namespace: 'authored',
                key: 'previous',
                labels: {'en': 'Previous'},
                kind: RuleKind.descriptive,
                commitPolicy: RuleKind.descriptive.defaultCommitPolicy,
                applicability: UniverseApplicability(),
                targetPredicates: ['p'],
                expression: comparison,
                capabilities: ['first'],
                executable: false,
                validity: validity,
              ),
            ).toWire();
            save = (wire, generation) async {
              await store.save(
                scope,
                UnfinishedRuleForm.fromWire(wire),
                generation,
              );
            };
            load = (scope) async => (await store.load(scope))?.form.toWire();
            close = () => store.close();
            reopen = () async {
              store.close();
              store = await BrowserRuleFormRecoveryStore.open(
                databaseName: name,
              );
            };
            reordered = {
              'labels': CanonicalArray(labels.reversed.map((v) => v.toWire())),
              'capabilities': CanonicalArray(
                ['last', 'first', '', 'first'].map(CanonicalString.new),
              ),
              'executable': CanonicalBool(true),
            };
            cleared = {
              'labels': CanonicalArray([]),
              'capabilities': CanonicalArray([]),
              'subject_types': CanonicalArray([]),
              'target_predicates': CanonicalArray([]),
              'executable': null,
              'knowledge': null,
              'constraints': null,
            };
          case 'action':
            var store = await BrowserActionFormRecoveryStore.open(
              databaseName: name,
            );
            final slots = [
              ActionSlotInput(
                fields: {
                  'order': '9007199254740993123',
                  'lifetime': 'unfinished-',
                },
                original: slot,
              ),
              ActionSlotInput(fields: {'slot': 'unfinished slot'}),
            ];
            final requirements = [
              ActionRequirementInput(
                role: 'actor',
                value: QualifierInput(
                  kind: 'rational',
                  value: '003',
                  denominator: '02',
                ),
              ),
              ActionRequirementInput(role: ''),
            ];
            input = UnfinishedActionForm(
              baseRevision: revision,
              representedContext: context,
              clientRef: family,
              namespace: 'authored',
              key: 'action',
              labels: labels,
              requirements: requirements,
              slots: slots,
              scope: commonScope,
              validity: commonTime,
              revisionTarget: target,
              expectedRecordVersion: pin,
              draftVersion: draft,
              original: ActionDefinitionRecord(
                namespace: 'authored',
                key: 'previous',
                labels: {'en': 'Previous'},
                requirements: [],
                consequenceContract: ConsequenceContract([slot]),
                scope: factualScope,
                validity: validity,
              ),
            ).toWire();
            save = (wire, generation) async {
              await store.save(
                scope,
                UnfinishedActionForm.fromWire(wire),
                generation,
              );
            };
            load = (scope) async => (await store.load(scope))?.form.toWire();
            close = () => store.close();
            reopen = () async {
              store.close();
              store = await BrowserActionFormRecoveryStore.open(
                databaseName: name,
              );
            };
            reordered = {
              'slots': CanonicalArray(slots.reversed.map((v) => v.toWire())),
              'requirements': CanonicalArray(
                requirements.reversed.map((v) => v.toWire()),
              ),
            };
            cleared = {
              'slots': CanonicalArray([]),
              'requirements': CanonicalArray([]),
              'labels': CanonicalArray([]),
            };
          case 'event':
            var store = await BrowserEventFormRecoveryStore.open(
              databaseName: name,
            );
            final effects = [
              EventEffectInput(
                slot: 'power',
                order: 'unfinished-',
                original: effect,
                scope: commonScope,
                validity: commonTime,
              ),
              EventEffectInput(slot: '', order: '9007199254740993123'),
            ];
            final preconditions = [
              ExpressionInput(kind: 'compare', original: comparison),
              ExpressionInput(strings: {'entered': 'unfinished-'}),
            ];
            final participants = [
              EventParticipantInput(record: 'actor', role: 'actor'),
              EventParticipantInput(record: ''),
              EventParticipantInput(record: 'actor', role: 'witness'),
            ];
            input = UnfinishedEventForm(
              baseRevision: revision,
              representedContext: context,
              clientRef: family,
              label: 'Name 記憶 😀\r\n',
              occurrence: 'reported',
              description: 'unfinished description',
              actionRecord: 'unresolved action',
              actionUniverse: universe.value,
              time: commonTime,
              participants: participants,
              effects: effects,
              preconditions: preconditions,
              worlds: ['a', '', 'a', 'b'],
              regionRecord: 'unfinished region',
              regionUniverse: universe.value,
              sequence: 'unfinished sequence',
              occurrenceId: 'occurrence',
              revisionTarget: target,
              expectedRecordVersion: pin,
              draftVersion: draft,
              original: EventRecord(
                occurrence: SimpleOccurrence(OccurrenceKind.reported),
                time: ExactTime(calendar, '9007199254740993123'),
                participants: [],
                effects: [effect],
                preconditions: [comparison],
                labels: {'en': 'Previous'},
                expansionVersion: 'original expansion',
              ),
            ).toWire();
            save = (wire, generation) async {
              await store.save(
                scope,
                UnfinishedEventForm.fromWire(wire),
                generation,
              );
            };
            load = (scope) async => (await store.load(scope))?.form.toWire();
            close = () => store.close();
            reopen = () async {
              store.close();
              store = await BrowserEventFormRecoveryStore.open(
                databaseName: name,
              );
            };
            reordered = {
              'effects': CanonicalArray(
                effects.reversed.map((v) => v.toWire()),
              ),
              'participants': CanonicalArray(
                participants.reversed.map((v) => v.toWire()),
              ),
              'preconditions': CanonicalArray(
                preconditions.reversed.map((v) => v.toWire()),
              ),
            };
            cleared = {
              'effects': CanonicalArray([]),
              'preconditions': CanonicalArray([]),
              'participants': CanonicalArray([]),
              'worlds': CanonicalArray([]),
              'region_record': CanonicalString(''),
              'region_universe': CanonicalString(''),
              'sequence': CanonicalString(''),
              'occurrence_id': CanonicalString(''),
            };
        }
        try {
          await save(input, BigInt.zero);
          await reopen();
          expect((await load(scope))!.toText(), input.toText());
          await save(input, BigInt.zero);
          final reorderedForm = replace(input, reordered);
          await expectLater(
            save(reorderedForm, BigInt.zero),
            throwsA(
              isA<EditorRecoveryException>().having(
                (e) => e.failure,
                'failure',
                EditorRecoveryFailure.conflict,
              ),
            ),
          );
          expect((await load(scope))!.toText(), input.toText());
          await save(reorderedForm, BigInt.one);
          expect((await load(scope))!.toText(), reorderedForm.toText());
          final clearedForm = replace(input, cleared);
          await save(clearedForm, BigInt.two);
          expect((await load(scope))!.toText(), clearedForm.toText());
          // Optional contracts remain distinct from explicit empty declarations.
          final omitted = replace(clearedForm, {
            'original': null,
            'revision_target': null,
            'expected_record_version': null,
            'draft_version': null,
            if (family == 'action') 'slots': null,
            if (family == 'event') 'effects': null,
            if (family == 'event') 'preconditions': null,
          });
          await save(omitted, BigInt.from(3));
          expect((await load(scope))!.toText(), omitted.toText());
          final different = EditorFormScope(
            instance: scope.instance,
            profile: scope.profile,
            universe: universe,
            continuity: scope.continuity,
            representedContext: context,
            typeClientRef: 'other',
          );
          expect(await load(different), isNull);
          await expectLater(
            save(
              replace(omitted, {'client_ref': CanonicalString('other')}),
              BigInt.from(4),
            ),
            throwsFormatException,
          );
          expect((await load(scope))!.toText(), omitted.toText());
        } finally {
          close();
          await deleteDatabase(name);
        }
      },
    );
  }
}
