/// Ephemeral local engine discovery; contains no credentials or author data.
library;

import 'dart:io';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'src/ownership.dart';

Uri readLocalHttpEndpoint(String root) {
  if (!Directory(root).existsSync()) {
    throw FileSystemException(
      'Installation unavailable',
      root,
      const OSError('Missing', 2),
    );
  }
  final path = '${privateDirectory(root)}/engine-http.json';
  protectedFile(path);
  final file = File(path);
  if (file.lengthSync() > 8192) {
    throw const FormatException('Endpoint metadata too large');
  }
  final fields = WireFields(
    CanonicalValue.parseWireJson(file.readAsStringSync()),
    {'protocol_version', 'endpoint'},
  );
  if (fields.string('protocol_version') != protocolVersion) {
    throw const FormatException('Incompatible endpoint');
  }
  return Uri.parse(fields.string('endpoint'));
}

/// The running service must hold the installation lock before publishing.
void writeLocalHttpEndpoint(String root, Uri endpoint) {
  final directory = privateDirectory(root);
  final path = '$directory/engine-http.json';
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    protectedFile(path);
  }
  final temporary =
      '$directory/engine-http-${OperationId.generate().value}.tmp';
  protectedFile(temporary, createNew: true);
  try {
    File(temporary).writeAsBytesSync(
      CanonicalObject([
        MapEntry('protocol_version', CanonicalString(protocolVersion)),
        MapEntry('endpoint', CanonicalString(endpoint.toString())),
      ]).toBytes(),
      flush: true,
    );
    File(temporary).renameSync(path);
  } finally {
    if (File(temporary).existsSync()) File(temporary).deleteSync();
  }
}

/// Called by the owning service before releasing its installation lock.
void removeLocalHttpEndpoint(String root) {
  final path = '${privateDirectory(root)}/engine-http.json';
  if (FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return;
  }
  protectedFile(path);
  File(path).deleteSync();
}
