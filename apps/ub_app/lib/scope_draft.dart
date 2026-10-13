import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

ScopeInput scopeInput(Scope scope) => ScopeInput(
  applicability: switch (scope.applicability) {
    UniverseApplicability() => 'universe_wide',
    WorldsApplicability() => 'worlds',
    ConditionalApplicability() => 'conditional',
    UnspecifiedApplicability() => 'unspecified',
  },
  worlds: scope.applicability is WorldsApplicability
      ? (scope.applicability as WorldsApplicability).worldIds
            .map((w) => w.value)
            .toList()
      : const [],
  contextRecord: scope.context.record.value,
  contextUniverse: scope.context.universe?.value ?? '',
  hasRealm: scope.realm != null,
  realmRecord: scope.realm?.record.value ?? '',
  realmUniverse: scope.realm?.universe?.value ?? '',
);

Scope buildScope(ScopeInput input) => Scope(
  applicability: switch (input.applicability) {
    'universe_wide' => const UniverseApplicability(),
    'worlds' => WorldsApplicability(input.worlds.map(WorldId.parse)),
    'conditional' => const ConditionalApplicability(),
    'unspecified' => const UnspecifiedApplicability(),
    _ => throw const FormatException('Choose factual applicability.'),
  },
  context: _reference(input.contextRecord, input.contextUniverse),
  realm: input.hasRealm
      ? _reference(input.realmRecord, input.realmUniverse)
      : null,
);

RecordRef _reference(String record, String universe) => RecordRef(
  record: RecordId.parse(record),
  universe: universe.isEmpty ? null : UniverseId.parse(universe),
);
