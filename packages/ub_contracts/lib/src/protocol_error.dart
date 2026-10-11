import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';

sealed class ProtocolError implements Exception {
  const ProtocolError();
  String get code;
  CanonicalObject toWire();
  @override
  bool operator ==(Object other) =>
      other is ProtocolError && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toWire().toText().hashCode;
  bool get isProtocolFailure =>
      this is InvalidArgumentError ||
      this is UniverseRequiredError ||
      this is DomainError;
  static ProtocolError fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'code',
      'field',
      'message',
      'expected',
      'actual',
    });
    return switch (f.string('code')) {
      'INVALID_ARGUMENT' => InvalidArgumentError.fromWire(value),
      'AMBIGUOUS_REFERENCE' => AmbiguousReferenceError.fromWire(value),
      'UNIVERSE_REQUIRED' => UniverseRequiredError.fromWire(value),
      'UNIVERSE_ID_MISMATCH' => UniverseIdMismatchError.fromWire(value),
      'UNIVERSE_SCOPE_MISMATCH' => UniverseScopeMismatchError.fromWire(value),
      'WORLD_NOT_FOUND_OR_NOT_ACCESSIBLE' =>
        WorldNotFoundOrNotAccessibleError.fromWire(value),
      'WORLD_SCOPE_CONFLICT' => WorldScopeConflictError.fromWire(value),
      'NAME_UNAVAILABLE' => NameUnavailableError.fromWire(value),
      'NOT_FOUND_OR_NOT_ACCESSIBLE' => NotFoundOrNotAccessibleError.fromWire(
        value,
      ),
      'CONTEXT_EXPIRED' => ContextExpiredError.fromWire(value),
      'BASE_REVISION_CONFLICT' => BaseRevisionConflictError.fromWire(value),
      'APPROVAL_REQUIRED' => ApprovalRequiredError.fromWire(value),
      'APPROVAL_STALE' => ApprovalStaleError.fromWire(value),
      'IDEMPOTENCY_KEY_REUSED' => IdempotencyKeyReusedError.fromWire(value),
      'UNSUPPORTED_SEMANTICS' => UnsupportedSemanticsError.fromWire(value),
      'EVALUATION_LIMIT_REACHED' => EvaluationLimitReachedError.fromWire(value),
      'POLICY_DENIED' => PolicyDeniedError.fromWire(value),
      'STORAGE_FAILURE' => StorageFailureError.fromWire(value),
      'MAINTENANCE_REQUIRED' => MaintenanceRequiredError.fromWire(value),
      'DOMAIN' => DomainError.fromWire(value),
      _ => throw const FormatException('Unknown protocol error'),
    };
  }
}

final class InvalidArgumentError extends ProtocolError {
  const InvalidArgumentError({required this.field, required this.message});
  final String field;
  final String message;
  factory InvalidArgumentError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'field', 'message'});
    if (f.string('code') != 'INVALID_ARGUMENT') {
      throw const FormatException('Wrong error code');
    }
    return InvalidArgumentError(
      field: f.string('field'),
      message: f.string('message'),
    );
  }
  @override
  String get code => 'INVALID_ARGUMENT';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('INVALID_ARGUMENT')),
    MapEntry('field', CanonicalString(field)),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class AmbiguousReferenceError extends ProtocolError {
  const AmbiguousReferenceError({required this.message});
  final String message;
  factory AmbiguousReferenceError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'AMBIGUOUS_REFERENCE') {
      throw const FormatException('Wrong error code');
    }
    return AmbiguousReferenceError(message: f.string('message'));
  }
  @override
  String get code => 'AMBIGUOUS_REFERENCE';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('AMBIGUOUS_REFERENCE')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class UniverseRequiredError extends ProtocolError {
  const UniverseRequiredError();
  factory UniverseRequiredError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code'});
    if (f.string('code') != 'UNIVERSE_REQUIRED') {
      throw const FormatException('Wrong error code');
    }
    return UniverseRequiredError();
  }
  @override
  String get code => 'UNIVERSE_REQUIRED';
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('code', CanonicalString('UNIVERSE_REQUIRED'))]);
}

final class UniverseIdMismatchError extends ProtocolError {
  const UniverseIdMismatchError({required this.expected, required this.actual});
  final String expected;
  final String actual;
  factory UniverseIdMismatchError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'expected', 'actual'});
    if (f.string('code') != 'UNIVERSE_ID_MISMATCH') {
      throw const FormatException('Wrong error code');
    }
    return UniverseIdMismatchError(
      expected: f.string('expected'),
      actual: f.string('actual'),
    );
  }
  @override
  String get code => 'UNIVERSE_ID_MISMATCH';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('UNIVERSE_ID_MISMATCH')),
    MapEntry('expected', CanonicalString(expected)),
    MapEntry('actual', CanonicalString(actual)),
  ]);
}

final class UniverseScopeMismatchError extends ProtocolError {
  const UniverseScopeMismatchError({required this.message});
  final String message;
  factory UniverseScopeMismatchError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'UNIVERSE_SCOPE_MISMATCH') {
      throw const FormatException('Wrong error code');
    }
    return UniverseScopeMismatchError(message: f.string('message'));
  }
  @override
  String get code => 'UNIVERSE_SCOPE_MISMATCH';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('UNIVERSE_SCOPE_MISMATCH')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class WorldNotFoundOrNotAccessibleError extends ProtocolError {
  const WorldNotFoundOrNotAccessibleError({required this.message});
  final String message;
  factory WorldNotFoundOrNotAccessibleError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'WORLD_NOT_FOUND_OR_NOT_ACCESSIBLE') {
      throw const FormatException('Wrong error code');
    }
    return WorldNotFoundOrNotAccessibleError(message: f.string('message'));
  }
  @override
  String get code => 'WORLD_NOT_FOUND_OR_NOT_ACCESSIBLE';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('WORLD_NOT_FOUND_OR_NOT_ACCESSIBLE')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class WorldScopeConflictError extends ProtocolError {
  const WorldScopeConflictError({required this.message});
  final String message;
  factory WorldScopeConflictError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'WORLD_SCOPE_CONFLICT') {
      throw const FormatException('Wrong error code');
    }
    return WorldScopeConflictError(message: f.string('message'));
  }
  @override
  String get code => 'WORLD_SCOPE_CONFLICT';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('WORLD_SCOPE_CONFLICT')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class NameUnavailableError extends ProtocolError {
  const NameUnavailableError({required this.message});
  final String message;
  factory NameUnavailableError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'NAME_UNAVAILABLE') {
      throw const FormatException('Wrong error code');
    }
    return NameUnavailableError(message: f.string('message'));
  }
  @override
  String get code => 'NAME_UNAVAILABLE';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('NAME_UNAVAILABLE')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class NotFoundOrNotAccessibleError extends ProtocolError {
  const NotFoundOrNotAccessibleError({required this.message});
  final String message;
  factory NotFoundOrNotAccessibleError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'NOT_FOUND_OR_NOT_ACCESSIBLE') {
      throw const FormatException('Wrong error code');
    }
    return NotFoundOrNotAccessibleError(message: f.string('message'));
  }
  @override
  String get code => 'NOT_FOUND_OR_NOT_ACCESSIBLE';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('NOT_FOUND_OR_NOT_ACCESSIBLE')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class ContextExpiredError extends ProtocolError {
  const ContextExpiredError();
  factory ContextExpiredError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code'});
    if (f.string('code') != 'CONTEXT_EXPIRED') {
      throw const FormatException('Wrong error code');
    }
    return ContextExpiredError();
  }
  @override
  String get code => 'CONTEXT_EXPIRED';
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('code', CanonicalString('CONTEXT_EXPIRED'))]);
}

final class BaseRevisionConflictError extends ProtocolError {
  const BaseRevisionConflictError({
    required this.expected,
    required this.actual,
  });
  final String expected;
  final String actual;
  factory BaseRevisionConflictError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'expected', 'actual'});
    if (f.string('code') != 'BASE_REVISION_CONFLICT') {
      throw const FormatException('Wrong error code');
    }
    return BaseRevisionConflictError(
      expected: f.string('expected'),
      actual: f.string('actual'),
    );
  }
  @override
  String get code => 'BASE_REVISION_CONFLICT';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('BASE_REVISION_CONFLICT')),
    MapEntry('expected', CanonicalString(expected)),
    MapEntry('actual', CanonicalString(actual)),
  ]);
}

final class ApprovalRequiredError extends ProtocolError {
  const ApprovalRequiredError({required this.message});
  final String message;
  factory ApprovalRequiredError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'APPROVAL_REQUIRED') {
      throw const FormatException('Wrong error code');
    }
    return ApprovalRequiredError(message: f.string('message'));
  }
  @override
  String get code => 'APPROVAL_REQUIRED';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('APPROVAL_REQUIRED')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class ApprovalStaleError extends ProtocolError {
  const ApprovalStaleError();
  factory ApprovalStaleError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code'});
    if (f.string('code') != 'APPROVAL_STALE') {
      throw const FormatException('Wrong error code');
    }
    return ApprovalStaleError();
  }
  @override
  String get code => 'APPROVAL_STALE';
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('code', CanonicalString('APPROVAL_STALE'))]);
}

final class IdempotencyKeyReusedError extends ProtocolError {
  const IdempotencyKeyReusedError({required this.message});
  final String message;
  factory IdempotencyKeyReusedError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'IDEMPOTENCY_KEY_REUSED') {
      throw const FormatException('Wrong error code');
    }
    return IdempotencyKeyReusedError(message: f.string('message'));
  }
  @override
  String get code => 'IDEMPOTENCY_KEY_REUSED';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('IDEMPOTENCY_KEY_REUSED')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class UnsupportedSemanticsError extends ProtocolError {
  const UnsupportedSemanticsError({required this.message});
  final String message;
  factory UnsupportedSemanticsError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'UNSUPPORTED_SEMANTICS') {
      throw const FormatException('Wrong error code');
    }
    return UnsupportedSemanticsError(message: f.string('message'));
  }
  @override
  String get code => 'UNSUPPORTED_SEMANTICS';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('UNSUPPORTED_SEMANTICS')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class EvaluationLimitReachedError extends ProtocolError {
  const EvaluationLimitReachedError({required this.message});
  final String message;
  factory EvaluationLimitReachedError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'EVALUATION_LIMIT_REACHED') {
      throw const FormatException('Wrong error code');
    }
    return EvaluationLimitReachedError(message: f.string('message'));
  }
  @override
  String get code => 'EVALUATION_LIMIT_REACHED';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('EVALUATION_LIMIT_REACHED')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class PolicyDeniedError extends ProtocolError {
  const PolicyDeniedError({required this.message});
  final String message;
  factory PolicyDeniedError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'POLICY_DENIED') {
      throw const FormatException('Wrong error code');
    }
    return PolicyDeniedError(message: f.string('message'));
  }
  @override
  String get code => 'POLICY_DENIED';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('POLICY_DENIED')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class StorageFailureError extends ProtocolError {
  const StorageFailureError({required this.message});
  final String message;
  factory StorageFailureError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'STORAGE_FAILURE') {
      throw const FormatException('Wrong error code');
    }
    return StorageFailureError(message: f.string('message'));
  }
  @override
  String get code => 'STORAGE_FAILURE';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('STORAGE_FAILURE')),
    MapEntry('message', CanonicalString(message)),
  ]);
}

final class MaintenanceRequiredError extends ProtocolError {
  const MaintenanceRequiredError();
  factory MaintenanceRequiredError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code'});
    if (f.string('code') != 'MAINTENANCE_REQUIRED') {
      throw const FormatException('Wrong error code');
    }
    return MaintenanceRequiredError();
  }
  @override
  String get code => 'MAINTENANCE_REQUIRED';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('MAINTENANCE_REQUIRED')),
  ]);
}

final class DomainError extends ProtocolError {
  const DomainError({required this.message});
  final String message;
  factory DomainError.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'code', 'message'});
    if (f.string('code') != 'DOMAIN') {
      throw const FormatException('Wrong error code');
    }
    return DomainError(message: f.string('message'));
  }
  @override
  String get code => 'DOMAIN_ERROR';
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('code', CanonicalString('DOMAIN')),
    MapEntry('message', CanonicalString(message)),
  ]);
}
