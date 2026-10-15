import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final class ArchiveExportResult {
  const ArchiveExportResult({
    required this.manifest,
    this.savedPath,
    this.downloadStarted = false,
  });
  final CanonicalObject manifest;
  final String? savedPath;
  final bool downloadStarted;

  String get message {
    if (savedPath == null && !downloadStarted) {
      return 'Export file selection cancelled.';
    }
    final fields = WireFields(manifest, {
      'format',
      'universe',
      'name',
      'complete',
      'omitted_records',
      'includes_history',
      'includes_workflow',
    });
    final outcome = downloadStarted
        ? 'Archive download started. Your browser reports completion.'
        : 'Archive saved: $savedPath';
    final omitted = fields.u64('omitted_records');
    final scope = fields.boolean('complete')
        ? 'Complete factual archive.'
        : 'Filtered archive; $omitted ${omitted == BigInt.one ? 'record' : 'records'} omitted. Import it as a named clone.';
    final workflow = fields.boolean('includes_workflow')
        ? 'Workflow history is included as historical evidence.'
        : 'Private drafts, approvals and workflow records are omitted.';
    return '$outcome\n$scope\n$workflow';
  }
}
