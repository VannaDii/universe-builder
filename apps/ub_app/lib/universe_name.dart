import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

Future<LibraryEntry> renameUniverse(
  AppSession session,
  LibraryEntry universe,
  String name,
) async {
  final result = WireFields(
    await session.call(
      RenameUniverseEngineRequest(universeId: universe.id, name: name),
    ),
    {'universe_id', 'name'},
  );
  return LibraryEntry(
    UniverseId.parse(result.string('universe_id')),
    result.string('name'),
  );
}
