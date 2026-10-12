@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_client/archive_transfer.dart';
import 'package:ub_client/local_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/local_socket.dart';
import 'package:ub_store/profile_credentials.dart';
import 'package:ub_store/sqlite.dart';
import 'package:ub_store/src/ownership.dart';

void main() {
  late Directory root;
  late ProfileId author, writer;
  late LocalSqliteEngineServer server;
  late List<LocalEngineClient> clients;
  late List<Socket> sockets;
  EngineHello hello(ProfileId profile, {String? credential}) => EngineHello(
    protocolVersion: protocolVersion,
    profileId: profile,
    credential: Credential(
      credential ??
          ProfileCredentialStore.read(root: root.path, profile: profile),
    ),
    clientName: 'Disposable transport client',
  );
  setUp(() async {
    root = Directory('/tmp').createTempSync('ub-engine-');
    clients = [];
    sockets = [];
    final store = SqliteInstallationStore.create(root.path);
    try {
      final authority = InstallationAuthority(store);
      author = authority.initializeAuthor();
      writer = authority.enroll(authority.authenticateHello(hello(author)));
    } finally {
      store.close();
    }
    server = await LocalSqliteEngineServer.start(root.path);
  });
  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
    root.deleteSync(recursive: true);
  });
  Future<LocalEngineClient> client(ProfileId profile) async {
    final result = await LocalEngineClient.connect(
      root: root.path,
      profile: profile,
      clientName: 'Disposable author',
    );
    clients.add(result);
    return result;
  }

  Future<(Socket, StreamIterator<Uint8List>)> raw(EngineHello greeting) async {
    final socket = await Socket.connect(
      InternetAddress(
        '${root.path}/engine.sock',
        type: InternetAddressType.unix,
      ),
      0,
    );
    sockets.add(socket);
    final frames = StreamIterator(decodeLengthPrefixedFrames(socket));
    socket.add(encodeLengthPrefixedFrame(greeting.toWire().toBytes()));
    await socket.flush();
    return (socket, frames);
  }

  CanonicalValue field(CanonicalValue value, String key) =>
      (value as CanonicalObject).fields.singleWhere((f) => f.key == key).value;

  test('move recovery metadata crosses the authenticated socket after restart without exposing paths', () async {
    final original = await client(author);
    final created = await original.call(
      CreateUniverseEngineRequest(
        name: 'Recoverable move',
        start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
      ),
    );
    final universe = UniverseId.parse(
      wireString(field(created, 'universe_id')),
    );
    await original.call(
      StageSourceEngineRequest(
        universe: const Selector('Recoverable move'),
        label: 'Exact multiline source',
        text: List.filled(50000, 'é😀\r\n').join(),
      ),
    );
    final operation = OperationId.generate(), target = OperationId.generate();
    final request = StageMoveEngineRequest(
      universeId: universe,
      operationId: operation,
      targetInstance: target,
    );
    final denied = await client(writer);
    await expectLater(denied.call(request), throwsA(isA<ProtocolError>()));
    await denied.close();
    final staged = await original.call(request);
    expect(wireString(field(staged, 'digest')), hasLength(64));
    expect(
      BigInt.parse((field(staged, 'bytes') as CanonicalNumber).digits),
      greaterThan(BigInt.zero),
    );
    expect(
      (field(
        field(staged, 'manifest'),
        'includes_history',
      ) as CanonicalBool).value,
      isTrue,
    );
    expect(
      (field(
        field(staged, 'manifest'),
        'includes_workflow',
      ) as CanonicalBool).value,
      isTrue,
    );
    expect(staged.toText(), isNot(contains(root.path)));
    expect((await original.call(request)).toText(), staged.toText());
    final firstChunk = await original.call(
      ReadMoveChunkEngineRequest(
        universeId: universe,
        operationId: operation,
        targetInstance: target,
        ordinal: 0,
      ),
    );
    await original.close();
    await server.close();
    final installation = SqliteInstallationStore.openExisting(root.path);
    try {
      expect(
        installation.audit(author).where((e) => e.action == 'quiesce_move'),
        hasLength(1),
      );
    } finally {
      installation.close();
    }
    server = await LocalSqliteEngineServer.start(root.path);
    final owner = await client(author);
    expect((await owner.call(request)).toText(), staged.toText());
    ReadMoveChunkEngineRequest chunkRequest(
      int ordinal, {
      OperationId? destination,
    }) => ReadMoveChunkEngineRequest(
      universeId: universe,
      operationId: operation,
      targetInstance: destination ?? target,
      ordinal: ordinal,
    );
    final downloaded = '${root.path}/download.sqlite';
    protectedFile(downloaded, createNew: true);
    final output = File(downloaded).openSync(mode: FileMode.writeOnly);
    var received = 0, ordinal = 0;
    final bytes = int.parse((field(staged, 'bytes') as CanonicalNumber).digits);
    try {
      while (received < bytes) {
        final reply = await owner.call(chunkRequest(ordinal));
        if (ordinal == 0) expect(reply.toText(), firstChunk.toText());
        final chunk = MoveArchiveChunk.fromWire(reply);
        expect(chunk.ordinal, ordinal++);
        expect(
          chunk.content.length,
          lessThanOrEqualTo(ReadMoveChunkEngineRequest.chunkBytes),
        );
        output.writeFromSync(chunk.content);
        received += chunk.content.length;
        expect(
          (await owner.call(chunkRequest(chunk.ordinal))).toText(),
          reply.toText(),
        );
      }
      output.flushSync();
    } finally {
      output.closeSync();
    }
    expect(received, bytes);
    expect(ordinal, greaterThan(1));
    final archive = OwnedSqliteDatabase.stageLogicalArchive(
      downloaded,
      root.path,
    );
    try {
      expect(archive.digest, wireString(field(staged, 'digest')));
    } finally {
      archive.close();
    }
    await expectLater(
      owner.call(chunkRequest(ordinal)),
      throwsA(isA<ProtocolError>()),
    );
    await expectLater(
      owner.call(chunkRequest(0, destination: OperationId.generate())),
      throwsA(isA<ProtocolError>()),
    );
    final page = await owner.call(const ListMovesEngineRequest(limit: 1));
    expect((field(page, 'moves') as CanonicalArray).items, hasLength(1));
    final report = await owner.call(
      GetMoveEngineRequest(operationId: operation),
    );
    expect(wireString(field(report, 'state')), 'suspended');
    expect(wireString(field(report, 'universe_id')), universe.value);
    expect(wireString(field(report, 'target_instance')), target.value);
    expect(report.toText(), isNot(contains(root.path)));
    expect(
      report.toText(),
      isNot(
        contains(ProfileCredentialStore.read(root: root.path, profile: author)),
      ),
    );
    final contributor = await client(writer);
    await expectLater(
      contributor.call(chunkRequest(0)),
      throwsA(isA<ProtocolError>()),
    );
    await expectLater(contributor.call(request), throwsA(isA<ProtocolError>()));
    await expectLater(
      contributor.call(const ListMovesEngineRequest()),
      throwsA(isA<ProtocolError>()),
    );
    await expectLater(
      contributor.call(GetMoveEngineRequest(operationId: operation)),
      throwsA(isA<ProtocolError>()),
    );
  });

  test('socket transfer resumes target upload after restart and reviews exact retained bytes before admission', () async {
    final targetRoot = '${root.path}/target';
    final targetStore = SqliteInstallationStore.create(targetRoot);
    final targetAuthority = InstallationAuthority(targetStore);
    final targetAuthor = targetAuthority.initializeAuthor();
    final targetInstance = targetStore.instanceId;
    targetStore.close();
    var targetServer = await LocalSqliteEngineServer.start(targetRoot);
    Future<LocalEngineClient> destination() async {
      final connection = await LocalEngineClient.connect(
        root: targetRoot,
        profile: targetAuthor,
        clientName: 'Disposable target',
      );
      clients.add(connection);
      return connection;
    }

    var destinationClient = await destination();
    try {
      final source = await client(author);
      final created = await source.call(
        CreateUniverseEngineRequest(
          name: 'Transfer source',
          start: const GregorianUniverseStart('2040-01-01T00:00:00Z'),
        ),
      );
      await source.call(
        StageSourceEngineRequest(
          universe: const Selector('Transfer source'),
          label: 'Retained source',
          text: List.filled(50000, 'é😀\r\n').join(),
        ),
      );
      final universe = UniverseId.parse(
        wireString(field(created, 'universe_id')),
      );
      final operation = OperationId.generate(),
          uploadId = OperationId.generate();
      final stage = await source.call(
        StageMoveEngineRequest(
          universeId: universe,
          operationId: operation,
          targetInstance: targetInstance,
        ),
      );
      final begin = BeginArchiveUploadEngineRequest(
        uploadId: uploadId,
        digest: wireString(field(stage, 'digest')),
        bytes: int.parse((field(stage, 'bytes') as CanonicalNumber).digits),
      );
      final wrongDigest = BeginArchiveUploadEngineRequest(
        uploadId: OperationId.generate(),
        digest: '0' * 64,
        bytes: begin.bytes,
      );
      await destinationClient.call(wrongDigest);
      final review = ReviewArchiveUploadEngineRequest(
        uploadId: uploadId,
        name: 'Transferred universe',
        mode: ImportMode.restore,
      );
      await destinationClient.call(begin);
      await expectLater(
        destinationClient.call(review),
        throwsA(isA<ProtocolError>()),
      );
      await expectLater(
        destinationClient.call(
          BeginArchiveUploadEngineRequest(
            uploadId: uploadId,
            digest: '0' * 64,
            bytes: begin.bytes,
          ),
        ),
        throwsA(isA<ProtocolError>()),
      );
      final denied = await client(writer);
      await expectLater(denied.call(begin), throwsA(isA<ProtocolError>()));
      var received = 0, ordinal = 0;
      while (received < begin.bytes) {
        final chunk = MoveArchiveChunk.fromWire(
          await source.call(
            ReadMoveChunkEngineRequest(
              universeId: universe,
              operationId: operation,
              targetInstance: targetInstance,
              ordinal: ordinal,
            ),
          ),
        );
        final write = WriteArchiveChunkEngineRequest(
          uploadId: uploadId,
          chunk: chunk,
        );
        await destinationClient.call(
          WriteArchiveChunkEngineRequest(
            uploadId: wrongDigest.uploadId,
            chunk: chunk,
          ),
        );
        final progress = await destinationClient.call(write);
        expect(
          (await destinationClient.call(write)).toText(),
          progress.toText(),
        );
        received += chunk.content.length;
        ordinal++;
        if (ordinal == 1) {
          final changed = Uint8List.fromList(chunk.content)..[0] ^= 1;
          await expectLater(
            destinationClient.call(
              WriteArchiveChunkEngineRequest(
                uploadId: uploadId,
                chunk: MoveArchiveChunk(ordinal: 0, content: changed),
              ),
            ),
            throwsA(isA<ProtocolError>()),
          );
          await destinationClient.close();
          await targetServer.close();
          targetServer = await LocalSqliteEngineServer.start(targetRoot);
          destinationClient = await destination();
          expect(
            (await destinationClient.call(begin)).toText(),
            progress.toText(),
          );
          await expectLater(
            destinationClient.call(review),
            throwsA(isA<ProtocolError>()),
          );
        }
      }
      expect(ordinal, greaterThan(1));
      await expectLater(
        destinationClient.call(
          ReviewArchiveUploadEngineRequest(
            uploadId: wrongDigest.uploadId,
            name: 'Rejected digest',
            mode: ImportMode.restore,
          ),
        ),
        throwsA(isA<ProtocolError>()),
      );
      // Recover a crash after the deterministic archive publish but before
      // import-preview commit, retaining the exact protected original bytes.
      final retained = '$targetRoot/imports/${uploadId.value}.sqlite';
      protectedFile(retained, createNew: true);
      File(retained).writeAsBytesSync(
        File('${root.path}/moves/${operation.value}.sqlite').readAsBytesSync(),
      );
      final preview = await prepareMoveTransfer(
        source: source.call,
        target: destinationClient.call,
        move: StageMoveEngineRequest(
          universeId: universe,
          operationId: operation,
          targetInstance: targetInstance,
        ),
        uploadId: uploadId,
        name: 'Transferred universe',
      );
      expect(wireString(field(preview, 'preview_id')), uploadId.value);
      expect(wireString(field(preview, 'target_universe')), universe.value);
      expect(
        (field(preview, 'includes_workflow') as CanonicalBool).value,
        isTrue,
      );
      expect(preview.toText(), isNot(contains(root.path)));
      expect((await destinationClient.call(review)).toText(), preview.toText());
      await expectLater(
        destinationClient.call(
          ReviewArchiveUploadEngineRequest(
            uploadId: uploadId,
            name: 'Changed target',
            mode: ImportMode.restore,
          ),
        ),
        throwsA(isA<ProtocolError>()),
      );
      await destinationClient.close();
      await targetServer.close();
      targetServer = await LocalSqliteEngineServer.start(targetRoot);
      destinationClient = await destination();
      expect((await destinationClient.call(review)).toText(), preview.toText());
      final accept = AcceptImportEngineRequest(
        previewId: uploadId,
        digest: wireString(field(preview, 'digest')),
      );
      final receipt = await destinationClient.call(accept);
      expect((await destinationClient.call(accept)).toText(), receipt.toText());
      expect(wireString(field(receipt, 'universe_id')), universe.value);
      final catalog = field(
        await destinationClient.call(const StatusEngineRequest()),
        'universes',
      ) as CanonicalArray;
      expect(catalog.items, hasLength(1));
      expect(wireString(field(catalog.items.single, 'id')), universe.value);
    } finally {
      await destinationClient.close();
      await targetServer.close();
    }
  });

  test('real client authenticates, executes service operations and retains enrollment across restart', () async {
    checkLocalSocketEndpoint('${root.path}/engine.sock');
    final connection = await client(author);
    expect(connection.welcome.author, isTrue);
    final status = await connection.call(const StatusEngineRequest());
    expect(
      field(status, 'principal').toText(),
      CanonicalString(author.value).toText(),
    );
    final enrolled = await connection.call(const EnrollEngineRequest());
    expect(enrolled.toText(), isNot(contains('credential')));
    final profiles = await connection.call(const ProfilesEngineRequest());
    expect(profiles.toText(), contains(writer.value));
    final instance = connection.welcome.serviceInstance;
    await connection.close();
    await server.close();
    expect(
      FileSystemEntity.typeSync('${root.path}/engine.sock', followLinks: false),
      FileSystemEntityType.notFound,
    );
    server = await LocalSqliteEngineServer.start(root.path);
    final restarted = await client(author);
    expect(restarted.welcome.serviceInstance, isNot(instance));
    expect(
      (await restarted.call(const ProfilesEngineRequest())).toText(),
      profiles.toText(),
    );
  });

  test(
    'current revocation is enforced on an already authenticated connection',
    () async {
      final human = await client(author), agent = await client(writer);
      expect(agent.welcome.author, isFalse);
      await expectLater(
        agent.call(const EnrollEngineRequest()),
        throwsA(isA<ProtocolError>()),
      );
      await agent.call(const StatusEngineRequest());
      await human.call(RevokeEngineRequest(profileId: writer));
      await expectLater(
        agent.call(const StatusEngineRequest()),
        throwsA(isA<ProtocolError>()),
      );
      await human.call(const StatusEngineRequest());
    },
  );

  test('author shutdown returns its acknowledgement, removes endpoint and releases installation ownership', () async {
    final human = await client(author);
    await human.call(const ShutdownEngineRequest());
    await server.done.timeout(const Duration(seconds: 5));
    await server.close();
    expect(
      FileSystemEntity.typeSync('${root.path}/engine.sock', followLinks: false),
      FileSystemEntityType.notFound,
    );
    final reopened = SqliteInstallationStore.openExisting(root.path);
    reopened.close();
  });

  test('wrong credential is refused without a welcome', () async {
    final (_, frames) = await raw(
      hello(writer, credential: 'Disposable wrong credential'),
    );
    expect(
      await frames.moveNext().timeout(const Duration(seconds: 5)),
      isFalse,
    );
    await frames.cancel();
    await (await client(author)).call(const StatusEngineRequest());
  });

  test(
    'duplicate request ID closes transport before repeating a mutation',
    () async {
      final (socket, frames) = await raw(hello(author));
      expect(await frames.moveNext(), isTrue);
      final call = EngineCall(
        id: BigInt.from(9),
        request: const EnrollEngineRequest(),
      );
      final bytes = encodeLengthPrefixedFrame(call.toWire().toBytes());
      socket.add(bytes);
      await socket.flush();
      expect(await frames.moveNext(), isTrue);
      expect(EngineReply.decode(frames.current).id, call.id);
      final human = await client(author);
      final before = (await human.call(const ProfilesEngineRequest())).toText();
      socket.add(bytes);
      await socket.flush();
      expect(await frames.moveNext(), isFalse);
      expect(
        (await human.call(const ProfilesEngineRequest())).toText(),
        before,
      );
      await frames.cancel();
    },
  );

  test('principal connection admission refuses ninth connection and recovers released slot', () async {
    final active = <LocalEngineClient>[];
    for (var i = 0; i < 8; i++) {
      active.add(await client(author));
    }
    await expectLater(client(author), throwsA(isA<LocalEngineException>()));
    await active.removeLast().close();
    // The server observes the closed connection before a new admission attempt.
    await (await client(writer)).call(const StatusEngineRequest());
    final next = await client(author);
    await next.call(const StatusEngineRequest());
  });

  test('second server cannot remove the active endpoint or acquire its installation', () async {
    await expectLater(
      LocalSqliteEngineServer.start(root.path),
      throwsA(isA<LocalEngineServerException>()),
    );
    await (await client(author)).call(const StatusEngineRequest());
  });

  test('startup preserves unsafe existing endpoint and releases failed startup lock', () async {
    await server.close();
    final retained = File('${root.path}/engine.sock')
      ..writeAsStringSync('Retained author file');
    await expectLater(
      LocalSqliteEngineServer.start(root.path),
      throwsA(isA<LocalEngineServerException>()),
    );
    expect(retained.readAsStringSync(), 'Retained author file');
    final reopened = SqliteInstallationStore.openExisting(root.path);
    reopened.close();
    retained.deleteSync();
  });

  test('public envelope carries the exact request ID and created universe survives restart', () async {
    final human = await client(author);
    final created = await human.call(
      const CreateUniverseEngineRequest(
        name: 'Transport world',
        start: GregorianUniverseStart('2040-03-15T12:30:00+02:00'),
      ),
    );
    final universe = UniverseId.parse(
      (field(created, 'universe_id') as CanonicalString).value,
    );
    final (socket, frames) = await raw(hello(author));
    expect(await frames.moveNext(), isTrue);
    final id = BigInt.parse('18446744073709551615');
    final request = ToolEngineRequest(
      request: DescribeSummaryRequest(
        universe: const Selector('Transport world'),
        universeId: universe,
      ),
    );
    socket.add(
      encodeLengthPrefixedFrame(
        EngineCall(id: id, request: request).toWire().toBytes(),
      ),
    );
    await socket.flush();
    expect(await frames.moveNext(), isTrue);
    final reply = EngineReply.decode(frames.current);
    expect(reply.id, id);
    expect(reply.result, isA<EngineSuccess>());
    final envelope = Envelope.fromWire(
      (reply.result as EngineSuccess).value,
      (v) => v,
    );
    expect(envelope.requestId, id);
    await frames.cancel();
    await server.close();
    server = await LocalSqliteEngineServer.start(root.path);
    expect(
      (await (await client(author)).call(const StatusEngineRequest())).toText(),
      contains(universe.value),
    );
  });

  test(
    'silent unauthenticated socket expires at the handshake deadline',
    () async {
      final socket = await Socket.connect(
        InternetAddress(
          '${root.path}/engine.sock',
          type: InternetAddressType.unix,
        ),
        0,
      );
      sockets.add(socket);
      expect(
        await socket.toList().timeout(const Duration(seconds: 8)),
        isEmpty,
      );
      await (await client(author)).call(const StatusEngineRequest());
    },
  );

  test(
    'shutdown closes incomplete handshakes without waiting for their deadline',
    () async {
      final socket = await Socket.connect(
        InternetAddress(
          '${root.path}/engine.sock',
          type: InternetAddressType.unix,
        ),
        0,
      );
      sockets.add(socket);
      final ended = socket.toList();
      await server.close().timeout(const Duration(seconds: 2));
      expect(await ended, isEmpty);
      final reopened = SqliteInstallationStore.openExisting(root.path);
      reopened.close();
    },
  );
}
