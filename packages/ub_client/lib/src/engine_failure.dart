enum LocalEngineFailure {
  unavailable,
  unsafeEndpoint,
  credentialUnavailable,
  handshakeFailed,
  interrupted,
  reconnectRequired,
  busy,
  closed,
  invalidRequest,
  helperUnavailable,
  startupTimeout,
}

/// Transport/parser exceptions may contain credentials or authored content.
final class LocalEngineException implements Exception {
  const LocalEngineException(this.failure);
  final LocalEngineFailure failure;
  @override
  String toString() => 'LocalEngineException(${failure.name})';
}
