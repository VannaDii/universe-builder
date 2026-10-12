import 'package:ub_domain/ub_domain.dart';

import 'request.dart';
import 'workflow.dart';
import 'wire.dart';

/// Private author decisions. These DTOs are not public model requests and do
/// not grant author rights, accept findings or publish a proposal when decoded.
sealed class AuthorWritingAction {
  const AuthorWritingAction();
  String get action;
  CanonicalObject toWire();
  static AuthorWritingAction fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'action',
      'candidate',
      'context_id',
      'correction',
      'declaration',
      'fingerprint',
      'idempotency_key',
      'label',
      'rationale',
      'scope',
      'text',
      'validation_run',
    });
    return switch (f.string('action')) {
      'inspect' => InspectWritingAction.fromWire(value),
      'prepare' => PrepareWritingAction.fromWire(value),
      'prepare_contracts' => PrepareContractsWritingAction.fromWire(value),
      'edit_knowledge' => EditKnowledgeWritingAction.fromWire(value),
      'establish_knowledge' => EstablishKnowledgeWritingAction.fromWire(value),
      'reject' => RejectWritingAction.fromWire(value),
      'publish' => PublishWritingAction.fromWire(value),
      'accept' => AcceptWritingAction.fromWire(value),
      _ => throw const FormatException('Unknown private author action'),
    };
  }
}

final class InspectWritingAction extends AuthorWritingAction {
  const InspectWritingAction({required this.candidate});
  final ProposalRef candidate;
  @override
  String get action => 'inspect';
  factory InspectWritingAction.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'action', 'candidate'});
    if (f.string('action') != 'inspect') {
      throw const FormatException('Wrong author action');
    }
    return InspectWritingAction(
      candidate: ProposalRef.fromWire(f.require('candidate')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('action', CanonicalString('inspect')),
    MapEntry('candidate', candidate.toWire()),
  ]);
}

final class PrepareWritingAction extends AuthorWritingAction {
  const PrepareWritingAction({
    required this.candidate,
    required this.label,
    required this.text,
  });
  final ProposalId candidate;
  final String label;
  final String text;
  @override
  String get action => 'prepare';
  factory PrepareWritingAction.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'action', 'candidate', 'label', 'text'});
    if (f.string('action') != 'prepare') {
      throw const FormatException('Wrong author action');
    }
    return PrepareWritingAction(
      candidate: ProposalId.parse(f.string('candidate')),
      label: f.string('label'),
      text: f.string('text'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('action', CanonicalString('prepare')),
    MapEntry('candidate', CanonicalString(candidate.value)),
    MapEntry('label', CanonicalString(label)),
    MapEntry('text', CanonicalString(text)),
  ]);
}

final class PrepareContractsWritingAction extends AuthorWritingAction {
  const PrepareContractsWritingAction({
    required this.candidate,
    required this.label,
    required this.text,
  });
  final ProposalId candidate;
  final String label;
  final String text;
  @override
  String get action => 'prepare_contracts';
  factory PrepareContractsWritingAction.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'action', 'candidate', 'label', 'text'});
    if (f.string('action') != 'prepare_contracts') {
      throw const FormatException('Wrong author action');
    }
    return PrepareContractsWritingAction(
      candidate: ProposalId.parse(f.string('candidate')),
      label: f.string('label'),
      text: f.string('text'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('action', CanonicalString('prepare_contracts')),
    MapEntry('candidate', CanonicalString(candidate.value)),
    MapEntry('label', CanonicalString(label)),
    MapEntry('text', CanonicalString(text)),
  ]);
}

final class EditKnowledgeWritingAction extends AuthorWritingAction {
  const EditKnowledgeWritingAction({
    required this.contextId,
    required this.correction,
    required this.label,
    required this.text,
  });
  final ContextId contextId;
  final WritingAttitudeCorrection correction;
  final String label;
  final String text;
  @override
  String get action => 'edit_knowledge';
  factory EditKnowledgeWritingAction.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'action',
      'context_id',
      'correction',
      'label',
      'text',
    });
    if (f.string('action') != 'edit_knowledge') {
      throw const FormatException('Wrong author action');
    }
    return EditKnowledgeWritingAction(
      contextId: ContextId.parse(f.string('context_id')),
      correction: WritingAttitudeCorrection.fromWire(f.require('correction')),
      label: f.string('label'),
      text: f.string('text'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('action', CanonicalString('edit_knowledge')),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('correction', correction.toWire()),
    MapEntry('label', CanonicalString(label)),
    MapEntry('text', CanonicalString(text)),
  ]);
}

final class EstablishKnowledgeWritingAction extends AuthorWritingAction {
  const EstablishKnowledgeWritingAction({
    required this.contextId,
    required this.declaration,
    required this.rationale,
    required this.label,
    required this.text,
  });
  final ContextId contextId;
  final AuthorKnowledgeDeclaration declaration;
  final String rationale;
  final String label;
  final String text;
  @override
  String get action => 'establish_knowledge';
  factory EstablishKnowledgeWritingAction.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'action',
      'context_id',
      'declaration',
      'rationale',
      'label',
      'text',
    });
    if (f.string('action') != 'establish_knowledge') {
      throw const FormatException('Wrong author action');
    }
    return EstablishKnowledgeWritingAction(
      contextId: ContextId.parse(f.string('context_id')),
      declaration: AuthorKnowledgeDeclaration.fromWire(
        f.require('declaration'),
      ),
      rationale: f.string('rationale'),
      label: f.string('label'),
      text: f.string('text'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('action', CanonicalString('establish_knowledge')),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('declaration', declaration.toWire()),
    MapEntry('rationale', CanonicalString(rationale)),
    MapEntry('label', CanonicalString(label)),
    MapEntry('text', CanonicalString(text)),
  ]);
}

final class RejectWritingAction extends AuthorWritingAction {
  const RejectWritingAction({required this.candidate});
  final ProposalId candidate;
  @override
  String get action => 'reject';
  factory RejectWritingAction.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'action', 'candidate'});
    if (f.string('action') != 'reject') {
      throw const FormatException('Wrong author action');
    }
    return RejectWritingAction(
      candidate: ProposalId.parse(f.string('candidate')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('action', CanonicalString('reject')),
    MapEntry('candidate', CanonicalString(candidate.value)),
  ]);
}

final class PublishWritingAction extends AuthorWritingAction {
  const PublishWritingAction({
    required this.candidate,
    required this.validationRun,
    required this.idempotencyKey,
  });
  final ProposalRef candidate;
  final ValidationRunId validationRun;
  final String idempotencyKey;
  @override
  String get action => 'publish';
  factory PublishWritingAction.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'action',
      'candidate',
      'validation_run',
      'idempotency_key',
    });
    if (f.string('action') != 'publish') {
      throw const FormatException('Wrong author action');
    }
    return PublishWritingAction(
      candidate: ProposalRef.fromWire(f.require('candidate')),
      validationRun: ValidationRunId.parse(f.string('validation_run')),
      idempotencyKey: f.string('idempotency_key'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('action', CanonicalString('publish')),
    MapEntry('candidate', candidate.toWire()),
    MapEntry('validation_run', CanonicalString(validationRun.value)),
    MapEntry('idempotency_key', CanonicalString(idempotencyKey)),
  ]);
}

final class AcceptWritingAction extends AuthorWritingAction {
  const AcceptWritingAction({
    required this.candidate,
    required this.fingerprint,
    required this.scope,
    required this.rationale,
  });
  final ProposalRef candidate;
  final FindingFingerprint fingerprint;
  final String scope;
  final String rationale;
  @override
  String get action => 'accept';
  factory AcceptWritingAction.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'action',
      'candidate',
      'fingerprint',
      'scope',
      'rationale',
    });
    if (f.string('action') != 'accept') {
      throw const FormatException('Wrong author action');
    }
    return AcceptWritingAction(
      candidate: ProposalRef.fromWire(f.require('candidate')),
      fingerprint: FindingFingerprint(f.string('fingerprint')),
      scope: f.string('scope'),
      rationale: f.string('rationale'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('action', CanonicalString('accept')),
    MapEntry('candidate', candidate.toWire()),
    MapEntry('fingerprint', CanonicalString(fingerprint.value)),
    MapEntry('scope', CanonicalString(scope)),
    MapEntry('rationale', CanonicalString(rationale)),
  ]);
}
