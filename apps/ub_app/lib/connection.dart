import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final class AppSession {
  const AppSession({
    this.backupFile,
    this.restoreBackupFile,
    required this.call,
    required this.close,
    required this.author,
    required this.principal,
    required this.loadWorldForm,
    required this.saveWorldForm,
    required this.loadTypeForm,
    required this.saveTypeForm,
    required this.loadPropertyForm,
    required this.savePropertyForm,
    required this.loadUnitForm,
    required this.saveUnitForm,
    required this.loadRelationForm,
    required this.saveRelationForm,
    required this.loadCommunicationForm,
    required this.saveCommunicationForm,
    required this.loadItemPowerForm,
    required this.saveItemPowerForm,
    required this.loadIssueDecisionForm,
    required this.saveIssueDecisionForm,
    required this.loadExceptionForm,
    required this.saveExceptionForm,
    required this.loadWorkVersionForm,
    required this.saveWorkVersionForm,
    required this.loadSagaForm,
    required this.saveSagaForm,
    required this.loadWorkForm,
    required this.saveWorkForm,
    required this.loadBoundaryForm,
    required this.saveBoundaryForm,
    required this.loadCommitmentForm,
    required this.saveCommitmentForm,
    required this.loadPlanForm,
    required this.savePlanForm,
    required this.loadRepresentedContextForm,
    required this.saveRepresentedContextForm,
    required this.loadMemoryForm,
    required this.saveMemoryForm,
    required this.loadObservationForm,
    required this.saveObservationForm,
    required this.loadAttitudeForm,
    required this.saveAttitudeForm,
    required this.loadPropositionForm,
    required this.savePropositionForm,
    required this.loadCompletenessForm,
    required this.saveCompletenessForm,
    required this.loadRuleForm,
    required this.saveRuleForm,
    required this.loadActionForm,
    required this.saveActionForm,
    required this.loadEventForm,
    required this.saveEventForm,
    required this.loadSourceForm,
    required this.saveSourceForm,
    required this.loadValueDefinitionForm,
    required this.saveValueDefinitionForm,
    required this.loadCalendarForm,
    required this.saveCalendarForm,
    required this.loadEntityForm,
    required this.saveEntityForm,
    required this.loadAttributeForm,
    required this.saveAttributeForm,
  });
  final Future<String?> Function(LibraryEntry)? backupFile;
  final Future<LibraryEntry?> Function(String name)? restoreBackupFile;
  final Future<CanonicalValue> Function(EngineRequest) call;
  final Future<void> Function() close;
  final bool author;
  final ProfileId principal;
  final Future<SavedWorldForm?> Function(EditorFormScope) loadWorldForm;
  final Future<SavedWorldForm> Function(
    EditorFormScope,
    UnfinishedWorldForm,
    BigInt,
  )
  saveWorldForm;
  final Future<SavedTypeForm?> Function(EditorFormScope) loadTypeForm;
  final Future<SavedTypeForm> Function(
    EditorFormScope,
    UnfinishedTypeForm,
    BigInt,
  )
  saveTypeForm;
  final Future<SavedPropertyForm?> Function(EditorFormScope) loadPropertyForm;
  final Future<SavedPropertyForm> Function(
    EditorFormScope,
    UnfinishedPropertyForm,
    BigInt,
  )
  savePropertyForm;
  final Future<SavedUnitForm?> Function(EditorFormScope) loadUnitForm;
  final Future<SavedUnitForm> Function(
    EditorFormScope,
    UnfinishedUnitForm,
    BigInt,
  )
  saveUnitForm;
  final Future<SavedValueDefinitionForm?> Function(EditorFormScope)
  loadValueDefinitionForm;
  final Future<SavedValueDefinitionForm> Function(
    EditorFormScope,
    UnfinishedValueDefinitionForm,
    BigInt,
  )
  saveValueDefinitionForm;
  final Future<SavedRelationForm?> Function(EditorFormScope) loadRelationForm;
  final Future<SavedRelationForm> Function(
    EditorFormScope,
    UnfinishedRelationForm,
    BigInt,
  )
  saveRelationForm;
  final Future<SavedCommunicationForm?> Function(EditorFormScope)
  loadCommunicationForm;
  final Future<SavedCommunicationForm> Function(
    EditorFormScope,
    UnfinishedCommunicationForm,
    BigInt,
  )
  saveCommunicationForm;
  final Future<SavedItemPowerForm?> Function(EditorFormScope) loadItemPowerForm;
  final Future<SavedItemPowerForm> Function(
    EditorFormScope,
    UnfinishedItemPowerForm,
    BigInt,
  )
  saveItemPowerForm;
  final Future<SavedIssueDecisionForm?> Function(EditorFormScope)
  loadIssueDecisionForm;
  final Future<SavedIssueDecisionForm> Function(
    EditorFormScope,
    UnfinishedIssueDecisionForm,
    BigInt,
  )
  saveIssueDecisionForm;
  final Future<SavedExceptionForm?> Function(EditorFormScope) loadExceptionForm;
  final Future<SavedExceptionForm> Function(
    EditorFormScope,
    UnfinishedExceptionForm,
    BigInt,
  )
  saveExceptionForm;
  final Future<SavedWorkVersionForm?> Function(EditorFormScope)
  loadWorkVersionForm;
  final Future<SavedWorkVersionForm> Function(
    EditorFormScope,
    UnfinishedWorkVersionForm,
    BigInt,
  )
  saveWorkVersionForm;
  final Future<SavedSagaForm?> Function(EditorFormScope) loadSagaForm;
  final Future<SavedSagaForm> Function(
    EditorFormScope,
    UnfinishedSagaForm,
    BigInt,
  )
  saveSagaForm;
  final Future<SavedWorkForm?> Function(EditorFormScope) loadWorkForm;
  final Future<SavedWorkForm> Function(
    EditorFormScope,
    UnfinishedWorkForm,
    BigInt,
  )
  saveWorkForm;
  final Future<SavedBoundaryForm?> Function(EditorFormScope) loadBoundaryForm;
  final Future<SavedBoundaryForm> Function(
    EditorFormScope,
    UnfinishedBoundaryForm,
    BigInt,
  )
  saveBoundaryForm;
  final Future<SavedCommitmentForm?> Function(EditorFormScope)
  loadCommitmentForm;
  final Future<SavedCommitmentForm> Function(
    EditorFormScope,
    UnfinishedCommitmentForm,
    BigInt,
  )
  saveCommitmentForm;
  final Future<SavedPlanForm?> Function(EditorFormScope) loadPlanForm;
  final Future<SavedPlanForm> Function(
    EditorFormScope,
    UnfinishedPlanForm,
    BigInt,
  )
  savePlanForm;
  final Future<SavedRepresentedContextForm?> Function(EditorFormScope)
  loadRepresentedContextForm;
  final Future<SavedRepresentedContextForm> Function(
    EditorFormScope,
    UnfinishedRepresentedContextForm,
    BigInt,
  )
  saveRepresentedContextForm;
  final Future<SavedMemoryForm?> Function(EditorFormScope) loadMemoryForm;
  final Future<SavedMemoryForm> Function(
    EditorFormScope,
    UnfinishedMemoryForm,
    BigInt,
  )
  saveMemoryForm;
  final Future<SavedObservationForm?> Function(EditorFormScope)
  loadObservationForm;
  final Future<SavedObservationForm> Function(
    EditorFormScope,
    UnfinishedObservationForm,
    BigInt,
  )
  saveObservationForm;
  final Future<SavedAttitudeForm?> Function(EditorFormScope) loadAttitudeForm;
  final Future<SavedAttitudeForm> Function(
    EditorFormScope,
    UnfinishedAttitudeForm,
    BigInt,
  )
  saveAttitudeForm;
  final Future<SavedPropositionForm?> Function(EditorFormScope)
  loadPropositionForm;
  final Future<SavedPropositionForm> Function(
    EditorFormScope,
    UnfinishedPropositionForm,
    BigInt,
  )
  savePropositionForm;
  final Future<SavedCompletenessForm?> Function(EditorFormScope)
  loadCompletenessForm;
  final Future<SavedCompletenessForm> Function(
    EditorFormScope,
    UnfinishedCompletenessForm,
    BigInt,
  )
  saveCompletenessForm;
  final Future<SavedRuleForm?> Function(EditorFormScope) loadRuleForm;
  final Future<SavedRuleForm> Function(
    EditorFormScope,
    UnfinishedRuleForm,
    BigInt,
  )
  saveRuleForm;
  final Future<SavedActionForm?> Function(EditorFormScope) loadActionForm;
  final Future<SavedActionForm> Function(
    EditorFormScope,
    UnfinishedActionForm,
    BigInt,
  )
  saveActionForm;
  final Future<SavedEventForm?> Function(EditorFormScope) loadEventForm;
  final Future<SavedEventForm> Function(
    EditorFormScope,
    UnfinishedEventForm,
    BigInt,
  )
  saveEventForm;
  final Future<SavedSourceForm?> Function(EditorFormScope) loadSourceForm;
  final Future<SavedSourceForm> Function(
    EditorFormScope,
    UnfinishedSourceForm,
    BigInt,
  )
  saveSourceForm;
  final Future<SavedCalendarForm?> Function(EditorFormScope) loadCalendarForm;
  final Future<SavedCalendarForm> Function(
    EditorFormScope,
    UnfinishedCalendarForm,
    BigInt,
  )
  saveCalendarForm;
  final Future<SavedEntityForm?> Function(EditorFormScope) loadEntityForm;
  final Future<SavedEntityForm> Function(
    EditorFormScope,
    UnfinishedEntityForm,
    BigInt,
  )
  saveEntityForm;
  final Future<SavedAttributeForm?> Function(EditorFormScope) loadAttributeForm;
  final Future<SavedAttributeForm> Function(
    EditorFormScope,
    UnfinishedAttributeForm,
    BigInt,
  )
  saveAttributeForm;
}

final class LibraryEntry {
  const LibraryEntry(this.id, this.name);
  final UniverseId id;
  final String name;
}

enum ConnectedBackend { sqlite, postgres }

final class TestedSqliteConnection {
  const TestedSqliteConnection({required this.instance, required this.profile});
  final OperationId instance;
  final ProfileId profile;
}

/// A device-local selection. Never serialized or returned to a browser/API.
final class TestedPostgresConnection {
  const TestedPostgresConnection({
    required this.endpoint,
    required this.instance,
    required this.profile,
  });
  final String endpoint;
  final OperationId instance;
  final ProfileId profile;
  @override
  String toString() => 'TestedPostgresConnection([redacted])';
}

final class InstanceLibrary {
  InstanceLibrary({
    required this.instance,
    required this.backend,
    required Iterable<LibraryEntry> universes,
  }) : universes = List.unmodifiable(universes);
  final OperationId instance;
  final ConnectedBackend backend;
  final List<LibraryEntry> universes;
  factory InstanceLibrary.fromWire(CanonicalValue value) {
    final fields = Map.fromEntries((value as CanonicalObject).fields);
    return InstanceLibrary(
      instance: OperationId.parse(wireString(fields['instance_id']!)),
      backend: switch (wireString(fields['backend']!)) {
        'sqlite' => ConnectedBackend.sqlite,
        'postgres' => ConnectedBackend.postgres,
        _ => throw const FormatException('Unsupported connected backend'),
      },
      universes: (fields['universes']! as CanonicalArray).items.map((entry) {
        final row = WireFields(entry, {'id', 'name'});
        return LibraryEntry(
          UniverseId.parse(row.string('id')),
          row.string('name'),
        );
      }),
    );
  }
}
