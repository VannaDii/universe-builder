export 'package:ub_contracts/ub_contracts.dart'
    show PackageImportPhase, PackageImportDraft, SavedPackageImport;

final class SelectedArchiveFile {
  const SelectedArchiveFile({
    required this.source,
    required this.name,
    this.release,
  });
  final Object source;
  final String name;
  final Future<void> Function()? release;
}
