@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:ub_cli/universe_cli.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

void main() {
  late Directory root;
  late ProfileId author, writer;
  late LocalSqliteEngineServer server;
  late List<String> output, errors;
  setUp(() async {
    root = Directory('/tmp').createTempSync('ub-cli-');
    output = [];
    errors = [];
    final store = SqliteInstallationStore.create(root.path);
    try {
      final authority = InstallationAuthority(store);
      author = authority.initializeAuthor();
      writer = authority.enroll(
        authority.authenticate(
          profile: author,
          credential: Credential(
            ProfileCredentialStore.read(root: root.path, profile: author),
          ),
        ),
      );
    } finally {
      store.close();
    }
    server = await LocalSqliteEngineServer.start(root.path);
  });
  tearDown(() async {
    await server.close();
    root.deleteSync(recursive: true);
  });
  Future<int> run(
    List<String> command, {
    ProfileId? principal,
    Future<Uint8List> Function()? input,
  }) => runUniverseCli(
    [
      '--installation',
      root.path,
      '--profile',
      (principal ?? author).value,
      ...command,
    ],
    output: output.add,
    error: errors.add,
    engineHelper: () async => '${root.path}/missing/universe-engine',
    readInput: input,
  );
  CanonicalValue field(CanonicalValue object, String key) =>
      (object as CanonicalObject).fields.singleWhere((f) => f.key == key).value;
  CanonicalValue result() => CanonicalValue.parseWireJson(output.last);

  test('author commands create canon, stage exact sources and apply current grant/revocation permissions', () async {
    expect(
      await run([
        'create',
        'CLI world',
        '--first-time=2040-03-15T12:30:00+02:00',
      ]),
      0,
    );
    final universe = (field(result(), 'universe_id') as CanonicalString).value;
    final toolFile = File('${root.path}/tool.json')
      ..writeAsStringSync(
        DescribeSummaryRequest(universe: const Selector('CLI world'))
            .toWire()
            .toText(),
      );
    expect(await run(['tool', toolFile.path]), 0);
    expect(Envelope.fromWire(result(), (v) => v).requestId, BigInt.one);
    expect(await run(['library', 'CLI world']), 0);
    final file = File('${root.path}/notes.txt')
      ..writeAsStringSync('\uFEFFExact source café 世界\r\n');
    final sourceRequest = await parseAuthorCommand('stage-source', [
      'CLI world',
      'Private notes',
      file.path,
    ]) as StageSourceEngineRequest;
    expect(sourceRequest.text, '\uFEFFExact source café 世界\r\n');
    expect(
      await run(['stage-source', 'CLI world', 'Private notes', file.path]),
      0,
    );
    expect(await run(['library', 'CLI world'], principal: writer), 1);
    expect(await run(['grant', writer.value, universe, '--propose']), 0);
    expect(await run(['status'], principal: writer), 0);
    expect(output.last, contains(universe));
    expect(await run(['enroll'], principal: writer), 1);
    expect(await run(['rename', universe, 'Renamed CLI world']), 0);
    expect(await run(['doctor']), 0);
    final archive = '${root.path}/export.sqlite';
    expect(
      await run(['export', 'Renamed CLI world', archive, '--complete-history']),
      0,
    );
    expect(
      await run(['preview-import', archive, 'Clone from CLI', '--clone']),
      0,
    );
    final preview = (field(result(), 'preview_id') as CanonicalString).value;
    final digest = (field(result(), 'digest') as CanonicalString).value;
    expect(await run(['accept-import', preview, digest]), 0);
    expect(field(result(), 'imported'), const CanonicalBool(true));
    expect(await run(['status']), 0);
    expect(output.last, contains('Clone from CLI'));
    expect(await run(['revoke', writer.value]), 0);
    expect(await run(['status'], principal: writer), 1);
    expect(await run(['status']), 0);
    expect(
      errors.join(),
      isNot(
        contains(ProfileCredentialStore.read(root: root.path, profile: author)),
      ),
    );
  });

  test('exact approval references and explicit world grants survive CLI parsing without numeric rounding', () async {
    final proposal = ProposalId.generate(),
        validation = ValidationRunId.generate();
    final parsed = await parseAuthorCommand('approve', [
      'Universe',
      proposal.value,
      '18446744073709551615',
      'exact authored digest',
      validation.value,
    ]) as ApproveEngineRequest;
    expect(
      parsed.proposalReference.version,
      BigInt.parse('18446744073709551615'),
    );
    expect(parsed.proposalReference.digest, 'exact authored digest');
    expect(parsed.validationRun, validation);
    final world = WorldId.generate(), universe = UniverseId.generate();
    final restricted = await parseAuthorCommand('grant', [
      writer.value,
      universe.value,
      '--world',
      world.value,
      '--edit',
      '--protected',
    ]) as GrantEngineRequest;
    expect(restricted.grant.worlds, [world]);
    expect(restricted.grant.propose, isFalse);
    expect(restricted.grant.edit, isTrue);
    expect(restricted.grant.limits.delegatedCommit, isFalse);
    final unrestricted = await parseAuthorCommand('grant', [
      writer.value,
      universe.value,
    ]) as GrantEngineRequest;
    expect(unrestricted.grant.worlds, isNull);
    final creation = await parseAuthorCommand('create', [
      'World',
      '--calendar',
      'Aurora',
      '--first-time',
      '9007199254740993',
      '--tick-label',
      'days',
      '--ticks-per-month=36',
    ]) as CreateUniverseEngineRequest;
    expect(
      (creation.start as FictionalUniverseStart).initialTick,
      '9007199254740993',
    );
  });

  test('invalid commands and malformed or oversized private input fail before helper lookup', () async {
    var helperCalls = 0;
    final proposal = ProposalId.generate(),
        validation = ValidationRunId.generate();
    for (final command in <List<String>>[
      ['unknown'],
      ['status', 'extra'],
      ['create', 'World'],
      [
        'create',
        'World',
        '--first-time',
        '2040-01-01T00:00:00Z',
        '--tick-label',
        'days',
      ],
      ['create', 'World', '--first-time', '1', '--calendar', 'Era'],
      ['create', 'World', '--first-time', '1', '--first-time', '2'],
      [
        'approve',
        'World',
        proposal.value,
        '18446744073709551616',
        'digest',
        validation.value,
      ],
      ['maintain', 'World', '--collect=false'],
    ]) {
      expect(
        await runUniverseCli(
          ['--installation', root.path, '--profile', author.value, ...command],
          output: output.add,
          error: errors.add,
          engineHelper: () async {
            helperCalls++;
            return '/missing/universe-engine';
          },
        ),
        2,
      );
    }
    expect(helperCalls, 0);
    for (final bytes in [
      Uint8List.fromList([255]),
      Uint8List.fromList(
        utf8.encode('{"action":"inspect","action":"publish"}'),
      ),
      Uint8List(1000001),
    ]) {
      expect(
        await run(['author-writing', 'World'], input: () async => bytes),
        2,
      );
    }
    expect(output, isEmpty);
  });

  test('private stdin uses its closed author-action contract and cannot be substituted with a public tool', () async {
    final action = InspectWritingAction(
      candidate: ProposalRef(
        proposalId: ProposalId.generate(),
        version: BigInt.parse('9007199254740993'),
        digest: 'exact digest',
      ),
    );
    final request = await parseAuthorCommand(
      'author-writing',
      ['World'],
      readInput: () async => action.toWire().toBytes(),
    ) as AuthorWritingEngineRequest;
    expect(request.action.toWire().toText(), action.toWire().toText());
    final public = DescribeSummaryRequest(universe: const Selector('World'));
    await expectLater(
      parseAuthorCommand('author-writing', [
        'World',
      ], readInput: () async => public.toWire().toBytes()),
      throwsFormatException,
    );
    await expectLater(
      parseAuthorCommand(
        'author-writing',
        ['World'],
        readInput: () async => Uint8List.fromList(
          utf8.encode('\uFEFF${action.toWire().toText()}'),
        ),
      ),
      throwsFormatException,
    );
    final source = File('${root.path}/invalid-source')..writeAsBytesSync([255]);
    expect(await run(['stage-source', 'World', 'Label', source.path]), 2);
  });

  test('standalone universe command uses its installed sibling for initialization and on-demand authoring', () async {
    await server.close();
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:ub_cli/universe_cli.dart'),
    );
    final app = File.fromUri(library!).parent.parent;
    final workspace = app.parent.parent;
    final builds = [
      ('${app.path}/bin/universe.dart', '${root.path}/cli-build'),
      (
        '${workspace.path}/apps/ub_engine/bin/universe-engine.dart',
        '${root.path}/engine-build',
      ),
    ];
    for (final (entry, destination) in builds) {
      final built = await Process.run(Platform.resolvedExecutable, [
        'build',
        'cli',
        '--target',
        entry,
        '--output',
        destination,
        '--verbosity=error',
      ]);
      expect(
        built.exitCode,
        0,
        reason: 'Standalone command fixture compilation failed',
      );
    }
    final binary = '${root.path}/cli-build/bundle/bin/universe';
    Link('${root.path}/cli-build/bundle/bin/universe-engine')
        .createSync('${root.path}/engine-build/bundle/bin/universe-engine');
    const environment = {
      'PATH': '',
      'UB_USE_POSTGRES': 'false',
      'UB_POSTGRES_ENDPOINT': '',
    };
    final installation = '${root.path}/new-installation';
    Future<ProcessResult> invoke(List<String> command, {String? profile}) =>
        Process.run(
          binary,
          [
            '--installation',
            installation,
            if (profile != null) ...['--profile', profile],
            ...command,
          ],
          workingDirectory: root.path,
          environment: environment,
        ).timeout(const Duration(seconds: 20));
    final initialized = await invoke(['init']);
    expect(initialized.exitCode, 0);
    expect(initialized.stderr, isEmpty);
    final profile = ProfileId.parse((initialized.stdout as String).trim());
    try {
      final created = await invoke([
        'create',
        'Compiled world',
        '--first-time',
        '2040-01-01T00:00:00Z',
      ], profile: profile.value);
      expect(created.exitCode, 0);
      expect(created.stderr, isEmpty);
      final status = await invoke(['status'], profile: profile.value);
      expect(status.exitCode, 0);
      expect(status.stdout, contains('Compiled world'));
      expect(status.stderr, isEmpty);
    } finally {
      final shutdown = await invoke(['shutdown'], profile: profile.value);
      expect(shutdown.exitCode, 0);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      SqliteInstallationStore? retained;
      while (retained == null && DateTime.now().isBefore(deadline)) {
        try {
          retained = SqliteInstallationStore.openExisting(installation);
        } on Object {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }
      expect(retained, isNotNull);
      retained!.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
