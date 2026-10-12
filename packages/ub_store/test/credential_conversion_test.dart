@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  late Directory root;
  late ProfileId profile;
  late String source, destination, targetRoot;
  const secret = 'Disposable exact credential: é😀\r\n\u0000';
  setUp(() {
    root = Directory.systemTemp.createTempSync(
      'universe-builder-credential-conversion-',
    );
    privateDirectory(root.path);
    profile = ProfileId.generate();
    source = '${root.path}/${profile.value}.json';
    targetRoot = privateDirectory('${root.path}/target');
    privateDirectory('$targetRoot/profiles');
    destination = '$targetRoot/profiles/${profile.value}.sqlite';
    protectedFile(source, createNew: true);
    File(source).writeAsStringSync(
      jsonEncode({
        'format_version': 1,
        'profile_id': profile.value,
        'credential': secret,
      }),
      flush: true,
    );
  });
  tearDown(() => root.deleteSync(recursive: true));
  void noStages() => expect(
    Directory('$targetRoot/profiles').listSync().where(
      (entry) => entry.uri.pathSegments.any(
        (part) => part.startsWith('.credential-conversion-'),
      ),
    ),
    isEmpty,
  );
  Matcher failure(CredentialConversionFailure value) => throwsA(
    isA<CredentialConversionException>().having(
      (error) => error.failure,
      'failure',
      value,
    ),
  );

  test('offline credential conversion preserves exact identity secret and read-only original without enrollment', () {
    final bytes = File(source).readAsBytesSync();
    expect(Process.runSync('chmod', ['400', source]).exitCode, 0);
    final result = WireFields(convertCredential(source, destination), {
      'source_sha256',
      'original_preserved',
      'credential_verified',
    });
    expect(result.string('source_sha256'), sha256.convert(bytes).toString());
    expect(result.boolean('original_preserved'), isTrue);
    expect(result.boolean('credential_verified'), isTrue);
    expect(
      ProfileCredentialStore.read(root: targetRoot, profile: profile),
      secret,
    );
    expect(File(source).readAsBytesSync(), orderedEquals(bytes));
    expect(File(source).statSync().mode & 0x1ff, 0x100);
    expect(File(destination).statSync().mode & 0x1ff, 0x180);
    expect(File('$targetRoot/installation.sqlite').existsSync(), isFalse);
    expect(
      result.values.values.map((value) => value.toText()).join(),
      isNot(contains(secret)),
    );
    noStages();
  });

  test('credential conversion refuses existing files and symlinks without replacing needed data', () {
    final bytes = File(source).readAsBytesSync();
    File(destination).writeAsStringSync('Retained destination');
    expect(
      () => convertCredential(source, destination),
      failure(CredentialConversionFailure.destinationExists),
    );
    expect(File(destination).readAsStringSync(), 'Retained destination');
    File(destination).deleteSync();
    Link(destination).createSync(source);
    expect(
      () => convertCredential(source, destination),
      failure(CredentialConversionFailure.destinationExists),
    );
    expect(File(source).readAsBytesSync(), orderedEquals(bytes));
    noStages();
  });

  test('credential conversion redacts malformed secrets and refuses unsupported inputs without publication', () {
    for (final input in [
      {'format_version': 2, 'profile_id': profile.value, 'credential': secret},
      {'format_version': 1, 'profile_id': secret, 'credential': secret},
      {
        'format_version': 1,
        'profile_id': profile.value,
        'credential': [secret],
      },
      {'format_version': 1, 'profile_id': profile.value, 'credential': ''},
      {
        'format_version': 1,
        'profile_id': profile.value,
        'credential': secret,
        secret: secret,
      },
    ]) {
      File(source).writeAsStringSync(jsonEncode(input), flush: true);
      Object? caught;
      try {
        convertCredential(source, destination);
      } on Object catch (error) {
        caught = error;
      }
      expect(caught, isA<CredentialConversionException>());
      expect(caught.toString(), isNot(contains(secret)));
      expect(File(destination).existsSync(), isFalse);
      noStages();
    }
    File(source).writeAsBytesSync([0xff]);
    expect(
      () => convertCredential(source, destination),
      failure(CredentialConversionFailure.invalidInput),
    );
    File(source).writeAsStringSync('x' * 4097);
    expect(
      () => convertCredential(source, destination),
      failure(CredentialConversionFailure.unavailable),
    );
    expect(File(destination).existsSync(), isFalse);
  });

  test('checked read-only credential input refuses symlinks hardlinks and permissive modes', () {
    final linked = Link('${root.path}/linked.json')..createSync(source);
    expect(
      () => convertCredential(linked.path, destination),
      failure(CredentialConversionFailure.unavailable),
    );
    final hard = '${root.path}/hard.json';
    expect(Process.runSync('ln', [source, hard]).exitCode, 0);
    expect(
      () => convertCredential(source, destination),
      failure(CredentialConversionFailure.unavailable),
    );
    File(hard).deleteSync();
    expect(Process.runSync('chmod', ['644', source]).exitCode, 0);
    expect(
      () => convertCredential(source, destination),
      failure(CredentialConversionFailure.unavailable),
    );
    expect(File(destination).existsSync(), isFalse);
    noStages();
  });

  test('exclusive conversion publication renames a private file and refuses an existing target atomically', () {
    final staged = '${root.path}/staged.sqlite';
    protectedFile(staged, createNew: true);
    File(staged).writeAsStringSync('First complete target');
    publishConversionFile(staged, destination);
    expect(File(staged).existsSync(), isFalse);
    expect(File(destination).readAsStringSync(), 'First complete target');
    protectedFile(staged, createNew: true);
    File(staged).writeAsStringSync('Second complete target');
    expect(
      () => publishConversionFile(staged, destination),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(staged).readAsStringSync(), 'Second complete target');
    expect(File(destination).readAsStringSync(), 'First complete target');
  });
}
