@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/installation.dart';

void main() {
  late Directory directory;
  late SqliteInstallationStore store;
  late ProfileId author, writer;
  late UniverseId universe;
  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'universe-builder-authority-',
    );
    store = SqliteInstallationStore.create(directory.path);
    author = ProfileId.generate();
    writer = ProfileId.generate();
    universe = UniverseId.generate();
    store.enroll(id: author, credentialHash: '0' * 64);
    store.enroll(id: writer, credentialHash: '1' * 64, actor: author);
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  test(
    'queued revocation cannot change authority during an awaited capture',
    () async {
      final entered = Completer<void>(), resume = Completer<void>();
      final order = <String>[];
      final capture = store.withAuthority(() async {
        final sequence = store.validationAuthoritySequence(writer, universe);
        entered.complete();
        await resume.future;
        expect(store.validationAuthoritySequence(writer, universe), sequence);
        expect(store.profile(writer)!.revoked, isFalse);
        order.add('captured');
      });
      await entered.future;
      final revoke = store.withAuthority(() {
        store.revoke(actor: author, target: writer);
        order.add('revoked');
      });
      expect(store.profile(writer)!.revoked, isFalse);
      resume.complete();
      await capture;
      await revoke;
      expect(order, ['captured', 'revoked']);
      expect(store.profile(writer)!.revoked, isTrue);
      expect(
        store.validationAuthoritySequence(writer, universe),
        greaterThan(BigInt.zero),
      );
    },
  );

  test('direct mutation and close are refused while another section owns authority', () async {
    final entered = Completer<void>(), resume = Completer<void>();
    final held = store.withAuthority(() async {
      entered.complete();
      await resume.future;
    });
    await entered.future;
    try {
      expect(
        () => store.revoke(actor: author, target: writer),
        throwsA(
          isA<InstallationException>().having(
            (e) => e.failure,
            'failure',
            InstallationFailure.unavailable,
          ),
        ),
      );
      expect(store.close, throwsStateError);
      expect(store.profile(writer)!.revoked, isFalse);
    } finally {
      resume.complete();
      await held;
    }
    store.revoke(actor: author, target: writer);
    expect(store.profile(writer)!.revoked, isTrue);
  });

  test(
    'failed sections release the queue and preserve the original error',
    () async {
      final original = StateError('Failed universe check');
      final failed = store.withAuthority<int>(() async => throw original);
      final next = store.withAuthority(
        () => store.validationAuthoritySequence(writer, universe),
      );
      await expectLater(failed, throwsA(same(original)));
      expect(await next, BigInt.zero);
    },
  );

  test(
    'nested sections reject instead of deadlocking and the next section runs',
    () async {
      await store.withAuthority(() async {
        await expectLater(store.withAuthority(() => 1), throwsStateError);
      });
      expect(await store.withAuthority(() => 2), 2);
      store.close();
      await expectLater(store.withAuthority(() => 3), throwsStateError);
    },
  );
}
