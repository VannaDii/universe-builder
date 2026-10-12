import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_binding.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);
List<(RecordVersion, EntityTypeRecord)> _named(
  List<RecordVersion> rows,
  String name,
) => [
  for (final row in rows)
    if (row.payload case final EntityTypeRecord definition)
      if (definition.key == name ||
          definition.name == name ||
          definition.labels.values.contains(name))
        (row, definition),
];

RecordId? resolveWritingDefinition(
  List<RecordVersion> rows,
  String name, {
  Map<String, RecordId> introduced = const {},
  Set<String> ambiguous = const {},
}) {
  if (ambiguous.contains(name)) return null;
  final ids = {
    for (final (row, _) in _named(rows, name)) row.identity.recordId,
    if (introduced[name] != null) introduced[name]!,
  };
  return ids.length == 1 ? ids.single : null;
}

/// Allocate only explicit introductions. Shared and initial attributes are
/// compiled later using these exact bindings, never inferred here.
({
  List<DomainOperation> operations,
  Map<String, RecordId> introduced,
  Set<String> ambiguous,
  List<String> additions,
  List<String> clarifications,
  List<String> unknowns,
})
compileWritingDefinitions({
  required List<DefinitionChange> declarations,
  required List<RecordVersion> rows,
  required List<RecordVersion> worldRows,
  Set<WorldId>? worldScope,
}) {
  final introduced = <String, RecordId>{}, ambiguous = <String>{};
  final operations = <DomainOperation>[],
      additions = <String>[],
      clarifications = <String>[],
      unknowns = <String>[];
  for (final declaration in declarations.where((d) => d.introduce)) {
    if (!_nonWhitespace.hasMatch(declaration.name)) {
      throw const InvalidArgumentError(
        field: 'definitions.name',
        message: 'nonempty definition name required',
      );
    }
    if (introduced.containsKey(declaration.name)) {
      ambiguous.add(declaration.name);
      clarifications.add(
        "Are the repeated definitions '${declaration.name}' the same type?",
      );
    }
    introduced[declaration.name] = RecordId.generate();
  }
  RecordId? resolve(String name) => resolveWritingDefinition(
    rows,
    name,
    introduced: introduced,
    ambiguous: ambiguous,
  );
  for (final declaration in declarations) {
    final id = resolve(declaration.name);
    if (id == null) {
      clarifications.add(
        "Which exact reusable definition is '${declaration.name}', or is it an explicitly new definition?",
      );
      continue;
    }
    if (!declaration.introduce) {
      if (declaration.parent != null) {
        clarifications.add(
          "Changing an existing definition's ancestry requires an explicit definition revision, not classification refinement.",
        );
      }
      continue;
    }
    RecordId? parent;
    if (declaration.parent != null) {
      parent = resolve(declaration.parent!);
      if (parent == null) {
        clarifications.add(
          "Which exact parent definition is '${declaration.parent}'?",
        );
        continue;
      }
    }
    final Applicability applicability;
    try {
      applicability = bindWritingApplicability(
        worldRows,
        declaration.scope,
        worldScope: worldScope,
      );
    } on FormatException {
      clarifications.add(
        "Which accessible authored world is '${declaration.scope}'?",
      );
      continue;
    } on NotFoundOrNotAccessibleError {
      clarifications.add(
        "Which accessible authored world is '${declaration.scope}'?",
      );
      continue;
    }
    if (declaration.scope == 'unspecified') {
      unknowns.add(
        "The applicability of definition '${declaration.name}' remains unspecified.",
      );
    }
    operations.add(
      IntroduceDefinitionOperation(
        clientRef: id.value,
        namespace: 'authoring',
        key: declaration.name,
        name: declaration.name,
        parent: parent,
        applicability: applicability,
        classificationExecutable: true,
      ),
    );
    additions.add('New reusable definition: ${declaration.name}');
  }
  return (
    operations: List.unmodifiable(operations),
    introduced: Map.unmodifiable(introduced),
    ambiguous: Set.unmodifiable(ambiguous),
    additions: List.unmodifiable(additions),
    clarifications: List.unmodifiable(clarifications),
    unknowns: List.unmodifiable(unknowns),
  );
}

/// Corrections pin the base definition; candidate rows may supply an explicitly
/// introduced parent. Omitted ancestry and applicability remain unchanged.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> clarifications,
})
compileWritingDefinitionCorrections({
  required UniverseId universe,
  required List<RecordVersion> base,
  required List<RecordVersion> rows,
  required List<WritingDefinitionCorrection> corrections,
  Set<WorldId>? worldScope,
}) {
  final operations = <DomainOperation>[],
      additions = <String>[],
      clarifications = <String>[];
  for (final patch in corrections) {
    try {
      if (!_nonWhitespace.hasMatch(patch.reason)) {
        throw const FormatException(
          'Give the reason for this ancestry/applicability correction.',
        );
      }
      if (patch.parent == null && patch.scope == null) {
        throw const FormatException(
          'Specify the ancestry or applicability correction; omitted fields stay unchanged.',
        );
      }
      final found = _named(base, patch.name);
      if (found.length != 1) {
        throw FormatException(
          "Which exact authored definition is '${patch.name}' ?",
        );
      }
      final (original, definition) = found.single;
      var parent = definition.parent, resolution = definition.parentResolution;
      if (patch.parent != null) {
        switch (patch.parent!) {
          case WritingRootParent():
            parent = null;
          case WritingDefinitionParent(:final name):
            final parents = _named(rows, name);
            if (parents.length != 1) {
              throw FormatException(
                "Which exact parent definition is '$name' ?",
              );
            }
            parent = parents.single.$1.identity.recordId;
        }
        resolution = parent == null
            ? ParentResolution.root
            : ParentResolution.resolved;
      }
      final replacement = EntityTypeRecord(
        namespace: definition.namespace,
        key: definition.key,
        name: definition.name,
        labels: definition.labels,
        parent: parent,
        parentResolution: resolution,
        classificationExecutable: definition.classificationExecutable,
        applicability: patch.scope == null
            ? definition.applicability
            : bindWritingApplicability(
                rows,
                patch.scope!,
                worldScope: worldScope,
              ),
      );
      operations.add(
        ReviseDefinitionOperation(
          record: RecordRef(
            universe: universe,
            record: original.identity.recordId,
          ),
          expectedVersion: original.recordVersionId,
          replacement: replacement,
        ),
      );
      additions.add('Definition correction: ${patch.name} — ${patch.reason}');
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    } on NotFoundOrNotAccessibleError catch (error) {
      clarifications.add(error.message);
    }
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    clarifications: List.unmodifiable(clarifications),
  );
}
