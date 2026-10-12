@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/postgres_runtime.dart';
import 'package:ub_store/postgres_installation.dart';
import 'package:ub_store/src/postgres_authority_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL runtime across OS processes',
    () {
      late Directory build;
      late String executable;
      late PostgresInstallationStore store;
      late NativePostgresRuntime runtime;
      late NativePostgresConnection author;
      late Connection observer;
      late ProfileId authorId, writerId;
      final universes = <UniverseId>[];
      final peers = <_Peer>[];
      Endpoint endpoint() => Endpoint(
        host: '127.0.0.1',
        port: port!,
        database: 'ub_disposable',
        username: 'postgres',
      );
      setUpAll(() async {
        build = Directory.systemTemp.createTempSync(
          'universe-builder-process-build-',
        );
        final vm = File(Platform.resolvedExecutable);
        final dart = vm.uri.pathSegments.last == 'dartvm'
            ? '${vm.parent.path}/dart'
            : vm.path;
        final result = await Process.run(dart, [
          'build',
          'cli',
          '-o',
          build.path,
          '--target',
          'test/helpers/postgres_runtime_process.dart',
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        executable = '${build.path}/bundle/bin/postgres_runtime_process';
      });
      tearDownAll(() => build.deleteSync(recursive: true));
      setUp(() async {
        universes.clear();
        peers.clear();
        observer = await Connection.open(
          endpoint(),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        store = await PostgresInstallationStore.create(
          endpoint(),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        authorId = ProfileId.generate();
        writerId = ProfileId.generate();
        await store.transaction((s) async {
          final hash = sha256
              .convert(utf8.encode('disposable-process-profile'))
              .toString();
          await s.authority.enroll(id: authorId, credentialHash: hash);
          await s.authority.enroll(
            id: writerId,
            credentialHash: hash,
            actor: authorId,
          );
        });
        runtime = NativePostgresRuntime(store: store);
        author = await runtime.connect(
          EngineHello(
            protocolVersion: protocolVersion,
            profileId: authorId,
            credential: const Credential('disposable-process-profile'),
            clientName: 'Disposable parent',
          ),
        );
      });
      tearDown(() async {
        for (final peer in peers) {
          await peer.close();
        }
        await runtime.close();
        await store.close();
        try {
          for (final universe in universes) {
            await observer.execute(
              'DROP SCHEMA IF EXISTS ${postgresUniverseSchema(universe)} CASCADE',
            );
          }
          await observer.execute(
            'DROP SCHEMA IF EXISTS ${postgresAuthorityNamespace(store.instanceId)} CASCADE',
          );
        } finally {
          await observer.close();
        }
      });
      Future<_Peer> peer(ProfileId id) async {
        final process = await Process.start(executable, ['$port', id.value]);
        final value = _Peer(process);
        peers.add(value);
        expect(
          await value.lines.moveNext().timeout(const Duration(seconds: 30)),
          isTrue,
        );
        expect(value.lines.current, 'ready');
        return value;
      }

      Future<WireFields> create(String name) async {
        final result = WireFields(
          await author.execute(
            CreateUniverseEngineRequest(
              name: name,
              start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
            ),
          ),
          {'universe_id', 'continuity_id', 'context_id', 'revision', 'name'},
        );
        universes.add(UniverseId.parse(result.string('universe_id')));
        return result;
      }

      test('connected child observes grant withdrawal and profile revocation without restart', () async {
        final created = await create('Visible campaign');
        final universe = UniverseId.parse(created.string('universe_id'));
        await author.execute(
          GrantEngineRequest(
            grant: GrantSpec(
              profileId: writerId,
              universeId: universe,
              worlds: null,
              propose: true,
              edit: true,
              protected: true,
            ),
          ),
        );
        final child = await peer(writerId);
        const status = StatusEngineRequest();
        int visible(CanonicalValue result) => WireFields(result, {
          'service_instance',
          'universes',
          'canonical_commit',
          'max_requests_per_principal',
          'universe_queue_capacity',
        }).array('universes').length;
        expect(visible(await child.execute(status)), 1);
        await author.execute(
          WithdrawGrantEngineRequest(profileId: writerId, universeId: universe),
        );
        expect(visible(await child.execute(status)), 0);
        await author.execute(RevokeEngineRequest(profileId: writerId));
        expect(
          await child.response(status),
          containsPair('error', 'NotFoundOrNotAccessibleError'),
        );
      });
      test('two author processes serialize competing drafts and keep universe state isolated', () async {
        final first = await create('Campaign é😀');
        final second = await create('Memoir');
        final child = await peer(authorId);
        SaveDraftEngineRequest save(
          WireFields created,
          String name,
          String rationale,
        ) => SaveDraftEngineRequest(
          universe: Selector(name),
          continuityId: ContinuityId.parse(created.string('continuity_id')),
          expectedVersion: BigInt.zero,
          content: DraftContent(
            baseRevision: RevisionId.parse(created.string('revision')),
            representedContext: RecordId.parse(created.string('context_id')),
            operations: const [],
            rationale: rationale,
            proposal: null,
          ),
        );
        final childSave = child.response(
          save(first, 'Campaign é😀', 'Child exact text é😀'),
        );
        final parentSave = author
            .execute(save(first, 'Campaign é😀', 'Parent exact text'))
            .then<Object>((result) => result, onError: (Object error) => error);
        final childResult = await childSave;
        final parentResult = await parentSave;
        expect(
          childResult.containsKey('result') != (parentResult is CanonicalValue),
          isTrue,
        );
        if (childResult.containsKey('error')) {
          expect(childResult['error'], 'BaseRevisionConflictError');
        } else {
          expect(parentResult, isA<BaseRevisionConflictError>());
        }
        await child.execute(save(second, 'Memoir', 'Independent memoir'));
        Future<CanonicalValue> load(String name, WireFields created) =>
            author.execute(
              LoadDraftEngineRequest(
                universe: Selector(name),
                continuityId: ContinuityId.parse(
                  created.string('continuity_id'),
                ),
              ),
            );
        final firstDraft = await load('Campaign é😀', first);
        final secondDraft = await load('Memoir', second);
        expect(
          firstDraft.toText(),
          contains(
            childResult.containsKey('result')
                ? 'Child exact text é😀'
                : 'Parent exact text',
          ),
        );
        expect(secondDraft.toText(), contains('Independent memoir'));
        expect(secondDraft.toText(), isNot(contains('exact text')));
        await child.close();
        peers.remove(child);
        final restarted = await peer(authorId);
        for (final (name, created, expected) in [
          ('Campaign é😀', first, firstDraft),
          ('Memoir', second, secondDraft),
        ]) {
          final recovered = await restarted.execute(
            LoadDraftEngineRequest(
              universe: Selector(name),
              continuityId: ContinuityId.parse(created.string('continuity_id')),
            ),
          );
          expect(recovered.toText(), expected.toText());
        }
        final retry = await restarted.execute(
          save(
            first,
            'Campaign é😀',
            childResult.containsKey('result')
                ? 'Child exact text é😀'
                : 'Parent exact text',
          ),
        );
        expect(retry.toText(), firstDraft.toText());
        for (final id in universes) {
          await store.transaction((s) => s.verifyUniverse(id, complete: true));
        }
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT to a disposable PostgreSQL instance'
        : false,
  );
}

final class _Peer {
  _Peer(this.process)
    : lines = StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ) {
    errors = process.stderr.transform(utf8.decoder).join();
  }
  final Process process;
  final StreamIterator<String> lines;
  late final Future<String> errors;
  Future<Map<String, dynamic>> response(EngineRequest request) async {
    process.stdin.writeln(request.toWire().toText());
    await process.stdin.flush();
    if (!await lines.moveNext().timeout(const Duration(seconds: 30))) {
      throw StateError('Peer exited: ${await errors}');
    }
    return jsonDecode(lines.current) as Map<String, dynamic>;
  }

  Future<CanonicalValue> execute(EngineRequest request) async {
    final result = await response(request);
    if (result.containsKey('error')) {
      throw StateError('Peer request failed: ${result['error']}');
    }
    return CanonicalValue.parseJson(result['result'] as String);
  }

  Future<void> close() async {
    await process.stdin.close();
    try {
      await process.exitCode.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
    await lines.cancel();
    await errors;
  }
}
