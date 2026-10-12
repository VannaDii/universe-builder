import 'dart:typed_data';

import 'package:ub_domain/ub_domain.dart';

import 'author_writing_action.dart';
import 'installation.dart';
import 'protocol_error.dart';
import 'request.dart';
import 'workflow.dart';
import 'wire.dart';

/// Private installation commands. Decoding does not execute file operations,
/// authorize publication or make these commands available as model tools.
sealed class EngineRequest {
  const EngineRequest();
  String get method;
  CanonicalObject toWire();
  static EngineRequest decode(Uint8List bytes) =>
      fromWire(decodeWireFrame(bytes));
  static EngineRequest fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'action',
      'asset',
      'collect',
      'complete_history',
      'confirmation',
      'content',
      'context_id',
      'continuity_id',
      'destination',
      'digest',
      'expected_version',
      'grant',
      'label',
      'method',
      'mode',
      'name',
      'path',
      'preview_id',
      'profile_id',
      'proposal_reference',
      'record_ids',
      'request',
      'revision',
      'source',
      'source_revision',
      'start',
      'target',
      'target_revision',
      'text',
      'universe',
      'universe_id',
      'validation_run',
    });
    return switch (f.string('method')) {
      'status' => StatusEngineRequest.fromWire(value),
      'doctor' => DoctorEngineRequest.fromWire(value),
      'profiles' => ProfilesEngineRequest.fromWire(value),
      'withdraw_grant' => WithdrawGrantEngineRequest.fromWire(value),
      'preview_purge' => PreviewPurgeEngineRequest.fromWire(value),
      'purge' => PurgeEngineRequest.fromWire(value),
      'tool' => ToolEngineRequest.fromWire(value),
      'library' => LibraryEngineRequest.fromWire(value),
      'fork_continuity' => ForkContinuityEngineRequest.fromWire(value),
      'compare_continuities' => CompareContinuitiesEngineRequest.fromWire(
        value,
      ),
      'prepare_adoption' => PrepareAdoptionEngineRequest.fromWire(value),
      'load_draft' => LoadDraftEngineRequest.fromWire(value),
      'save_draft' => SaveDraftEngineRequest.fromWire(value),
      'stage_image' => StageImageEngineRequest.fromWire(value),
      'image_preview' => ImagePreviewEngineRequest.fromWire(value),
      'author_writing' => AuthorWritingEngineRequest.fromWire(value),
      'stage_source' => StageSourceEngineRequest.fromWire(value),
      'backup' => BackupEngineRequest.fromWire(value),
      'restore' => RestoreEngineRequest.fromWire(value),
      'maintain' => MaintainEngineRequest.fromWire(value),
      'convert_legacy' => ConvertLegacyEngineRequest.fromWire(value),
      'export_logical' => ExportLogicalEngineRequest.fromWire(value),
      'preview_import' => PreviewImportEngineRequest.fromWire(value),
      'accept_import' => AcceptImportEngineRequest.fromWire(value),
      'review' => ReviewEngineRequest.fromWire(value),
      'approve' => ApproveEngineRequest.fromWire(value),
      'create_universe' => CreateUniverseEngineRequest.fromWire(value),
      'register_universe' => RegisterUniverseEngineRequest.fromWire(value),
      'rename_universe' => RenameUniverseEngineRequest.fromWire(value),
      'enroll' => EnrollEngineRequest.fromWire(value),
      'grant' => GrantEngineRequest.fromWire(value),
      'revoke' => RevokeEngineRequest.fromWire(value),
      'shutdown' => ShutdownEngineRequest.fromWire(value),
      _ => throw const FormatException('Unknown engine method'),
    };
  }
}

final class StatusEngineRequest extends EngineRequest {
  const StatusEngineRequest();
  @override
  String get method => 'status';
  factory StatusEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method'});
    if (f.string('method') != 'status') {
      throw const FormatException('Wrong engine method');
    }
    return StatusEngineRequest();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('method', CanonicalString('status'))]);
}

final class DoctorEngineRequest extends EngineRequest {
  const DoctorEngineRequest();
  @override
  String get method => 'doctor';
  factory DoctorEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method'});
    if (f.string('method') != 'doctor') {
      throw const FormatException('Wrong engine method');
    }
    return DoctorEngineRequest();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('method', CanonicalString('doctor'))]);
}

final class ProfilesEngineRequest extends EngineRequest {
  const ProfilesEngineRequest();
  @override
  String get method => 'profiles';
  factory ProfilesEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method'});
    if (f.string('method') != 'profiles') {
      throw const FormatException('Wrong engine method');
    }
    return ProfilesEngineRequest();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('method', CanonicalString('profiles'))]);
}

final class WithdrawGrantEngineRequest extends EngineRequest {
  const WithdrawGrantEngineRequest({
    required this.profileId,
    required this.universeId,
  });
  final ProfileId profileId;
  final UniverseId universeId;
  @override
  String get method => 'withdraw_grant';
  factory WithdrawGrantEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'profile_id', 'universe_id'});
    if (f.string('method') != 'withdraw_grant') {
      throw const FormatException('Wrong engine method');
    }
    return WithdrawGrantEngineRequest(
      profileId: ProfileId.parse(f.string('profile_id')),
      universeId: UniverseId.parse(f.string('universe_id')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('withdraw_grant')),
    MapEntry('profile_id', CanonicalString(profileId.value)),
    MapEntry('universe_id', CanonicalString(universeId.value)),
  ]);
}

final class PreviewPurgeEngineRequest extends EngineRequest {
  const PreviewPurgeEngineRequest({required this.universe});
  final Selector universe;
  @override
  String get method => 'preview_purge';
  factory PreviewPurgeEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe'});
    if (f.string('method') != 'preview_purge') {
      throw const FormatException('Wrong engine method');
    }
    return PreviewPurgeEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('preview_purge')),
    MapEntry('universe', universe.toWire()),
  ]);
}

final class PurgeEngineRequest extends EngineRequest {
  const PurgeEngineRequest({
    required this.universe,
    required this.digest,
    required this.confirmation,
  });
  final Selector universe;
  final String digest;
  final String confirmation;
  @override
  String get method => 'purge';
  factory PurgeEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'method',
      'universe',
      'digest',
      'confirmation',
    });
    if (f.string('method') != 'purge') {
      throw const FormatException('Wrong engine method');
    }
    return PurgeEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      digest: f.string('digest'),
      confirmation: f.string('confirmation'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('purge')),
    MapEntry('universe', universe.toWire()),
    MapEntry('digest', CanonicalString(digest)),
    MapEntry('confirmation', CanonicalString(confirmation)),
  ]);
}

final class ToolEngineRequest extends EngineRequest {
  const ToolEngineRequest({required this.request});
  final Request request;
  @override
  String get method => 'tool';
  factory ToolEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'request'});
    if (f.string('method') != 'tool') {
      throw const FormatException('Wrong engine method');
    }
    return ToolEngineRequest(request: Request.fromWire(f.require('request')));
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('tool')),
    MapEntry('request', request.toWire()),
  ]);
}

final class LibraryEngineRequest extends EngineRequest {
  const LibraryEngineRequest({required this.universe});
  final Selector universe;
  @override
  String get method => 'library';
  factory LibraryEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe'});
    if (f.string('method') != 'library') {
      throw const FormatException('Wrong engine method');
    }
    return LibraryEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('library')),
    MapEntry('universe', universe.toWire()),
  ]);
}

final class ForkContinuityEngineRequest extends EngineRequest {
  const ForkContinuityEngineRequest({
    required this.universe,
    required this.name,
    required this.continuityId,
    required this.source,
    required this.revision,
  });
  final Selector universe;
  final String name;
  final ContinuityId continuityId;
  final ContinuityId source;
  final RevisionId revision;
  @override
  String get method => 'fork_continuity';
  factory ForkContinuityEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'method',
      'universe',
      'name',
      'continuity_id',
      'source',
      'revision',
    });
    if (f.string('method') != 'fork_continuity') {
      throw const FormatException('Wrong engine method');
    }
    return ForkContinuityEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      name: f.string('name'),
      continuityId: ContinuityId.parse(f.string('continuity_id')),
      source: ContinuityId.parse(f.string('source')),
      revision: RevisionId.parse(f.string('revision')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('fork_continuity')),
    MapEntry('universe', universe.toWire()),
    MapEntry('name', CanonicalString(name)),
    MapEntry('continuity_id', CanonicalString(continuityId.value)),
    MapEntry('source', CanonicalString(source.value)),
    MapEntry('revision', CanonicalString(revision.value)),
  ]);
}

final class CompareContinuitiesEngineRequest extends EngineRequest {
  const CompareContinuitiesEngineRequest({
    required this.universe,
    required this.target,
    required this.targetRevision,
    required this.source,
    required this.sourceRevision,
  });
  final Selector universe;
  final ContinuityId target;
  final RevisionId targetRevision;
  final ContinuityId source;
  final RevisionId sourceRevision;
  @override
  String get method => 'compare_continuities';
  factory CompareContinuitiesEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'method',
      'universe',
      'target',
      'target_revision',
      'source',
      'source_revision',
    });
    if (f.string('method') != 'compare_continuities') {
      throw const FormatException('Wrong engine method');
    }
    return CompareContinuitiesEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      target: ContinuityId.parse(f.string('target')),
      targetRevision: RevisionId.parse(f.string('target_revision')),
      source: ContinuityId.parse(f.string('source')),
      sourceRevision: RevisionId.parse(f.string('source_revision')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('compare_continuities')),
    MapEntry('universe', universe.toWire()),
    MapEntry('target', CanonicalString(target.value)),
    MapEntry('target_revision', CanonicalString(targetRevision.value)),
    MapEntry('source', CanonicalString(source.value)),
    MapEntry('source_revision', CanonicalString(sourceRevision.value)),
  ]);
}

final class PrepareAdoptionEngineRequest extends EngineRequest {
  PrepareAdoptionEngineRequest({
    required this.universe,
    required this.target,
    required this.targetRevision,
    required this.source,
    required this.sourceRevision,
    required Iterable<RecordId> recordIds,
  }) : recordIds = List.unmodifiable(recordIds);
  final Selector universe;
  final ContinuityId target;
  final RevisionId targetRevision;
  final ContinuityId source;
  final RevisionId sourceRevision;
  final List<RecordId> recordIds;
  @override
  String get method => 'prepare_adoption';
  factory PrepareAdoptionEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'method',
      'universe',
      'target',
      'target_revision',
      'source',
      'source_revision',
      'record_ids',
    });
    if (f.string('method') != 'prepare_adoption') {
      throw const FormatException('Wrong engine method');
    }
    return PrepareAdoptionEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      target: ContinuityId.parse(f.string('target')),
      targetRevision: RevisionId.parse(f.string('target_revision')),
      source: ContinuityId.parse(f.string('source')),
      sourceRevision: RevisionId.parse(f.string('source_revision')),
      recordIds: f
          .array('record_ids')
          .map((v) => RecordId.parse(wireString(v))),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('prepare_adoption')),
    MapEntry('universe', universe.toWire()),
    MapEntry('target', CanonicalString(target.value)),
    MapEntry('target_revision', CanonicalString(targetRevision.value)),
    MapEntry('source', CanonicalString(source.value)),
    MapEntry('source_revision', CanonicalString(sourceRevision.value)),
    MapEntry(
      'record_ids',
      CanonicalArray(recordIds.map((v) => CanonicalString(v.value))),
    ),
  ]);
}

final class LoadDraftEngineRequest extends EngineRequest {
  const LoadDraftEngineRequest({
    required this.universe,
    required this.continuityId,
  });
  final Selector universe;
  final ContinuityId continuityId;
  @override
  String get method => 'load_draft';
  factory LoadDraftEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe', 'continuity_id'});
    if (f.string('method') != 'load_draft') {
      throw const FormatException('Wrong engine method');
    }
    return LoadDraftEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      continuityId: ContinuityId.parse(f.string('continuity_id')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('load_draft')),
    MapEntry('universe', universe.toWire()),
    MapEntry('continuity_id', CanonicalString(continuityId.value)),
  ]);
}

final class SaveDraftEngineRequest extends EngineRequest {
  SaveDraftEngineRequest({
    required this.universe,
    required this.continuityId,
    required BigInt expectedVersion,
    required this.content,
  }) : expectedVersion = checkedU64(expectedVersion);
  final Selector universe;
  final ContinuityId continuityId;
  final BigInt expectedVersion;
  final DraftContent content;
  @override
  String get method => 'save_draft';
  factory SaveDraftEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'method',
      'universe',
      'continuity_id',
      'expected_version',
      'content',
    });
    if (f.string('method') != 'save_draft') {
      throw const FormatException('Wrong engine method');
    }
    return SaveDraftEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      continuityId: ContinuityId.parse(f.string('continuity_id')),
      expectedVersion: f.u64('expected_version'),
      content: DraftContent.fromWire(f.require('content')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('save_draft')),
    MapEntry('universe', universe.toWire()),
    MapEntry('continuity_id', CanonicalString(continuityId.value)),
    MapEntry('expected_version', CanonicalNumber(expectedVersion.toString())),
    MapEntry('content', content.toWire()),
  ]);
}

final class StageImageEngineRequest extends EngineRequest {
  const StageImageEngineRequest({required this.universe, required this.source});
  final Selector universe;
  final String source;
  @override
  String get method => 'stage_image';
  factory StageImageEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe', 'source'});
    if (f.string('method') != 'stage_image') {
      throw const FormatException('Wrong engine method');
    }
    return StageImageEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      source: f.string('source'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('stage_image')),
    MapEntry('universe', universe.toWire()),
    MapEntry('source', CanonicalString(source)),
  ]);
}

final class ImagePreviewEngineRequest extends EngineRequest {
  const ImagePreviewEngineRequest({
    required this.universe,
    required this.contextId,
    required this.asset,
  });
  final Selector universe;
  final ContextId contextId;
  final RecordId asset;
  @override
  String get method => 'image_preview';
  factory ImagePreviewEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe', 'context_id', 'asset'});
    if (f.string('method') != 'image_preview') {
      throw const FormatException('Wrong engine method');
    }
    return ImagePreviewEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      contextId: ContextId.parse(f.string('context_id')),
      asset: RecordId.parse(f.string('asset')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('image_preview')),
    MapEntry('universe', universe.toWire()),
    MapEntry('context_id', CanonicalString(contextId.value)),
    MapEntry('asset', CanonicalString(asset.value)),
  ]);
}

final class AuthorWritingEngineRequest extends EngineRequest {
  const AuthorWritingEngineRequest({
    required this.universe,
    required this.action,
  });
  final Selector universe;
  final AuthorWritingAction action;
  @override
  String get method => 'author_writing';
  factory AuthorWritingEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe', 'action'});
    if (f.string('method') != 'author_writing') {
      throw const FormatException('Wrong engine method');
    }
    return AuthorWritingEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      action: AuthorWritingAction.fromWire(f.require('action')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('author_writing')),
    MapEntry('universe', universe.toWire()),
    MapEntry('action', action.toWire()),
  ]);
}

final class StageSourceEngineRequest extends EngineRequest {
  const StageSourceEngineRequest({
    required this.universe,
    required this.label,
    required this.text,
  });
  final Selector universe;
  final String label;
  final String text;
  @override
  String get method => 'stage_source';
  factory StageSourceEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe', 'label', 'text'});
    if (f.string('method') != 'stage_source') {
      throw const FormatException('Wrong engine method');
    }
    return StageSourceEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      label: f.string('label'),
      text: f.string('text'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('stage_source')),
    MapEntry('universe', universe.toWire()),
    MapEntry('label', CanonicalString(label)),
    MapEntry('text', CanonicalString(text)),
  ]);
}

final class BackupEngineRequest extends EngineRequest {
  const BackupEngineRequest({
    required this.universe,
    required this.destination,
  });
  final Selector universe;
  final String destination;
  @override
  String get method => 'backup';
  factory BackupEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe', 'destination'});
    if (f.string('method') != 'backup') {
      throw const FormatException('Wrong engine method');
    }
    return BackupEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      destination: f.string('destination'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('backup')),
    MapEntry('universe', universe.toWire()),
    MapEntry('destination', CanonicalString(destination)),
  ]);
}

final class RestoreEngineRequest extends EngineRequest {
  const RestoreEngineRequest({required this.source, required this.name});
  final String source;
  final String name;
  @override
  String get method => 'restore';
  factory RestoreEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'source', 'name'});
    if (f.string('method') != 'restore') {
      throw const FormatException('Wrong engine method');
    }
    return RestoreEngineRequest(
      source: f.string('source'),
      name: f.string('name'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('restore')),
    MapEntry('source', CanonicalString(source)),
    MapEntry('name', CanonicalString(name)),
  ]);
}

final class MaintainEngineRequest extends EngineRequest {
  const MaintainEngineRequest({required this.universe, required this.collect});
  final Selector universe;
  final bool collect;
  @override
  String get method => 'maintain';
  factory MaintainEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe', 'collect'});
    if (f.string('method') != 'maintain') {
      throw const FormatException('Wrong engine method');
    }
    return MaintainEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      collect: f.boolean('collect'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('maintain')),
    MapEntry('universe', universe.toWire()),
    MapEntry('collect', CanonicalBool(collect)),
  ]);
}

final class ConvertLegacyEngineRequest extends EngineRequest {
  const ConvertLegacyEngineRequest({
    required this.source,
    required this.destination,
  });
  final String source;
  final String destination;
  @override
  String get method => 'convert_legacy';
  factory ConvertLegacyEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'source', 'destination'});
    if (f.string('method') != 'convert_legacy') {
      throw const FormatException('Wrong engine method');
    }
    return ConvertLegacyEngineRequest(
      source: f.string('source'),
      destination: f.string('destination'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('convert_legacy')),
    MapEntry('source', CanonicalString(source)),
    MapEntry('destination', CanonicalString(destination)),
  ]);
}

final class ExportLogicalEngineRequest extends EngineRequest {
  ExportLogicalEngineRequest({
    required this.universe,
    required this.destination,
    required Iterable<RecordId> recordIds,
    this.completeHistory = false,
  }) : recordIds = List.unmodifiable(recordIds);
  final Selector universe;
  final String destination;
  final List<RecordId> recordIds;
  final bool completeHistory;
  @override
  String get method => 'export_logical';
  factory ExportLogicalEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'method',
      'universe',
      'destination',
      'record_ids',
      'complete_history',
    });
    if (f.string('method') != 'export_logical') {
      throw const FormatException('Wrong engine method');
    }
    return ExportLogicalEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      destination: f.string('destination'),
      recordIds: f
          .array('record_ids')
          .map((v) => RecordId.parse(wireString(v))),
      completeHistory: f.values.containsKey('complete_history')
          ? f.boolean('complete_history')
          : false,
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('export_logical')),
    MapEntry('universe', universe.toWire()),
    MapEntry('destination', CanonicalString(destination)),
    MapEntry(
      'record_ids',
      CanonicalArray(recordIds.map((v) => CanonicalString(v.value))),
    ),
    MapEntry('complete_history', CanonicalBool(completeHistory)),
  ]);
}

final class PreviewImportEngineRequest extends EngineRequest {
  const PreviewImportEngineRequest({
    required this.source,
    required this.name,
    required this.mode,
  });
  final String source;
  final String name;
  final ImportMode mode;
  @override
  String get method => 'preview_import';
  factory PreviewImportEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'source', 'name', 'mode'});
    if (f.string('method') != 'preview_import') {
      throw const FormatException('Wrong engine method');
    }
    return PreviewImportEngineRequest(
      source: f.string('source'),
      name: f.string('name'),
      mode: ImportMode.fromName(f.string('mode')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('preview_import')),
    MapEntry('source', CanonicalString(source)),
    MapEntry('name', CanonicalString(name)),
    MapEntry('mode', CanonicalString(mode.name)),
  ]);
}

final class AcceptImportEngineRequest extends EngineRequest {
  const AcceptImportEngineRequest({
    required this.previewId,
    required this.digest,
  });
  final OperationId previewId;
  final String digest;
  @override
  String get method => 'accept_import';
  factory AcceptImportEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'preview_id', 'digest'});
    if (f.string('method') != 'accept_import') {
      throw const FormatException('Wrong engine method');
    }
    return AcceptImportEngineRequest(
      previewId: OperationId.parse(f.string('preview_id')),
      digest: f.string('digest'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('accept_import')),
    MapEntry('preview_id', CanonicalString(previewId.value)),
    MapEntry('digest', CanonicalString(digest)),
  ]);
}

final class ReviewEngineRequest extends EngineRequest {
  const ReviewEngineRequest({
    required this.universe,
    required this.proposalReference,
  });
  final Selector universe;
  final ProposalRef proposalReference;
  @override
  String get method => 'review';
  factory ReviewEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe', 'proposal_reference'});
    if (f.string('method') != 'review') {
      throw const FormatException('Wrong engine method');
    }
    return ReviewEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('review')),
    MapEntry('universe', universe.toWire()),
    MapEntry('proposal_reference', proposalReference.toWire()),
  ]);
}

final class ApproveEngineRequest extends EngineRequest {
  const ApproveEngineRequest({
    required this.universe,
    required this.proposalReference,
    required this.validationRun,
  });
  final Selector universe;
  final ProposalRef proposalReference;
  final ValidationRunId validationRun;
  @override
  String get method => 'approve';
  factory ApproveEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'method',
      'universe',
      'proposal_reference',
      'validation_run',
    });
    if (f.string('method') != 'approve') {
      throw const FormatException('Wrong engine method');
    }
    return ApproveEngineRequest(
      universe: Selector.fromWire(f.require('universe')),
      proposalReference: ProposalRef.fromWire(f.require('proposal_reference')),
      validationRun: ValidationRunId.parse(f.string('validation_run')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('approve')),
    MapEntry('universe', universe.toWire()),
    MapEntry('proposal_reference', proposalReference.toWire()),
    MapEntry('validation_run', CanonicalString(validationRun.value)),
  ]);
}

final class CreateUniverseEngineRequest extends EngineRequest {
  const CreateUniverseEngineRequest({required this.name, required this.start});
  final String name;
  final UniverseStart start;
  @override
  String get method => 'create_universe';
  factory CreateUniverseEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'name', 'start'});
    if (f.string('method') != 'create_universe') {
      throw const FormatException('Wrong engine method');
    }
    return CreateUniverseEngineRequest(
      name: f.string('name'),
      start: UniverseStart.fromWire(f.require('start')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('create_universe')),
    MapEntry('name', CanonicalString(name)),
    MapEntry('start', start.toWire()),
  ]);
}

final class RegisterUniverseEngineRequest extends EngineRequest {
  const RegisterUniverseEngineRequest({required this.path, required this.name});
  final String path;
  final String name;
  @override
  String get method => 'register_universe';
  factory RegisterUniverseEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'path', 'name'});
    if (f.string('method') != 'register_universe') {
      throw const FormatException('Wrong engine method');
    }
    return RegisterUniverseEngineRequest(
      path: f.string('path'),
      name: f.string('name'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('register_universe')),
    MapEntry('path', CanonicalString(path)),
    MapEntry('name', CanonicalString(name)),
  ]);
}

final class RenameUniverseEngineRequest extends EngineRequest {
  const RenameUniverseEngineRequest({
    required this.universeId,
    required this.name,
  });
  final UniverseId universeId;
  final String name;
  @override
  String get method => 'rename_universe';
  factory RenameUniverseEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'universe_id', 'name'});
    if (f.string('method') != 'rename_universe') {
      throw const FormatException('Wrong engine method');
    }
    return RenameUniverseEngineRequest(
      universeId: UniverseId.parse(f.string('universe_id')),
      name: f.string('name'),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('rename_universe')),
    MapEntry('universe_id', CanonicalString(universeId.value)),
    MapEntry('name', CanonicalString(name)),
  ]);
}

final class EnrollEngineRequest extends EngineRequest {
  const EnrollEngineRequest();
  @override
  String get method => 'enroll';
  factory EnrollEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method'});
    if (f.string('method') != 'enroll') {
      throw const FormatException('Wrong engine method');
    }
    return EnrollEngineRequest();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('method', CanonicalString('enroll'))]);
}

final class GrantEngineRequest extends EngineRequest {
  const GrantEngineRequest({required this.grant});
  final GrantSpec grant;
  @override
  String get method => 'grant';
  factory GrantEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'grant'});
    if (f.string('method') != 'grant') {
      throw const FormatException('Wrong engine method');
    }
    return GrantEngineRequest(grant: GrantSpec.fromWire(f.require('grant')));
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('grant')),
    MapEntry('grant', grant.toWire()),
  ]);
}

final class RevokeEngineRequest extends EngineRequest {
  const RevokeEngineRequest({required this.profileId});
  final ProfileId profileId;
  @override
  String get method => 'revoke';
  factory RevokeEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method', 'profile_id'});
    if (f.string('method') != 'revoke') {
      throw const FormatException('Wrong engine method');
    }
    return RevokeEngineRequest(
      profileId: ProfileId.parse(f.string('profile_id')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('method', CanonicalString('revoke')),
    MapEntry('profile_id', CanonicalString(profileId.value)),
  ]);
}

final class ShutdownEngineRequest extends EngineRequest {
  const ShutdownEngineRequest();
  @override
  String get method => 'shutdown';
  factory ShutdownEngineRequest.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'method'});
    if (f.string('method') != 'shutdown') {
      throw const FormatException('Wrong engine method');
    }
    return ShutdownEngineRequest();
  }
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('method', CanonicalString('shutdown'))]);
}

final class EngineCall {
  EngineCall({required BigInt id, required this.request}) : id = checkedU64(id);
  final BigInt id;
  final EngineRequest request;
  factory EngineCall.decode(Uint8List bytes) =>
      EngineCall.fromWire(decodeWireFrame(bytes));
  factory EngineCall.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'id', 'request'});
    return EngineCall(
      id: f.u64('id'),
      request: EngineRequest.fromWire(f.require('request')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('id', CanonicalNumber(id.toString())),
    MapEntry('request', request.toWire()),
  ]);
}

sealed class EngineResult {
  const EngineResult();
  CanonicalObject toWire();
  static EngineResult fromWire(CanonicalValue value) {
    final f = WireFields(value, {'Ok', 'Err'});
    if (f.values.length != 1) {
      throw const FormatException('Expected exactly one engine result');
    }
    if (f.values.containsKey('Ok')) return EngineSuccess(f.require('Ok'));
    return EngineFailure(ProtocolError.fromWire(f.require('Err')));
  }
}

final class EngineSuccess extends EngineResult {
  const EngineSuccess(this.value);
  final CanonicalValue value;
  @override
  CanonicalObject toWire() => CanonicalObject([MapEntry('Ok', value)]);
}

final class EngineFailure extends EngineResult {
  const EngineFailure(this.error);
  final ProtocolError error;
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('Err', error.toWire())]);
}

final class EngineReply {
  EngineReply({required BigInt id, required this.result}) : id = checkedU64(id);
  final BigInt id;
  final EngineResult result;
  factory EngineReply.decode(Uint8List bytes) =>
      EngineReply.fromWire(decodeWireFrame(bytes));
  factory EngineReply.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'id', 'result'});
    return EngineReply(
      id: f.u64('id'),
      result: EngineResult.fromWire(f.require('result')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('id', CanonicalNumber(id.toString())),
    MapEntry('result', result.toWire()),
  ]);
}
