@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/runtime_admission.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  late Directory directory;
  late SqliteInstallationStore installation;
  late InstallationPrincipal author;
  late List<InstallationPrincipal> writers;
  late NativeRuntimeAdmission admission;
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-admission-',
    );
    installation = SqliteInstallationStore.create(directory.path);
    final authority = InstallationAuthority(installation);
    InstallationPrincipal authenticate(ProfileId id) => authority.authenticate(
      profile: id,
      credential: Credential(
        ProfileCredentialStore.read(root: directory.path, profile: id),
      ),
    );
    author = authenticate(authority.initializeAuthor());
    writers = List.generate(4, (_) => authenticate(authority.enroll(author)));
    admission = NativeRuntimeAdmission();
  });
  tearDown(() {
    installation.close();
    directory.deleteSync(recursive: true);
  });
  final busy = throwsA(isA<EvaluationLimitReachedError>());

  test('agent saturation leaves author request capacity available', () async {
    final writer = admission.connect(writers.first);
    final other = admission.connect(writers[1]);
    final owner = admission.connect(author);
    final gate = Completer<int>();
    final work = [
      ...List.generate(4, (_) => writer.run(() => gate.future)),
      ...List.generate(4, (_) => other.run(() => gate.future)),
    ];
    await expectLater(
      writer.run(() => fail('Over-capacity work must not execute')),
      busy,
    );
    final authorWork = List.generate(4, (_) => owner.run(() => gate.future));
    await expectLater(owner.run(() => fail('Author reserve is bounded')), busy);
    gate.complete(7);
    expect(await Future.wait([...work, ...authorWork]), everyElement(7));
    expect(await writer.run(() => 8), 8);
    expect(await owner.run(() => 9), 9);
    writer.close();
    other.close();
    owner.close();
  });

  test('connections preserve author reserve and release on close', () {
    final first = List.generate(8, (_) => admission.connect(writers.first));
    expect(() => admission.connect(writers.first), busy);
    for (final lease in first) {
      lease.close();
    }
    final agents = [
      for (final writer in writers.take(3))
        ...List.generate(8, (_) => admission.connect(writer)),
    ];
    expect(() => admission.connect(writers.last), busy);
    final owners = List.generate(8, (_) => admission.connect(author));
    expect(() => admission.connect(author), busy);
    agents.first.close();
    agents.first.close();
    final extra = admission.connect(writers.last);
    extra.close();
    for (final lease in [...agents, ...owners]) {
      lease.close();
    }
    admission.connect(author).close();
  });

  test(
    'disconnect keeps admitted mutations counted until they finish',
    () async {
      final lease = admission.connect(author);
      final gate = Completer<void>();
      final work = List.generate(4, (_) => lease.run(() => gate.future));
      lease.close();
      final replacement = admission.connect(author);
      await expectLater(
        replacement.run(() => fail('Admitted work still occupies capacity')),
        busy,
      );
      gate.complete();
      await Future.wait(work);
      expect(await replacement.run(() => 'finished'), 'finished');
      replacement.close();
    },
  );

  test(
    'failed requests release capacity and closed connections cannot run',
    () async {
      final lease = admission.connect(author);
      final error = StateError('action failed');
      for (var n = 0; n < 8; n++) {
        await expectLater(lease.run(() => throw error), throwsA(same(error)));
      }
      expect(await lease.run(() async => 'available'), 'available');
      lease.close();
      await expectLater(
        lease.run(() => fail('Closed lease cannot execute')),
        throwsStateError,
      );
    },
  );
}
