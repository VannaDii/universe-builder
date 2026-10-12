import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;

void main() {
  test('explicit definitions bind parents introduced later and preserve unspecified applicability', () {
    final result = compileWritingDefinitions(
      declarations: [
        DefinitionChange(name: 'Oak', introduce: true, parent: 'Tree'),
        DefinitionChange(name: 'Tree', introduce: true, scope: 'universe'),
      ],
      rows: [],
      worldRows: [],
    );
    expect(result.clarifications, isEmpty);
    expect(result.operations, hasLength(2));
    expect(result.unknowns, [
      "The applicability of definition 'Oak' remains unspecified.",
    ]);
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: [],
      operations: result.operations,
    );
    final oak = candidate.singleWhere(
      (r) => (r.payload as EntityTypeRecord).key == 'Oak',
    );
    final tree = candidate.singleWhere(
      (r) => (r.payload as EntityTypeRecord).key == 'Tree',
    );
    expect((oak.payload as EntityTypeRecord).parent, tree.identity.recordId);
    expect(
      (oak.payload as EntityTypeRecord).parentResolution,
      ParentResolution.resolved,
    );
    expect(
      (oak.payload as EntityTypeRecord).applicability,
      isA<UnspecifiedApplicability>(),
    );
    expect(
      (tree.payload as EntityTypeRecord).parentResolution,
      ParentResolution.root,
    );
    expect(result.introduced['Oak'], oak.identity.recordId);
    expect(
      resolveWritingDefinition([], 'Tree', introduced: result.introduced),
      tree.identity.recordId,
    );
  });

  test('definition declarations clarify duplicates absence and unauthorized world scope', () {
    final existing = f.row(1, f.type(1, key: 'Tree'));
    final duplicate = compileWritingDefinitions(
      declarations: [
        DefinitionChange(name: 'Oak', introduce: true),
        DefinitionChange(name: 'Oak', introduce: true),
      ],
      rows: [],
      worldRows: [],
    );
    expect(duplicate.operations, isEmpty);
    expect(duplicate.ambiguous, {'Oak'});
    expect(duplicate.clarifications, hasLength(3));
    expect(
      resolveWritingDefinition(
        [],
        'Oak',
        introduced: duplicate.introduced,
        ambiguous: duplicate.ambiguous,
      ),
      isNull,
    );
    final result = compileWritingDefinitions(
      declarations: [
        DefinitionChange(name: 'Tree', introduce: true),
        DefinitionChange(name: 'missing'),
        DefinitionChange(name: 'child', introduce: true, parent: 'missing'),
        DefinitionChange(name: 'Tree', parent: 'Other'),
        DefinitionChange(name: 'Scoped', introduce: true, scope: 'Hidden'),
      ],
      rows: [existing],
      worldRows: [],
    );
    expect(result.operations, isEmpty);
    expect(result.clarifications, hasLength(5));
    expect(
      () => compileWritingDefinitions(
        declarations: [DefinitionChange(name: '\u0085', introduce: true)],
        rows: [],
        worldRows: [],
      ),
      throwsA(
        isA<InvalidArgumentError>().having(
          (e) => e.field,
          'field',
          'definitions.name',
        ),
      ),
    );
    final world = f.row(
      50,
      WorldRecord(selector: 'Ashen', aliases: ['Ashen world']),
    );
    final scoped = compileWritingDefinitions(
      declarations: [
        DefinitionChange(
          name: 'Scoped',
          introduce: true,
          scope: ' ashen WORLD ',
        ),
      ],
      rows: [],
      worldRows: [world],
    );
    expect(scoped.clarifications, isEmpty);
    expect(
      (scoped.operations.single as IntroduceDefinitionOperation).applicability,
      WorldsApplicability([WorldId.parse('wld_${f.suffix(50)}')]),
    );
    final restricted = compileWritingDefinitions(
      declarations: [
        DefinitionChange(name: 'Scoped', introduce: true, scope: 'Ashen'),
      ],
      rows: [],
      worldRows: [world],
      worldScope: {},
    );
    expect(restricted.operations, isEmpty);
    expect(restricted.clarifications, hasLength(1));
  });

  test('definition corrections use pinned originals and candidate parents while preserving metadata', () {
    final old = f.row(
      1,
      EntityTypeRecord(
        namespace: 'campaign',
        key: 'tree',
        name: 'Tree',
        labels: {'en': 'Woody plant'},
        parent: f.id(2),
        parentResolution: ParentResolution.resolved,
        applicability: const UnspecifiedApplicability(),
        classificationExecutable: false,
      ),
    );
    final parent = f.row(2, f.type(2));
    final introduced = compileWritingDefinitions(
      declarations: [
        DefinitionChange(name: 'Plant', introduce: true, scope: 'universe'),
      ],
      rows: [old, parent],
      worldRows: [],
    );
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: [old, parent],
      operations: introduced.operations,
    );
    final result = compileWritingDefinitionCorrections(
      universe: f.u,
      base: [old, parent],
      rows: candidate,
      corrections: [
        WritingDefinitionCorrection(
          name: 'Woody plant',
          reason: 'Correct ancestry',
          parent: WritingDefinitionParent(name: 'Plant'),
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    final op = result.operations.single as ReviseDefinitionOperation;
    expect(op.expectedVersion, old.recordVersionId);
    expect(op.record, f.ref(1));
    final replacement = op.replacement as EntityTypeRecord;
    expect(replacement.namespace, 'campaign');
    expect(replacement.labels, {'en': 'Woody plant'});
    expect(replacement.classificationExecutable, isFalse);
    expect(replacement.applicability, isA<UnspecifiedApplicability>());
    expect(replacement.parent, introduced.introduced['Plant']);
    final revised = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: candidate,
      operations: result.operations,
    );
    expect(
      () => compileWritingCandidate(
        universe: f.u,
        revision: f.revision,
        base: revised,
        operations: result.operations,
      ),
      throwsA(isA<InvalidArgumentError>()),
    );
    final root = compileWritingDefinitionCorrections(
      universe: f.u,
      base: [old],
      rows: [old],
      corrections: [
        WritingDefinitionCorrection(
          name: 'tree',
          reason: 'Explicit root',
          parent: WritingRootParent(),
        ),
      ],
    );
    final rootDefinition =
        (root.operations.single as ReviseDefinitionOperation).replacement
            as EntityTypeRecord;
    expect(rootDefinition.parent, isNull);
    expect(rootDefinition.parentResolution, ParentResolution.root);
    final scopeOnly = compileWritingDefinitionCorrections(
      universe: f.u,
      base: [old],
      rows: [old, parent],
      corrections: [
        WritingDefinitionCorrection(
          name: 'Tree',
          reason: 'Global definition',
          scope: 'universe',
        ),
      ],
    );
    final global =
        (scopeOnly.operations.single as ReviseDefinitionOperation).replacement
            as EntityTypeRecord;
    expect(global.parent, f.id(2));
    expect(global.applicability, isA<UniverseApplicability>());
  });

  test('missing ambiguous or unpinned correction targets do not manufacture replacements', () {
    final old = f.row(1, f.type(1)), duplicate = f.row(2, f.type(1));
    for (final patch in [
      WritingDefinitionCorrection(name: 'Type1', reason: 'No fields'),
      WritingDefinitionCorrection(name: 'Type1', reason: '', scope: 'universe'),
      WritingDefinitionCorrection(
        name: 'Missing',
        reason: 'Absent',
        scope: 'universe',
      ),
      WritingDefinitionCorrection(
        name: 'Type1',
        reason: 'Ambiguous',
        scope: 'universe',
      ),
    ]) {
      final denied = compileWritingDefinitionCorrections(
        universe: f.u,
        base: [old, duplicate],
        rows: [old, duplicate],
        corrections: [patch],
      );
      expect(denied.operations, isEmpty);
      expect(denied.clarifications, hasLength(1));
    }
    final missingParent = compileWritingDefinitionCorrections(
      universe: f.u,
      base: [old],
      rows: [old],
      corrections: [
        WritingDefinitionCorrection(
          name: 'Type1',
          reason: 'Unknown parent',
          parent: WritingDefinitionParent(name: 'Missing'),
        ),
      ],
    );
    expect(missingParent.operations, isEmpty);
    expect(
      missingParent.clarifications.single,
      contains('exact parent definition'),
    );
    final unpinned = compileWritingDefinitionCorrections(
      universe: f.u,
      base: [],
      rows: [old],
      corrections: [
        WritingDefinitionCorrection(
          name: 'Type1',
          reason: 'Candidate only',
          scope: 'universe',
        ),
      ],
    );
    expect(unpinned.operations, isEmpty);
    expect(
      unpinned.clarifications.single,
      contains('exact authored definition'),
    );
  });
}
