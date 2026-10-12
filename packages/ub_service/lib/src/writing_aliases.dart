import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'writing_binding.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

/// Uses admitted pinned identities, never names introduced by this same delta.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> unchanged,
  List<String> clarifications,
})
compileWritingAliases({
  required Frame frame,
  required List<RecordVersion> base,
  required List<WritingAlias> aliases,
}) {
  final operations = <DomainOperation>[],
      additions = <String>[],
      unchanged = <String>[],
      clarifications = <String>[];
  final targets = <RecordId>{};
  for (final alias in aliases) {
    try {
      if (!_nonWhitespace.hasMatch(alias.text)) {
        throw const FormatException(
          "Supply the author's explicit nonempty alias text.",
        );
      }
      final id =
          resolveWritingObject(base, alias.object, frame) ??
          (throw FormatException(
            "Which exact existing identity is '${alias.object}' ?",
          ));
      final original = base.firstWhere((r) => r.identity.recordId == id);
      final entity = original.payload as EntityRecord;
      final validity = alias.atTick == null && alias.lifetime == null
          ? const UnspecifiedValidity()
          : bindWritingLifetime(
              bindWritingTime(frame, base, alias.atTick),
              alias.lifetime ?? const FactUnspecifiedLifetime(),
            );
      final name = ContextualName(
        text: alias.text,
        language: alias.language,
        community: alias.community,
        role: alias.role,
        validity: validity,
      );
      if (entity.names.any(
        (n) => n.toWire().toText() == name.toWire().toText(),
      )) {
        unchanged.add('Existing alias: ${alias.object} — ${alias.text}');
        continue;
      }
      if (!targets.add(id)) {
        throw const FormatException(
          'Add only one new alias per identity per delta; existing aliases stay unchanged.',
        );
      }
      operations.add(
        AddNameOperation(
          record: RecordRef(universe: frame.universe, record: id),
          expectedVersion: original.recordVersionId,
          name: name,
        ),
      );
      additions.add(
        'Explicit alias: ${alias.object} — ${alias.text}; no knowledge or communication inferred.',
      );
    } on FormatException catch (error) {
      clarifications.add(error.message.toString());
    }
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    unchanged: List.unmodifiable(unchanged),
    clarifications: List.unmodifiable(clarifications),
  );
}
