import 'package:ub_client/loopback_engine.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

/// Fresh authentication per tool, as in the maintained adapter. Keep only the
/// profile ID; credentials are loaded through the protected client each time.
Future<CanonicalValue> callLocalMcpTool({
  required String root,
  required ProfileId profile,
  required Request request,
  required Future<void> cancelled,
}) async {
  LoopbackEngineClient? connection;
  var stopped = false;
  cancelled.then((_) async {
    stopped = true;
    await connection?.close();
  });
  try {
    connection = await LoopbackEngineClient.discover(
      root: root,
      profile: profile,
      clientName: 'mcp-adapter',
    );
    if (stopped) {
      throw const LocalEngineException(LocalEngineFailure.closed);
    }
    // No startup/reconnect or replay is performed after admission uncertainty.
    return await connection.call(ToolEngineRequest(request: request));
  } finally {
    await connection?.close();
    connection = null;
  }
}
