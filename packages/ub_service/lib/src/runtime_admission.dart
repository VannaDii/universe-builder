import 'dart:async';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'installation_authority.dart';

/// Engine-local resource admission for authenticated native connections.
/// This does not authorize a request: execution must recheck current authority.
final class NativeRuntimeAdmission {
  final _principals = <ProfileId, _PrincipalSlots>{};
  int _connections = 0, _agentConnections = 0;
  int _authorWork = 0, _agentWork = 0;

  NativeConnectionLease connect(InstallationPrincipal principal) {
    const busy = EvaluationLimitReachedError(
      message: 'principal connection limit',
    );
    if (_connections >= 32 || !principal.author && _agentConnections >= 24) {
      throw busy;
    }
    if (!_principals.containsKey(principal.id) && _principals.length >= 1024) {
      throw busy;
    }
    final slots = _principals.putIfAbsent(principal.id, _PrincipalSlots.new);
    if (slots.connections >= 8) throw busy;
    slots.connections++;
    _connections++;
    if (!principal.author) _agentConnections++;
    return NativeConnectionLease._(this, principal, slots);
  }

  Future<T> _run<T>(
    NativeConnectionLease lease,
    FutureOr<T> Function() action,
  ) async {
    if (lease._closed) throw StateError('Connection is closed');
    final author = lease._principal.author;
    final slots = lease._slots;
    if (slots.requests >= engineMaxInFlight ||
        (author ? _authorWork >= 4 : _agentWork >= 8)) {
      throw const EvaluationLimitReachedError(
        message: 'principal request limit',
      );
    }
    slots.requests++;
    if (author) {
      _authorWork++;
    } else {
      _agentWork++;
    }
    try {
      return await action();
    } finally {
      slots.requests--;
      if (author) {
        _authorWork--;
      } else {
        _agentWork--;
      }
    }
  }

  void _disconnect(NativeConnectionLease lease) {
    lease._slots.connections--;
    _connections--;
    if (!lease._principal.author) _agentConnections--;
  }
}

/// Held by the native transport for one authenticated connection.
final class NativeConnectionLease {
  NativeConnectionLease._(this._owner, this._principal, this._slots);
  final NativeRuntimeAdmission _owner;
  final InstallationPrincipal _principal;
  final _PrincipalSlots _slots;
  bool _closed = false;
  Future<T> run<T>(FutureOr<T> Function() action) => _owner._run(this, action);
  void close() {
    if (_closed) return;
    _closed = true;
    _owner._disconnect(this);
  }
}

final class _PrincipalSlots {
  int connections = 0, requests = 0;
}
