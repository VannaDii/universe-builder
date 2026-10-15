import 'dart:async';
import 'dart:io';

import 'package:ub_client/fixture_engine.dart';
import 'package:ub_client/local_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_store/installation.dart';

import 'fixture_workspace.dart';

final class FixtureDevice {
  FixtureDevice(this.arguments, {this.engineHelper, this.temporaryDirectory});
  final List<String> arguments;
  final Future<String> Function()? engineHelper;
  final Directory? temporaryDirectory;
  Future<FixtureTransport> start() async {
    if (arguments.length != 1 || arguments.single != '--fixture') {
      throw const FormatException(
        'Fixture mode accepts --fixture only; choose a persistent connection separately.',
      );
    }
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw UnsupportedError(
        'The disposable fixture requires a macOS or Linux desktop.',
      );
    }
    final helper = await (engineHelper ?? LocalEngineClient.siblingEngine)();
    final root = privateTemporaryDirectory(
      (temporaryDirectory ?? Directory.systemTemp).path,
      'f',
    );
    privateDirectory(root.path);
    Process? child;
    _NativeFixture? transport;
    try {
      child = await Process.start(helper, [
        '--fixture',
        '--socket',
        '${root.path}/s',
        '--exit-on-stdin-close',
      ]);
      child.stdout.drain<void>().ignore();
      child.stderr.drain<void>().ignore();
      transport = _NativeFixture(root, child);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline) && !transport.ended) {
        try {
          final ready = await FixtureEngineClient.connect('${root.path}/s');
          await ready.close();
          return transport;
        } on FileSystemException {
          /* wait for socket publication */
        } on SocketException {
          /* wait for the child to bind */
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      throw StateError('The bundled disposable engine did not start.');
    } on Object {
      if (transport != null) {
        await transport.close();
      } else {
        child?.kill();
        if (child != null) await child.exitCode;
        root.deleteSync();
      }
      rethrow;
    }
  }
}

final class _NativeFixture implements FixtureTransport {
  _NativeFixture(this.root, this.child) {
    child.exitCode.then((_) {
      ended = true;
    });
  }
  final Directory root;
  final Process child;
  final _clients = <FixtureEngineClient>{};
  bool ended = false, _closed = false;
  Future<void>? _closing;
  @override
  Future<Response> call(Request request) async {
    if (_closed || ended) {
      throw StateError(
        'The disposable engine has ended. Reopen fixture mode for a new session.',
      );
    }
    final client = await FixtureEngineClient.connect('${root.path}/s');
    _clients.add(client);
    try {
      if (_closed) throw StateError('Fixture closed.');
      return await client.call(request);
    } finally {
      _clients.remove(client);
      await client.close();
    }
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    for (final client in _clients.toList()) {
      await client.close();
    }
    try {
      await child.stdin.close();
      await child.exitCode.timeout(const Duration(seconds: 5));
    } on Object {
      child.kill(ProcessSignal.sigterm);
      try {
        await child.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
      }
    } finally {
      // Only the private directory allocated by this connection is eligible.
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  }
}
