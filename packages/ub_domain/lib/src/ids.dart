import 'dart:math';

/// Prefixes detect reference mistakes; they do not confer authority or universe
/// membership. Equality includes the typed family as well as the opaque body.
sealed class TypedId {
  TypedId(this.value, String prefix) {
    if (value.length != prefix.length + 24 ||
        !RegExp('^$prefix[0-9a-f]{24}\$').hasMatch(value)) {
      throw FormatException('Invalid $prefix identifier', value);
    }
  }
  final String value;
  @override
  String toString() => value;
  @override
  bool operator ==(Object other) =>
      other is TypedId &&
      runtimeType == other.runtimeType &&
      value == other.value;
  @override
  int get hashCode => Object.hash(runtimeType, value);
}

String _generate(String prefix) {
  final random = Random.secure();
  final body = List.generate(
    12,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return '$prefix$body';
}

final class UniverseId extends TypedId {
  UniverseId.parse(String value) : super(value, 'unv_');
  factory UniverseId.generate() => UniverseId.parse(_generate('unv_'));
  static const prefix = 'unv_';
}

final class WorldId extends TypedId {
  WorldId.parse(String value) : super(value, 'wld_');
  factory WorldId.generate() => WorldId.parse(_generate('wld_'));
  static const prefix = 'wld_';
}

final class WorkId extends TypedId {
  WorkId.parse(String value) : super(value, 'wrk_');
  factory WorkId.generate() => WorkId.parse(_generate('wrk_'));
  static const prefix = 'wrk_';
}

final class SagaId extends TypedId {
  SagaId.parse(String value) : super(value, 'sag_');
  factory SagaId.generate() => SagaId.parse(_generate('sag_'));
  static const prefix = 'sag_';
}

final class ContinuityId extends TypedId {
  ContinuityId.parse(String value) : super(value, 'cont_');
  factory ContinuityId.generate() => ContinuityId.parse(_generate('cont_'));
  static const prefix = 'cont_';
}

final class RevisionId extends TypedId {
  RevisionId.parse(String value) : super(value, 'rev_');
  factory RevisionId.generate() => RevisionId.parse(_generate('rev_'));
  static const prefix = 'rev_';
}

final class RecordId extends TypedId {
  RecordId.parse(String value) : super(value, 'rec_');
  factory RecordId.generate() => RecordId.parse(_generate('rec_'));
  static const prefix = 'rec_';
}

final class RecordVersionId extends TypedId {
  RecordVersionId.parse(String value) : super(value, 'ver_');
  factory RecordVersionId.generate() =>
      RecordVersionId.parse(_generate('ver_'));
  static const prefix = 'ver_';
}

final class ProposalId extends TypedId {
  ProposalId.parse(String value) : super(value, 'prp_');
  factory ProposalId.generate() => ProposalId.parse(_generate('prp_'));
  static const prefix = 'prp_';
}

final class ProposalVersionId extends TypedId {
  ProposalVersionId.parse(String value) : super(value, 'prv_');
  factory ProposalVersionId.generate() =>
      ProposalVersionId.parse(_generate('prv_'));
  static const prefix = 'prv_';
}

final class OperationId extends TypedId {
  OperationId.parse(String value) : super(value, 'op_');
  factory OperationId.generate() => OperationId.parse(_generate('op_'));
  static const prefix = 'op_';
}

final class PrincipalId extends TypedId {
  PrincipalId.parse(String value) : super(value, 'prn_');
  factory PrincipalId.generate() => PrincipalId.parse(_generate('prn_'));
  static const prefix = 'prn_';
}

final class ContextId extends TypedId {
  ContextId.parse(String value) : super(value, 'ctx_');
  factory ContextId.generate() => ContextId.parse(_generate('ctx_'));
  static const prefix = 'ctx_';
}

final class ValidationRunId extends TypedId {
  ValidationRunId.parse(String value) : super(value, 'val_');
  factory ValidationRunId.generate() =>
      ValidationRunId.parse(_generate('val_'));
  static const prefix = 'val_';
}

final class FindingId extends TypedId {
  FindingId.parse(String value) : super(value, 'fnd_');
  factory FindingId.generate() => FindingId.parse(_generate('fnd_'));
  static const prefix = 'fnd_';
}

final class ApprovalId extends TypedId {
  ApprovalId.parse(String value) : super(value, 'appr_');
  factory ApprovalId.generate() => ApprovalId.parse(_generate('appr_'));
  static const prefix = 'appr_';
}

final class ProfileId extends TypedId {
  ProfileId.parse(String value) : super(value, 'prf_');
  factory ProfileId.generate() => ProfileId.parse(_generate('prf_'));
  static const prefix = 'prf_';
}

final class GrantId extends TypedId {
  GrantId.parse(String value) : super(value, 'grn_');
  factory GrantId.generate() => GrantId.parse(_generate('grn_'));
  static const prefix = 'grn_';
}

final class CalendarId extends TypedId {
  CalendarId.parse(String value) : super(value, 'cal_');
  factory CalendarId.generate() => CalendarId.parse(_generate('cal_'));
  static const prefix = 'cal_';
  factory CalendarId.fromRecordId(RecordId record) => CalendarId.parse(
    '$prefix${record.value.substring(RecordId.prefix.length)}',
  );
  RecordId toRecordId() =>
      RecordId.parse('${RecordId.prefix}${value.substring(prefix.length)}');
}

final class PropositionId extends TypedId {
  PropositionId.parse(String value) : super(value, 'prop_');
  factory PropositionId.generate() => PropositionId.parse(_generate('prop_'));
  static const prefix = 'prop_';
  factory PropositionId.fromRecordId(RecordId record) => PropositionId.parse(
    '$prefix${record.value.substring(RecordId.prefix.length)}',
  );
  RecordId toRecordId() =>
      RecordId.parse('${RecordId.prefix}${value.substring(prefix.length)}');
}

final class RuleId extends TypedId {
  RuleId.parse(String value) : super(value, 'rule_');
  factory RuleId.generate() => RuleId.parse(_generate('rule_'));
  static const prefix = 'rule_';
  factory RuleId.fromRecordId(RecordId record) =>
      RuleId.parse('$prefix${record.value.substring(RecordId.prefix.length)}');
  RecordId toRecordId() =>
      RecordId.parse('${RecordId.prefix}${value.substring(prefix.length)}');
}

final class ExceptionId extends TypedId {
  ExceptionId.parse(String value) : super(value, 'exc_');
  factory ExceptionId.generate() => ExceptionId.parse(_generate('exc_'));
  static const prefix = 'exc_';
  factory ExceptionId.fromRecordId(RecordId record) => ExceptionId.parse(
    '$prefix${record.value.substring(RecordId.prefix.length)}',
  );
  RecordId toRecordId() =>
      RecordId.parse('${RecordId.prefix}${value.substring(prefix.length)}');
}

final class AnchorId extends TypedId {
  AnchorId.parse(String value) : super(value, 'anch_');
  factory AnchorId.generate() => AnchorId.parse(_generate('anch_'));
  static const prefix = 'anch_';
  factory AnchorId.fromRecordId(RecordId record) => AnchorId.parse(
    '$prefix${record.value.substring(RecordId.prefix.length)}',
  );
  RecordId toRecordId() =>
      RecordId.parse('${RecordId.prefix}${value.substring(prefix.length)}');
}

final class UnitId extends TypedId {
  UnitId.parse(String value) : super(value, 'unit_');
  factory UnitId.generate() => UnitId.parse(_generate('unit_'));
  static const prefix = 'unit_';
  factory UnitId.fromRecordId(RecordId record) =>
      UnitId.parse('$prefix${record.value.substring(RecordId.prefix.length)}');
  RecordId toRecordId() =>
      RecordId.parse('${RecordId.prefix}${value.substring(prefix.length)}');
}

final class ValueDefinitionId extends TypedId {
  ValueDefinitionId.parse(String value) : super(value, 'vdef_');
  factory ValueDefinitionId.generate() =>
      ValueDefinitionId.parse(_generate('vdef_'));
  static const prefix = 'vdef_';
  factory ValueDefinitionId.fromRecordId(RecordId record) =>
      ValueDefinitionId.parse(
        '$prefix${record.value.substring(RecordId.prefix.length)}',
      );
  RecordId toRecordId() =>
      RecordId.parse('${RecordId.prefix}${value.substring(prefix.length)}');
}
