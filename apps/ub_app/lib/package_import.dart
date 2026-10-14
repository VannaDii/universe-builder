import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

enum PackageImportPhase { input, uploading, review, admitting, admitted }

final class PackageImportDraft {
  const PackageImportDraft({
    required this.operation,
    this.name = '',
    this.mode = ImportMode.clone,
    this.phase = PackageImportPhase.input,
    this.fileName = '',
    this.review,
    this.receipt,
  });
  final OperationId operation;
  final String name, fileName;
  final ImportMode mode;
  final PackageImportPhase phase;
  final CanonicalObject? review, receipt;
  PackageImportDraft copyWith({
    String? name,
    ImportMode? mode,
    PackageImportPhase? phase,
    String? fileName,
    CanonicalObject? review,
    CanonicalObject? receipt,
  }) => PackageImportDraft(
    operation: operation,
    name: name ?? this.name,
    mode: mode ?? this.mode,
    phase: phase ?? this.phase,
    fileName: fileName ?? this.fileName,
    review: review ?? this.review,
    receipt: receipt ?? this.receipt,
  );
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('operation', CanonicalString(operation.value)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('mode', CanonicalString(mode.name)),
    MapEntry('phase', CanonicalString(phase.name)),
    MapEntry('file_name', CanonicalString(fileName)),
    if (review != null) MapEntry('review', review!),
    if (receipt != null) MapEntry('receipt', receipt!),
  ]);
  AcceptImportEngineRequest admission() {
    final fields = Map.fromEntries(review!.fields);
    if (wireString(fields['preview_id']!) != operation.value ||
        wireString(fields['name']!) != name) {
      throw const FormatException(
        'Import review does not match this selection',
      );
    }
    return AcceptImportEngineRequest(
      previewId: operation,
      digest: wireString(fields['digest']!),
    );
  }
}

final class SavedPackageImport {
  SavedPackageImport({required this.form, required BigInt generation})
    : generation = generation {
    if (generation < BigInt.zero || generation >= BigInt.one << 64) {
      throw const FormatException('Invalid import generation');
    }
  }
  final PackageImportDraft form;
  final BigInt generation;
}

final class SelectedArchiveFile {
  const SelectedArchiveFile({required this.source, required this.name});
  final Object source;
  final String name;
}
