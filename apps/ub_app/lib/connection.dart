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
    required this.loadTypeForm,
    required this.saveTypeForm,
    required this.loadEntityForm,
    required this.saveEntityForm,
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
  final Future<SavedTypeForm?> Function(EditorFormScope) loadTypeForm;
  final Future<SavedTypeForm> Function(
    EditorFormScope,
    UnfinishedTypeForm,
    BigInt,
  )
  saveTypeForm;
  final Future<SavedEntityForm?> Function(EditorFormScope) loadEntityForm;
  final Future<SavedEntityForm> Function(
    EditorFormScope,
    UnfinishedEntityForm,
    BigInt,
  )
  saveEntityForm;
}

final class LibraryEntry {
  const LibraryEntry(this.id, this.name);
  final UniverseId id;
  final String name;
}

enum ConnectedBackend { sqlite, postgres }

final class TestedSqliteConnection {
  const TestedSqliteConnection({required this.instance, required this.profile});
  final OperationId instance;
  final ProfileId profile;
}

/// A device-local selection. Never serialized or returned to a browser/API.
final class TestedPostgresConnection {
  const TestedPostgresConnection({
    required this.endpoint,
    required this.instance,
    required this.profile,
  });
  final String endpoint;
  final OperationId instance;
  final ProfileId profile;
  @override
  String toString() => 'TestedPostgresConnection([redacted])';
}

final class InstanceLibrary {
  InstanceLibrary({
    required this.instance,
    required this.backend,
    required Iterable<LibraryEntry> universes,
  }) : universes = List.unmodifiable(universes);
  final OperationId instance;
  final ConnectedBackend backend;
  final List<LibraryEntry> universes;
  factory InstanceLibrary.fromWire(CanonicalValue value) {
    final fields = Map.fromEntries((value as CanonicalObject).fields);
    return InstanceLibrary(
      instance: OperationId.parse(wireString(fields['instance_id']!)),
      backend: switch (wireString(fields['backend']!)) {
        'sqlite' => ConnectedBackend.sqlite,
        'postgres' => ConnectedBackend.postgres,
        _ => throw const FormatException('Unsupported connected backend'),
      },
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
