@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/source_verification.dart';
import 'package:ub_store/src/database.dart';
import 'package:ub_store/src/workflow_storage.dart';

import 'operation_compilation_test.dart' as f;
import 'source_verification_test.dart' as sources;

void main() {
  test('source and image receipts survive SQLite reopen and detect retained corruption', () async {
    final directory = Directory.systemTemp.createTempSync(
      'universe-builder-source-',
    );
    final path = '${directory.path}/package.sqlite';
    try {
      final v = sources.source(), bytes = [0, 1, 255];
      final image = ImageAssetRecord(
        contentDigest: sha256.convert(bytes).toString(),
        mediaType: 'image/png',
        byteSize: BigInt.from(bytes.length),
        width: 1,
        height: 1,
        originalName: 'image.png',
      );
      final entries = {
        ...sources.staging(v),
        'image-asset:${f.id(4).value}': image.toWire(),
        'image-bytes:${image.contentDigest}:0': CanonicalString(
          base64.encode(bytes),
        ),
      };
      final original = SqliteDatabase.open(path);
      try {
        WorkflowStorage(original).compareAppend({}, entries.entries);
      } finally {
        original.close();
      }
      final reopened = SqliteDatabase.open(path, existing: true);
      try {
        final workflow = WorkflowStorage(reopened);
        final records = [
          f.row(2, v),
          f.row(3, sources.anchor()),
          f.row(4, image),
        ];
        Future<void> verify() => verifyCandidateSources(
          records: records,
          readWorkflow: workflow.get,
          readVersion: (_) =>
              throw StateError('Candidate version must be used'),
        );
        await verify();
        reopened.execute('DROP TRIGGER source_content_no_update');
        reopened.execute(
          'UPDATE source_content SET utf8_content=? WHERE digest=?',
          [utf8.encode('Altered content'), v.contentDigest],
        );
        await expectLater(verify(), throwsFormatException);
      } finally {
        reopened.close();
      }
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
