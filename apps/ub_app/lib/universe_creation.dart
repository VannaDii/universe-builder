import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

export 'package:ub_contracts/ub_contracts.dart'
    show CreationCalendar, UniverseCreationForm, SavedUniverseCreationForm;

LibraryEntry createdUniverse(CanonicalValue value) {
  final fields = WireFields(value, {
    'universe_id',
    'continuity_id',
    'context_id',
    'revision',
    'name',
  });
  return LibraryEntry(
    UniverseId.parse(fields.string('universe_id')),
    fields.string('name'),
  );
}
