import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

List<RecordVersion> dossierAppearances(
  Records material,
  UniverseId universe,
  RecordId entry,
) => [
  for (final row in [...material.records, ...material.evidence])
    if (row.payload case AppearanceRecord(:final target)
        when row.identity.universeId == universe)
      if (row.identity.recordId == entry ||
          switch (target) {
            EntryAppearance(entry: final reference) =>
              reference.record == entry &&
                  (reference.universe == null ||
                      reference.universe == universe),
            UniverseAppearance() => false,
          })
        row,
];
