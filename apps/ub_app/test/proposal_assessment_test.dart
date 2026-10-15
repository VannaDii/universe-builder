@TestOn('vm')
library;

import 'package:test/test.dart';

import 'dart:io';

import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/draft_record_choices.dart';
import 'package:ub_app/proposal_assessment.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('review reads a complete paged declaration from the checked attachment after selection changes', () async {
    final root = Directory('/tmp').createTempSync('ub-assessment-review-');
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
            name: 'Assessment',
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
        universe: const Selector('Assessment'),
        scope: scope,
      );
      final staged = WireFields(
        await session.call(
          const StageSourceEngineRequest(
            universe: Selector('Assessment'),
            label: 'Retained passage',
            text: 'Ié🌲',
          ),
        ),
        {'canonical', 'operations'},
      );
      final content = DraftContent(
        baseRevision: RevisionId.parse(created.string('revision')),
        representedContext: scope.representedContext!,
        operations: staged.array('operations').map(DomainOperation.fromWire),
        rationale: 'Retain the original source.',
      );
      final draft = await changes().saveContent(
        SavedDraft(version: BigInt.zero, content: content),
        content,
      );
      final sourceProposal = await changes().submit(draft);
      final sourceChecks =
          await changes().validate(sourceProposal) as EvaluatedValidation;
      await changes().approve(sourceProposal, sourceChecks);
      final sourceReceipt = await changes().publish(
        sourceProposal,
        sourceChecks.execution.runId,
      );
      final source = (await changes().readPublished(
        sourceProposal,
        sourceReceipt,
      )).singleWhere((row) => row.payload is SourceVersionRecord);
      final sourceVersion = source.payload as SourceVersionRecord;
      final next = await changes().rebase(
        (await changes().load())!,
        startNew: true,
      );
      final candidateDraft = await changes().saveContent(
        next,
        DraftContent(
          baseRevision: next.content.baseRevision,
          representedContext: scope.representedContext!,
          operations: [
            CreateWorldOperation(
              clientRef: RecordId.generate().value,
              record: WorldRecord(selector: 'Proposed setting'),
            ),
          ],
          rationale: 'Review the author proposal.',
        ),
      );
      final proposal = await changes().submit(candidateDraft);
      final opened = await openDraftChoiceContext(changes(), candidateDraft);
      final longText = List.filled(2300, '漢🙂').join();
      SourceAssessmentV1 body(String rationale) => SourceAssessmentV1(
        kind: AssessmentKind.sourceAssessmentV1,
        proposal: changes().reference(proposal),
        baseFrame: proposal.baseFrame,
        assessor: Assessor(
          principal: PrincipalId.parse(
            session!.principal.value.replaceFirst('prf_', 'prn_'),
          ),
          method: Method.externalModelReview,
          tool: ToolIdentity(
            name: longText,
            version: 'fixture',
            modelRevision: 'fixture',
            procedureDigest: Sha256Hex('a' * 64),
          ),
          assessedAt: '2026-10-15T00:00:00Z',
        ),
        sources: [
          SourceBinding(
            key: 'Retained passage',
            sourceVersion: AssessmentVersionRef(
              universe: scope.universe,
              record: source.identity.recordId,
              version: source.recordVersionId,
            ),
            blobDigest: Sha256Hex(sourceVersion.contentDigest),
            byteSize: sourceVersion.byteSize,
            representation: SourceRepresentation.exactUtf8V1,
            ranges: [
              ByteRange(start: BigInt.zero, end: sourceVersion.byteSize),
            ],
            workEdition: null,
            passageId: null,
          ),
        ],
        dependencies: [],
        declaredInventory: [],
        inventoryDeclaration: InventoryDeclaration(
          kind: InventoryKind.noMaterialClaims,
          rationale: rationale,
          exclusions: [],
        ),
        claimMappings: [],
        unresolved: [],
        conclusion: DeclaredConclusion.consistentWithDeclaredInventory,
      );
      Future<AssessmentSelection> attach(
        SourceAssessmentV1 body,
        BigInt expected,
        String key,
      ) async => Envelope<AssessmentSelection>.fromWire(
        await session!.call(
          ToolEngineRequest(
            request: AttachAssessmentRequest(
              universe: changes().universe,
              universeId: scope.universe,
              contextId: opened.contextId,
              proposalReference: changes().reference(proposal),
              expectedSelectionGeneration: expected,
              body: body,
              idempotencyKey: key,
            ),
          ),
        ),
        AssessmentSelection.fromWire,
      ).result;
      final original = body(longText);
      expect(original.toWire().toBytes().length, greaterThan(32768));
      final first = await attach(original, BigInt.zero, 'first-attachment');
      final checks = await changes().validate(proposal) as EvaluatedValidation;
      final reference = assessmentReference(checks.assessment)!;
      expect(reference.toWire().toText(), first.selected!.toWire().toText());
      final second = await attach(
        body('A later declaration must not replace the checked one.'),
        first.generation,
        'later-attachment',
      );
      final declaration = await readProposalAssessment(
        changes(),
        proposal,
        reference,
      );
      expect(declaration!.assessmentId, first.selected!.assessmentId);
      expect(declaration.body.toWire().toText(), original.toWire().toText());
      expect(declaration.body.inventoryDeclaration.rationale, longText);
      expect(declaration.body.assessor.tool!.name, longText);
      final smaller = await readProposalAssessment(
        changes(),
        proposal,
        second.selected!,
      );
      expect(
        smaller!.body.inventoryDeclaration.rationale,
        'A later declaration must not replace the checked one.',
      );
      await session.close();
      session = await device.connect();
      final reopened = await readProposalAssessment(
        changes(),
        proposal,
        reference,
      );
      expect(reopened!.toWire().toText(), declaration.toWire().toText());
    } on ProtocolError catch (error) {
      fail(error.toWire().toText());
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
