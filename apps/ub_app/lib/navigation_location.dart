import 'package:ub_domain/ub_domain.dart';

enum LibrarySection { library, settings, help }

/// Links carry identifiers and page choices, never profile or database secrets.
final class LibraryLocation {
  const LibraryLocation({this.section = LibrarySection.library, this.universe});
  final LibrarySection section;
  final UniverseId? universe;
  Uri get uri => universe == null
      ? Uri(path: '/${section.name}')
      : Uri(path: '/universe/${universe!.value}');
  static LibraryLocation parse(Uri uri) {
    if (uri.hasScheme || uri.hasAuthority || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('Unsupported application link');
    }
    final parts = uri.pathSegments;
    if (parts.isEmpty) return const LibraryLocation();
    if (parts.length == 1 && parts.single.isEmpty) {
      return const LibraryLocation();
    }
    if (parts.length == 1) {
      return LibraryLocation(
        section: LibrarySection.values.byName(parts.single),
      );
    }
    if (parts.length == 2 && parts.first == 'universe') {
      return LibraryLocation(universe: UniverseId.parse(parts.last));
    }
    throw const FormatException('Unsupported application link');
  }
}
