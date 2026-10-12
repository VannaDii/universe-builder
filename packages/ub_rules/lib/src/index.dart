import 'package:ub_domain/ub_domain.dart';

/// Ephemeral lookup over one exact candidate, without frame or grant authority.
/// Callers rebuild it for changed snapshots; it never reads a database head.
final class EvaluationIndex {
  EvaluationIndex(Iterable<RecordVersion> records) {
    for (final r in records) {
      switch (r.payload) {
        case ItemPowerRecord():
          _hasPowers = true;
        case PropertyRecord(:final namespace, :final key):
          _definitions.putIfAbsent('$namespace:$key', () => []).add(r);
        case RelationRecord(:final namespace, :final key):
          _definitions.putIfAbsent('$namespace:$key', () => []).add(r);
        case PropositionRecord(
          :final subject,
          :final predicate,
          :final context,
        ):
          _propositions
              .putIfAbsent((subject, predicate.record, context), () => [])
              .add(r);
        case AssertionRecord(:final proposition):
          _assertions.putIfAbsent(proposition.record, () => []).add(r);
        case CompletenessRecord(:final subject, :final predicate):
          _completeness.putIfAbsent((subject, predicate), () => []).add(r);
        case ExceptionRecord(:final rule):
          _exceptions.putIfAbsent(rule.record, () => []).add(r);
        default:
          break;
      }
    }
  }

  final _definitions = <String, List<RecordVersion>>{};
  final _propositions =
      <(RecordRef, RecordId, RecordRef), List<RecordVersion>>{};
  final _assertions = <RecordId, List<RecordVersion>>{};
  final _completeness = <(RecordRef, String), List<RecordVersion>>{};
  final _exceptions = <RecordId, List<RecordVersion>>{};
  bool _hasPowers = false;
  bool get hasPowers => _hasPowers;

  List<RecordVersion> exceptions(RecordId target) =>
      List.unmodifiable(_exceptions[target] ?? const []);

  /// Definitions precede each matching proposition and its assertions, followed
  /// by subject/predicate completeness declarations. No interpretation occurs.
  List<RecordVersion> claim(
    RecordRef subject,
    String predicate,
    RecordRef context,
  ) {
    final found = <RecordVersion>[];
    for (final definition
        in _definitions[predicate] ?? const <RecordVersion>[]) {
      found.add(definition);
      for (final proposition
          in _propositions[(subject, definition.identity.recordId, context)] ??
              const <RecordVersion>[]) {
        found.add(proposition);
        found.addAll(_assertions[proposition.identity.recordId] ?? const []);
      }
    }
    found.addAll(_completeness[(subject, predicate)] ?? const []);
    return List.unmodifiable(found);
  }
}
