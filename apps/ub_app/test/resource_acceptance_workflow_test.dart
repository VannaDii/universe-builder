@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_app/resource_acceptance.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('resource acceptance recovers a completed revision and requires fresh checks and separate approval', () async {
    final root = Directory('/tmp').createTempSync('ub-resource-acceptance-');
    final device = DeviceConnection([
      '--installation',
      root.path,
    ], embeddedLocal: true);
    AppSession? session;
    try {
      session = await device.connect();
      final status = InstanceLibrary.fromWire(
        await session.call(const StatusEngineRequest()),
      );
      final created = WireFields(
        await session.call(
          const CreateUniverseEngineRequest(
            name: 'Resources',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
        ),
        {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
      );
      final scope = EditorFormScope(
        instance: status.instance,
        profile: session.principal,
        universe: UniverseId.parse(created.string('universe_id')),
        continuity: ContinuityId.parse(created.string('continuity_id')),
        representedContext: RecordId.parse(created.string('context_id')),
      );
      SavedChanges changes() => SavedChanges(
        session: session!,
        universe: const Selector('Resources'),
        scope: scope,
      );
      SavedChanges libraryChanges() => SavedChanges(
        session: session!,
        universe: const Selector('Resources'),
        scope: EditorFormScope(
          instance: scope.instance,
          profile: scope.profile,
          universe: scope.universe,
          continuity: scope.continuity,
        ),
      );
      final empty = SavedDraft(
        version: BigInt.zero,
        content: DraftContent(
          baseRevision: RevisionId.parse(created.string('revision')),
          representedContext: scope.representedContext!,
          operations: [],
          rationale: 'Track campaign ammunition.',
        ),
      );
      final opened = await openDraftChoiceContext(changes(), empty);
      final context = await readContextRecord(
        session: session,
        universe: LibraryEntry(scope.universe, 'Resources'),
        context: opened,
        record: scope.representedContext!,
      );
      final calendar =
          (context.payload as RepresentedContextRecord).chronology!.calendar;
      final actor = RecordId.generate(),
          property = RecordId.generate(),
          rule = RecordId.generate();
      RecordRef ref(RecordId id) =>
          RecordRef(universe: scope.universe, record: id);
      AssertPropositionOperation count(String value, int start, int end) {
        final proposition = RecordId.generate();
        return AssertPropositionOperation(
          clientRef: proposition.value,
          proposition: PropositionRecord(
            subject: ref(actor),
            predicate: ref(property),
            value: IntegerValue(value),
            quantification: Quantification.particular,
            context: ref(scope.representedContext!),
          ),
          assertion: AssertionRecord(
            attributeMode: AttributeMode.instance,
            proposition: ref(proposition),
            polarity: Polarity.support,
            scope: Scope(
              context: ref(scope.representedContext!),
              applicability: const UniverseApplicability(),
            ),
            validity: CalendarIntervalValidity(
              calendar,
              ExactBound('$start'),
              ExactBound('$end'),
            ),
            persistence: PersistenceSemantics.explicitInterval,
            precision: Precision.exact,
            basis: const AuthorDecisionBasis('Campaign count'),
          ),
        );
      }

      final operations = <DomainOperation>[
        CreateEntityOperation(
          clientRef: actor.value,
          record: EntityRecord(
            names: [],
            classificationResolution: ClassificationResolution.unclassified,
            worldAssociations: [],
            labels: {'en': 'Ranger'},
            metadata: {},
          ),
        ),
        DefinePropertyOperation(
          clientRef: property.value,
          record: PropertyRecord(
            namespace: 'resource',
            key: 'rounds',
            labels: {},
            value: const SimpleValueShape(SimpleShapeKind.integer),
            multiplicity: Multiplicity.single,
            persistence: PersistenceSemantics.explicitInterval,
            exclusive: false,
            symmetric: false,
            transitive: false,
          ),
        ),
        DefineRuleOperation(
          clientRef: rule.value,
          record: RuleRecord(
            namespace: 'resource',
            key: 'accounting',
            labels: {},
            kind: RuleKind.physicalConstraint,
            commitPolicy: CommitPolicy.blockUnlessException,
            applicability: const UniverseApplicability(),
            targetPredicates: ['resource:rounds'],
            expression: const LiteralExpr(true),
            capabilities: ['resources.accounting.v1'],
            executable: true,
            validity: const UnspecifiedValidity(),
          ),
        ),
        count('1', 0, 5),
        count('2', 5, 20),
      ];
      await changes().saveContent(
        empty,
        DraftContent(
          baseRevision: empty.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: operations,
          rationale: empty.content.rationale,
        ),
      );
      final proposal = await changes().submit((await changes().load())!);
      final draft = (await changes().load())!;
      final validation =
          await changes().validate(proposal) as EvaluatedValidation;
      final records = await changes().findingRecords(proposal, validation);
      final finding = validation.execution.findings
          .where((f) => canAcceptResourceFinding(f, records))
          .single;
      await expectLater(
        changes().approve(proposal, validation),
        throwsA(isA<PolicyDeniedError>()),
      );
      final target = ResourceAcceptance(proposal: proposal, finding: finding);
      final principal = PrincipalId.parse(
        scope.profile.value.replaceFirst('prf_', 'prn_'),
      );
      final form = target
          .form(principal)
          .copyWith(
            rationale: '\ufeffAccept the exact unexplained count 記憶 😀\r\n',
          );
      expect(
        () => target.operation(form, author: false, principal: principal),
        throwsFormatException,
      );
      expect(
        () => target.operation(
          form.copyWith(rationale: '  '),
          author: true,
          principal: principal,
        ),
        throwsFormatException,
      );
      expect(
        () => target.operation(
          form.copyWith(scope: 'another resource'),
          author: true,
          principal: principal,
        ),
        throwsFormatException,
      );
      expect(canAcceptResourceFinding(finding, {}), isFalse);
      final formScope = EditorFormScope(
        instance: scope.instance,
        profile: scope.profile,
        universe: scope.universe,
        continuity: scope.continuity,
        representedContext: scope.representedContext,
        typeClientRef: target.clientRef,
      );
      await session.saveIssueDecisionForm(formScope, form, BigInt.zero);
      final decision = target.operation(
        form,
        author: true,
        principal: principal,
      );
      // Complete the service revision without saving its response into the draft.
      // A reconnect must look up the existing operation instead of sending a new context ID.
      final revised = Envelope<Proposal>.fromWire(
        await session.call(
          ToolEngineRequest(
            request: ReviseProposalRequest(
              universe: const Selector('Resources'),
              universeId: scope.universe,
              contextId: opened.contextId,
              proposalReference: target.reference,
              operations: [...proposal.operations, decision],
              submission: Submission.submitted,
              rationale: proposal.rationale,
              idempotencyKey: target.revisionKey(decision),
            ),
          ),
        ),
        Proposal.fromWire,
      ).result;
      await session.close();
      session = await device.connect();
      final recoveredForm = (await session.loadIssueDecisionForm(formScope))!
          .form;
      expect(recoveredForm.toWire().toText(), form.toWire().toText());
      final accepted = await libraryChanges().acceptResource(
        draft: draft,
        target: target,
        form: recoveredForm,
      );
      expect(accepted.content.proposal, changes().reference(revised));
      expect(accepted.content.proposal!.proposalId, proposal.proposalId);
      expect(accepted.content.proposal!.version, proposal.version + BigInt.one);
      expect(
        accepted.content.operations
            .whereType<RecordIssueDecisionOperation>()
            .length,
        1,
      );
      expect(
        accepted.content.operations
            .take(operations.length)
            .map((op) => op.toWire().toText()),
        operations.map((op) => op.toWire().toText()),
      );
      expect(
        (await libraryChanges().acceptResource(
          draft: draft,
          target: target,
          form: recoveredForm,
        )).version,
        accepted.version,
      );
      await expectLater(
        libraryChanges().acceptResource(
          draft: draft,
          target: target,
          form: recoveredForm.copyWith(rationale: 'A different decision'),
        ),
        throwsFormatException,
      );
      expect((await changes().load())!.version, accepted.version);
      final recoveredProposal = (await changes().recover(accepted))!;
      expect(await changes().publication(recoveredProposal), isNull);
      await expectLater(
        changes().approve(recoveredProposal, validation),
        throwsA(isA<ApprovalStaleError>()),
      );
      final checked =
          await changes().validate(recoveredProposal) as EvaluatedValidation;
      await changes().approve(recoveredProposal, checked);
      final receipt = await changes().publish(
        recoveredProposal,
        checked.execution.runId,
      );
      expect(receipt.revision, isNot(proposal.baseFrame.revision));
      final decisions = (await changes().readPublished(
        recoveredProposal,
        receipt,
      )).where((r) => r.payload is IssueDecisionRecord).toList();
      expect(
        (decisions.single.payload as IssueDecisionRecord).rationale,
        form.rationale,
      );
      expect(
        (decisions.single.payload as IssueDecisionRecord).scope,
        target.scope,
      );
    } on ProtocolError catch (error) {
      fail(error.toWire().toText());
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
