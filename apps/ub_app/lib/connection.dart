import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final class AppSession {
  const AppSession({
    required this.call,
    required this.close,
    required this.author,
    required this.principal,
    required this.loadWorldForm,
    required this.saveWorldForm,
  });
  final Future<CanonicalValue> Function(EngineRequest) call;
  final Future<void> Function() close;
  final bool author;
  final ProfileId principal;
  final Future<SavedWorldForm?> Function(EditorFormScope) loadWorldForm;
  final Future<SavedWorldForm> Function(
    EditorFormScope,
    UnfinishedWorldForm,
    BigInt,
  )
  saveWorldForm;
}

final class LibraryEntry {
  const LibraryEntry(this.id, this.name);
  final UniverseId id;
  final String name;
}

final class InstanceLibrary {
  InstanceLibrary({
    required this.instance,
    required Iterable<LibraryEntry> universes,
  }) : universes = List.unmodifiable(universes);
  final OperationId instance;
  final List<LibraryEntry> universes;
  factory InstanceLibrary.fromWire(CanonicalValue value) {
    final fields = Map.fromEntries((value as CanonicalObject).fields);
    return InstanceLibrary(
      instance: OperationId.parse(wireString(fields['instance_id']!)),
      universes: (fields['universes']! as CanonicalArray).items.map((entry) {
        final row = WireFields(entry, {'id', 'name'});
        return LibraryEntry(
          UniverseId.parse(row.string('id')),
          row.string('name'),
        );
      }),
    );
  }
}
