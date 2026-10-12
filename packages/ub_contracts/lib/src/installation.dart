import 'dart:typed_data';

import 'package:ub_domain/ub_domain.dart';

import 'workflow.dart';
import 'wire.dart';

/// A transport credential. Normal diagnostic formatting always redacts it.
/// Explicit exposure/serialization is only for the authenticated private path.
final class Credential {
  const Credential(String value) : _value = value;
  final String _value;
  String expose() => _value;
  @override
  String toString() => '[redacted]';
  factory Credential.fromWire(CanonicalValue value) =>
      Credential(wireString(value));
  CanonicalString toWire() => CanonicalString(_value);
}

enum ImportMode {
  restore,
  clone;

  static ImportMode fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown import mode'),
  );
}

// Private installation DTOs are not public tools or authority grants.
const engineMaxInFlight = 8;

final class EngineHello {
  factory EngineHello.decode(Uint8List bytes) =>
      EngineHello.fromWire(decodeWireFrame(bytes));
  EngineHello({
    required this.protocolVersion,
    required this.profileId,
    required this.credential,
    required this.clientName,
  });
  final String protocolVersion;
  final ProfileId profileId;
  final Credential credential;
  final String clientName;
  factory EngineHello.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'protocol_version',
      'profile_id',
      'credential',
      'client_name',
    });
    return EngineHello(
      protocolVersion: wireString(f.require('protocol_version')),
      profileId: ProfileId.parse(wireString(f.require('profile_id'))),
      credential: Credential.fromWire(f.require('credential')),
      clientName: wireString(f.require('client_name')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('protocol_version', CanonicalString(protocolVersion)),
    MapEntry('profile_id', CanonicalString(profileId.value)),
    MapEntry('credential', credential.toWire()),
    MapEntry('client_name', CanonicalString(clientName)),
  ]);
}

final class EngineWelcome {
  factory EngineWelcome.decode(Uint8List bytes) =>
      EngineWelcome.fromWire(decodeWireFrame(bytes));
  EngineWelcome({
    required this.protocolVersion,
    required this.serviceInstance,
    required this.principal,
    required this.author,
    required BigInt maxFrameBytes,
    required BigInt maxInFlight,
  }) : maxFrameBytes = checkedU64(maxFrameBytes),
       maxInFlight = checkedU64(maxInFlight);
  final String protocolVersion;
  final String serviceInstance;
  final ProfileId principal;
  final bool author;
  final BigInt maxFrameBytes;
  final BigInt maxInFlight;
  factory EngineWelcome.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'protocol_version',
      'service_instance',
      'principal',
      'author',
      'max_frame_bytes',
      'max_in_flight',
    });
    return EngineWelcome(
      protocolVersion: wireString(f.require('protocol_version')),
      serviceInstance: wireString(f.require('service_instance')),
      principal: ProfileId.parse(wireString(f.require('principal'))),
      author: _installationBool(f.require('author')),
      maxFrameBytes: _installationU64(f.require('max_frame_bytes')),
      maxInFlight: _installationU64(f.require('max_in_flight')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('protocol_version', CanonicalString(protocolVersion)),
    MapEntry('service_instance', CanonicalString(serviceInstance)),
    MapEntry('principal', CanonicalString(principal.value)),
    MapEntry('author', CanonicalBool(author)),
    MapEntry('max_frame_bytes', CanonicalNumber(maxFrameBytes.toString())),
    MapEntry('max_in_flight', CanonicalNumber(maxInFlight.toString())),
  ]);
}

final class GrantLimits {
  GrantLimits({
    Iterable<RecordId>? entities,
    Iterable<RecordId>? predicates,
    Iterable<ContinuityId>? continuities,
    BigInt? expiresAt,
    this.delegatedCommit = false,
    this.allowShared = false,
  }) : entities = entities == null ? null : List.unmodifiable(entities),
       predicates = predicates == null ? null : List.unmodifiable(predicates),
       continuities = continuities == null
           ? null
           : List.unmodifiable(continuities),
       expiresAt = expiresAt == null ? null : checkedU64(expiresAt);
  final List<RecordId>? entities;
  final List<RecordId>? predicates;
  final List<ContinuityId>? continuities;
  final BigInt? expiresAt;
  final bool delegatedCommit;
  final bool allowShared;
  factory GrantLimits.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'entities',
      'predicates',
      'continuities',
      'expires_at',
      'delegated_commit',
      'allow_shared',
    });
    return GrantLimits(
      entities: f.optional(
        'entities',
        (v) => _installationArray(v).map((v) => RecordId.parse(wireString(v))),
      ),
      predicates: f.optional(
        'predicates',
        (v) => _installationArray(v).map((v) => RecordId.parse(wireString(v))),
      ),
      continuities: f.optional(
        'continuities',
        (v) =>
            _installationArray(v).map((v) => ContinuityId.parse(wireString(v))),
      ),
      expiresAt: f.optional('expires_at', (v) => _installationU64(v)),
      delegatedCommit: f.values.containsKey('delegated_commit')
          ? f.boolean('delegated_commit')
          : false,
      allowShared: f.values.containsKey('allow_shared')
          ? f.boolean('allow_shared')
          : false,
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry(
      'entities',
      entities == null
          ? const CanonicalNull()
          : CanonicalArray(entities!.map((v) => CanonicalString(v.value))),
    ),
    MapEntry(
      'predicates',
      predicates == null
          ? const CanonicalNull()
          : CanonicalArray(predicates!.map((v) => CanonicalString(v.value))),
    ),
    MapEntry(
      'continuities',
      continuities == null
          ? const CanonicalNull()
          : CanonicalArray(continuities!.map((v) => CanonicalString(v.value))),
    ),
    MapEntry(
      'expires_at',
      expiresAt == null
          ? const CanonicalNull()
          : CanonicalNumber(expiresAt!.toString()),
    ),
    MapEntry('delegated_commit', CanonicalBool(delegatedCommit)),
    MapEntry('allow_shared', CanonicalBool(allowShared)),
  ]);
}

final class GrantSpec {
  GrantSpec({
    required this.profileId,
    required this.universeId,
    Iterable<WorldId>? worlds,
    required this.propose,
    required this.edit,
    required this.protected,
    GrantLimits? limits,
  }) : worlds = worlds == null ? null : List.unmodifiable(worlds),
       limits = limits ?? GrantLimits();
  final ProfileId profileId;
  final UniverseId universeId;
  final List<WorldId>? worlds;
  final bool propose;
  final bool edit;
  final bool protected;
  final GrantLimits limits;
  factory GrantSpec.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'profile_id',
      'universe_id',
      'worlds',
      'propose',
      'edit',
      'protected',
      'limits',
    });
    return GrantSpec(
      profileId: ProfileId.parse(wireString(f.require('profile_id'))),
      universeId: UniverseId.parse(wireString(f.require('universe_id'))),
      worlds: f.optional(
        'worlds',
        (v) => _installationArray(v).map((v) => WorldId.parse(wireString(v))),
      ),
      propose: _installationBool(f.require('propose')),
      edit: _installationBool(f.require('edit')),
      protected: _installationBool(f.require('protected')),
      limits: f.values.containsKey('limits')
          ? GrantLimits.fromWire(f.require('limits'))
          : GrantLimits(),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('profile_id', CanonicalString(profileId.value)),
    MapEntry('universe_id', CanonicalString(universeId.value)),
    MapEntry(
      'worlds',
      worlds == null
          ? const CanonicalNull()
          : CanonicalArray(worlds!.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('propose', CanonicalBool(propose)),
    MapEntry('edit', CanonicalBool(edit)),
    MapEntry('protected', CanonicalBool(protected)),
    MapEntry('limits', limits.toWire()),
  ]);
}

final class DraftContent {
  DraftContent({
    required this.baseRevision,
    required this.representedContext,
    required Iterable<DomainOperation> operations,
    required this.rationale,
    this.proposal,
  }) : operations = List.unmodifiable(operations);
  final RevisionId baseRevision;
  final RecordId representedContext;
  final List<DomainOperation> operations;
  final String rationale;
  final ProposalRef? proposal;
  factory DraftContent.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'base_revision',
      'represented_context',
      'operations',
      'rationale',
      'proposal',
    });
    return DraftContent(
      baseRevision: RevisionId.parse(wireString(f.require('base_revision'))),
      representedContext: RecordId.parse(
        wireString(f.require('represented_context')),
      ),
      operations: f.array('operations').map((v) => DomainOperation.fromWire(v)),
      rationale: wireString(f.require('rationale')),
      proposal: f.optional('proposal', (v) => ProposalRef.fromWire(v)),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('base_revision', CanonicalString(baseRevision.value)),
    MapEntry('represented_context', CanonicalString(representedContext.value)),
    MapEntry('operations', CanonicalArray(operations.map((v) => v.toWire()))),
    MapEntry('rationale', CanonicalString(rationale)),
    if (proposal != null) MapEntry('proposal', proposal!.toWire()),
  ]);
}

final class SavedDraft {
  SavedDraft({required BigInt version, required this.content})
    : version = checkedU64(version);
  final BigInt version;
  final DraftContent content;
  factory SavedDraft.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'version', 'content'});
    return SavedDraft(
      version: _installationU64(f.require('version')),
      content: DraftContent.fromWire(f.require('content')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('version', CanonicalNumber(version.toString())),
    MapEntry('content', content.toWire()),
  ]);
}

bool _installationBool(CanonicalValue value) => switch (value) {
  CanonicalBool(:final value) => value,
  _ => throw const FormatException('Expected installation boolean'),
};
List<CanonicalValue> _installationArray(CanonicalValue value) =>
    switch (value) {
      CanonicalArray(:final items) => items,
      _ => throw const FormatException('Expected installation array'),
    };
BigInt _installationU64(CanonicalValue value) => WireFields(
  CanonicalObject([MapEntry('value', value)]),
  {'value'},
).u64('value');
