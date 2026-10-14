import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/boundary_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('boundary edits preserve every area and mode, ordered constraints and exact validity', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    final constraints = [
      AllExpr([const LiteralExpr(true), const LiteralExpr(false)]),
      CompareExpr(
        ValueOperand(IntegerValue('9007199254740993')),
        Comparator.ltEq,
        ValueOperand(IntegerValue('9007199254740997')),
      ),
      const LiteralExpr(false),
      const LiteralExpr(false),
    ];
    for (final area in [
      RecordBoundaryArea(ref()),
      PredicateBoundaryArea('authored:account', ref()),
      const PredicateBoundaryArea('authored:account', null),
      CategoryBoundaryArea(RecordId.generate()),
    ]) {
      for (final mode in BoundaryMode.values) {
        final record = BoundaryRecord(
          key: 'Origin 記憶 😀',
          area: area,
          mode: mode,
          constraints: constraints,
          scope: Scope(
            applicability: const UniverseApplicability(),
            context: RecordRef(universe: universe, record: context),
          ),
          validity: InstantValidity(
            ExactTime(CalendarId.generate(), '9007199254740997'),
          ),
        );
        final draft = SavedDraft(
          version: BigInt.from(6),
          content: DraftContent(
            baseRevision: RevisionId.generate(),
            representedContext: context,
            operations: [
              SetCreativeBoundaryOperation(
                clientRef: 'boundary',
                record: record,
              ),
            ],
            rationale: 'Keep the authored boundary.',
          ),
        );
        final form = UnfinishedBoundaryForm.fromWire(
          boundaryFormFromDraft(draft, 0).toWire(),
        );
        expect(
          boundaryOperation(form).record.toWire().toText(),
          record.toWire().toText(),
        );
        final request = boundaryDraftRequest(
          draft: draft,
          form: form.copyWith(
            mode: 'proposal_required',
            constraints: form.constraints.reversed.toList(),
          ),
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        );
        final next =
            (request.content.operations.single as SetCreativeBoundaryOperation)
                .record;
        expect(next.mode, BoundaryMode.proposalRequired);
        expect(next.area.toWire().toText(), area.toWire().toText());
        expect(next.key, record.key);
        expect(
          next.constraints.map((e) => e.toWire().toText()),
          constraints.reversed.map((e) => e.toWire().toText()),
        );
        expect(
          next.validity.toWire().toText(),
          record.validity.toWire().toText(),
        );
        expect(next.scope.toWire().toText(), record.scope.toWire().toText());
        expect(request.content.rationale, draft.content.rationale);
        expect(
          () => boundaryDraftRequest(
            draft: SavedDraft(version: BigInt.from(7), content: draft.content),
            form: form,
            universe: const Selector('Universe'),
            continuity: ContinuityId.generate(),
            index: 0,
          ),
          throwsFormatException,
        );
      }
    }
  });
  test('unfinished boundaries recover without assuming an area, mode or complete constraint', () {
    final root = Directory('/tmp').createTempSync('ub-boundary-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedBoundaryForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      key: 'unfinished 記憶 😀',
      predicate: 'authored:',
      constraints: [
        ExpressionInput(kind: 'all', items: [ExpressionInput()]),
      ],
    );
    var store = BoundaryFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = BoundaryFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.areaKind, isEmpty);
      expect(recovered.mode, isEmpty);
      expect(() => boundaryOperation(recovered), throwsFormatException);
      expect(
        () => boundaryOperation(recovered.copyWith(areaKind: 'predicate')),
        throwsFormatException,
      );
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(scope, form.copyWith(mode: 'fixed'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
