import 'dart:io';
import 'dart:typed_data';

import 'package:ub_client/local_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'operator_cli.dart';

const _offline = {
  'convert-package',
  'convert-installation',
  'convert-credential',
};
const _usage = '''Usage: universe --installation <path> [--profile <id>] <command> [arguments]

init | status | doctor | enroll | shutdown
create <name> --first-time <value> [--calendar <name>] [--tick-label <label>] [--ticks-per-month <u32>]
register <path> <name> | rename <universe-id> <name> | revoke <profile-id>
grant <profile-id> <universe-id> [--world <id>]... [--propose] [--edit] [--protected]
tool <file> | library <universe>
review <universe> <proposal-id> <version> <digest>
approve <universe> <proposal-id> <version> <digest> <validation-run>
author-writing <universe>              Read exact private author action from stdin.
stage-source <universe> <label> <file>
backup <universe> <destination> | restore <source> <name>
maintain <universe> [--collect] | convert-legacy <source> <destination>
export <universe> <destination> [--record <id>]... [--complete-history]
preview-import <source> <name> [--clone] | accept-import <preview-id> <digest>
convert-package | convert-installation | convert-credential <source> <destination>

Every service command requires --profile except init. Offline conversions do not
authenticate, resolve backend settings, launch an engine or register packages.
Review and approval use exact proposal versions; publication remains separate.''';

Future<int> runUniverseCli(
  List<String> arguments, {
  required void Function(String) output,
  required void Function(String) error,
  Future<String> Function()? engineHelper,
  Future<Uint8List> Function()? readInput,
}) async {
  LocalEngineClient? client;
  try {
    String? root, profile;
    var index = 0;
    while (index < arguments.length && arguments[index].startsWith('-')) {
      final option = arguments[index++];
      if (option == '--help' || option == '-h') {
        output(_usage);
        return 0;
      }
      final equal = option.indexOf('=');
      final name = equal < 0 ? option : option.substring(0, equal);
      if (!{'--installation', '--profile'}.contains(name)) {
        throw const _UsageError();
      }
      final String value;
      if (equal < 0) {
        if (index == arguments.length || arguments[index].startsWith('-')) {
          throw const _UsageError();
        }
        value = arguments[index++];
      } else {
        value = option.substring(equal + 1);
      }
      if (value.isEmpty || value.contains('\u0000')) throw const _UsageError();
      if (name == '--installation') {
        if (root != null) throw const _UsageError();
        root = value;
      } else {
        if (profile != null) throw const _UsageError();
        profile = value;
      }
    }
    if (index == arguments.length) throw const _UsageError();
    final command = arguments[index++];
    if (_offline.contains(command)) {
      return runOperatorCli(arguments, output: output, error: error);
    }
    final tail = arguments.sublist(index);
    if (tail.length == 1 && {'--help', '-h'}.contains(tail.single)) {
      output(_usage);
      return 0;
    }
    if (root == null) throw const _UsageError();
    if (command == 'init') {
      if (tail.isNotEmpty) throw const _UsageError();
      final helper = await (engineHelper ?? LocalEngineClient.siblingEngine)();
      final initialized = await Process.run(helper, [
        '--installation',
        root,
        '--initialize',
      ]);
      if (initialized.exitCode != 0) {
        throw const LocalEngineException(LocalEngineFailure.unavailable);
      }
      final id = ProfileId.parse((initialized.stdout as String).trim());
      output(id.value);
      return 0;
    }
    if (profile == null) throw const _UsageError();
    final principal = ProfileId.parse(profile);
    final request = await parseAuthorCommand(
      command,
      tail,
      readInput: readInput,
    );
    // Reject an oversized request before launching an engine or sending a call.
    if (EngineCall(id: BigInt.one, request: request).toWire().toBytes().length >
        maxFrameBytes) {
      throw const _UsageError();
    }
    final helper = await (engineHelper ?? LocalEngineClient.siblingEngine)();
    client = await LocalEngineClient.ensureRunning(
      root: root,
      profile: principal,
      helper: helper,
      clientName: 'maintenance-cli',
    );
    output((await client.call(request)).toText());
    return 0;
  } on _UsageError {
    error(_usage);
    return 2;
  } on FormatException {
    error(
      'Invalid command arguments or request content. Use --help for the maintained command interface.',
    );
    return 2;
  } on ProtocolError catch (failure) {
    error(failure.toWire().toText());
    return 1;
  } on LocalEngineException catch (failure) {
    error(
      'Engine connection failed: ${failure.failure.name}. Inspect the operation outcome before retrying an interrupted request.',
    );
    return 1;
  } on Object {
    error(
      'Command failed; verify input files, installation ownership and current access.',
    );
    return 1;
  } finally {
    await client?.close();
  }
}

/// Maintained author command arguments compile to existing closed engine DTOs.
/// Parsing is separate from connection establishment and never grants authority.
Future<EngineRequest> parseAuthorCommand(
  String command,
  List<String> tokens, {
  Future<Uint8List> Function()? readInput,
}) async {
  final values = switch (command) {
    'create' => {'first-time', 'calendar', 'tick-label', 'ticks-per-month'},
    'grant' => {'world'},
    'export' => {'record'},
    _ => <String>{},
  };
  final flags = switch (command) {
    'grant' => {'propose', 'edit', 'protected'},
    'export' => {'complete-history'},
    'maintain' => {'collect'},
    'preview-import' => {'clone'},
    _ => <String>{},
  };
  final args = _Arguments(
    tokens,
    values: values,
    flags: flags,
    repeated: {'world', 'record'},
  );
  Selector universe() => Selector(args.positional[0]);
  ProposalRef proposal() => ProposalRef(
    proposalId: ProposalId.parse(args.positional[1]),
    version: BigInt.parse(args.positional[2]),
    digest: args.positional[3],
  );
  switch (command) {
    case 'status':
      args.count(0);
      return const StatusEngineRequest();
    case 'doctor':
      args.count(0);
      return const DoctorEngineRequest();
    case 'enroll':
      args.count(0);
      return const EnrollEngineRequest();
    case 'shutdown':
      args.count(0);
      return const ShutdownEngineRequest();
    case 'create':
      args.count(1);
      final time = args.requiredValue('first-time');
      final calendar = args.value('calendar') ?? 'gregorian';
      final UniverseStart start;
      if (calendar == 'gregorian') {
        if (args.value('tick-label') != null ||
            args.value('ticks-per-month') != null) {
          throw const _UsageError();
        }
        start = GregorianUniverseStart(time);
      } else {
        start = FictionalUniverseStart(
          calendarName: calendar,
          initialTick: time,
          tickLabel: args.requiredValue('tick-label'),
          ticksPerMonth: args.value('ticks-per-month') == null
              ? null
              : int.parse(args.value('ticks-per-month')!),
        );
      }
      return CreateUniverseEngineRequest(
        name: args.positional[0],
        start: start,
      );
    case 'register':
      args.count(2);
      return RegisterUniverseEngineRequest(
        path: args.positional[0],
        name: args.positional[1],
      );
    case 'rename':
      args.count(2);
      return RenameUniverseEngineRequest(
        universeId: UniverseId.parse(args.positional[0]),
        name: args.positional[1],
      );
    case 'grant':
      args.count(2);
      final worlds = args.options['world'];
      return GrantEngineRequest(
        grant: GrantSpec(
          profileId: ProfileId.parse(args.positional[0]),
          universeId: UniverseId.parse(args.positional[1]),
          worlds: worlds?.map(WorldId.parse),
          propose: args.has('propose'),
          edit: args.has('edit'),
          protected: args.has('protected'),
        ),
      );
    case 'revoke':
      args.count(1);
      return RevokeEngineRequest(
        profileId: ProfileId.parse(args.positional[0]),
      );
    case 'tool':
      args.count(1);
      return ToolEngineRequest(
        request: Request.fromWire(
          CanonicalValue.parseWireJson(
            decodeExactUtf8(
              await _readBounded(
                File(args.positional[0]).openRead(),
                maxFrameBytes,
              ),
            ),
          ),
        ),
      );
    case 'library':
      args.count(1);
      return LibraryEngineRequest(universe: universe());
    case 'review':
      args.count(4);
      return ReviewEngineRequest(
        universe: universe(),
        proposalReference: proposal(),
      );
    case 'approve':
      args.count(5);
      return ApproveEngineRequest(
        universe: universe(),
        proposalReference: proposal(),
        validationRun: ValidationRunId.parse(args.positional[4]),
      );
    case 'author-writing':
      args.count(1);
      final bytes = await (readInput ?? () => _readBounded(stdin, 1000000))();
      if (bytes.length > 1000000) {
        throw const FormatException('Author input limit');
      }
      return AuthorWritingEngineRequest(
        universe: universe(),
        action: AuthorWritingAction.fromWire(
          CanonicalValue.parseWireJson(decodeExactUtf8(bytes)),
        ),
      );
    case 'stage-source':
      args.count(3);
      return StageSourceEngineRequest(
        universe: universe(),
        label: args.positional[1],
        text: decodeExactUtf8(
          await _readBounded(
            File(args.positional[2]).openRead(),
            maxFrameBytes,
          ),
        ),
      );
    case 'backup':
      args.count(2);
      return BackupEngineRequest(
        universe: universe(),
        destination: args.positional[1],
      );
    case 'restore':
      args.count(2);
      return RestoreEngineRequest(
        source: args.positional[0],
        name: args.positional[1],
      );
    case 'maintain':
      args.count(1);
      return MaintainEngineRequest(
        universe: universe(),
        collect: args.has('collect'),
      );
    case 'convert-legacy':
      args.count(2);
      return ConvertLegacyEngineRequest(
        source: args.positional[0],
        destination: args.positional[1],
      );
    case 'export':
      args.count(2);
      return ExportLogicalEngineRequest(
        universe: universe(),
        destination: args.positional[1],
        recordIds: (args.options['record'] ?? []).map(RecordId.parse),
        completeHistory: args.has('complete-history'),
      );
    case 'preview-import':
      args.count(2);
      return PreviewImportEngineRequest(
        source: args.positional[0],
        name: args.positional[1],
        mode: args.has('clone') ? ImportMode.clone : ImportMode.restore,
      );
    case 'accept-import':
      args.count(2);
      return AcceptImportEngineRequest(
        previewId: OperationId.parse(args.positional[0]),
        digest: args.positional[1],
      );
    default:
      throw const _UsageError();
  }
}

Future<Uint8List> _readBounded(Stream<List<int>> input, int limit) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in input) {
    if (bytes.length + chunk.length > limit) {
      throw const FormatException('Input limit');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

final class _Arguments {
  _Arguments(
    List<String> tokens, {
    required Set<String> values,
    required Set<String> flags,
    required Set<String> repeated,
  }) {
    var literal = false;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (!literal && token == '--') {
        literal = true;
        continue;
      }
      if (!literal && token.startsWith('-')) {
        if (!token.startsWith('--')) throw const _UsageError();
        final equal = token.indexOf('=');
        final name = token.substring(2, equal < 0 ? token.length : equal);
        if (flags.contains(name)) {
          if (equal >= 0 || !switches.add(name)) throw const _UsageError();
        } else if (values.contains(name)) {
          final String value;
          if (equal >= 0) {
            value = token.substring(equal + 1);
          } else {
            if (++i == tokens.length || tokens[i].startsWith('--')) {
              throw const _UsageError();
            }
            value = tokens[i];
          }
          if (value.isEmpty ||
              value.contains('\u0000') ||
              options.containsKey(name) && !repeated.contains(name)) {
            throw const _UsageError();
          }
          options.putIfAbsent(name, () => []).add(value);
        } else {
          throw const _UsageError();
        }
      } else {
        if (token.isEmpty || token.contains('\u0000')) {
          throw const _UsageError();
        }
        positional.add(token);
      }
    }
  }
  final positional = <String>[];
  final options = <String, List<String>>{};
  final switches = <String>{};
  void count(int expected) {
    if (positional.length != expected) throw const _UsageError();
  }

  bool has(String flag) => switches.contains(flag);
  String? value(String name) => options[name]?.single;
  String requiredValue(String name) =>
      value(name) ?? (throw const _UsageError());
}

final class _UsageError implements Exception {
  const _UsageError();
}
