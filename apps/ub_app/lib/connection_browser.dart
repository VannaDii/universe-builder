import 'package:ub_client/browser_engine.dart';
import 'package:ub_client/browser_http.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:web/web.dart' as web;

import 'package:ub_client/browser_world_recovery.dart';
import 'package:ub_client/browser_type_recovery.dart';
import 'package:ub_client/browser_property_recovery.dart';
import 'package:ub_client/browser_unit_recovery.dart';
import 'package:ub_client/browser_relation_recovery.dart';
import 'package:ub_client/browser_communication_recovery.dart';
import 'package:ub_client/browser_item_power_recovery.dart';
import 'package:ub_client/browser_issue_decision_recovery.dart';
import 'package:ub_client/browser_exception_recovery.dart';
import 'package:ub_client/browser_work_version_recovery.dart';
import 'package:ub_client/browser_saga_recovery.dart';
import 'package:ub_client/browser_work_recovery.dart';
import 'package:ub_client/browser_scene_recovery.dart';
import 'package:ub_client/browser_passage_recovery.dart';
import 'package:ub_client/browser_interpretation_recovery.dart';
import 'package:ub_client/browser_assertion_retraction_recovery.dart';
import 'package:ub_client/browser_assertion_end_recovery.dart';
import 'package:ub_client/browser_assertion_correction_recovery.dart';
import 'package:ub_client/browser_event_withdrawal_recovery.dart';
import 'package:ub_client/browser_pack_recovery.dart';
import 'package:ub_client/browser_record_removal_recovery.dart';
import 'package:ub_client/browser_boundary_recovery.dart';
import 'package:ub_client/browser_commitment_recovery.dart';
import 'package:ub_client/browser_plan_recovery.dart';
import 'package:ub_client/browser_represented_context_recovery.dart';
import 'package:ub_client/browser_memory_recovery.dart';
import 'package:ub_client/browser_observation_recovery.dart';
import 'package:ub_client/browser_secret_recovery.dart';
import 'package:ub_client/browser_appearance_recovery.dart';
import 'package:ub_client/browser_attitude_recovery.dart';
import 'package:ub_client/browser_proposition_recovery.dart';
import 'package:ub_client/browser_completeness_recovery.dart';
import 'package:ub_client/browser_rule_recovery.dart';
import 'package:ub_client/browser_action_recovery.dart';
import 'package:ub_client/browser_event_recovery.dart';
import 'package:ub_client/browser_source_recovery.dart';
import 'package:ub_client/browser_value_definition_recovery.dart';
import 'package:ub_client/browser_calendar_recovery.dart';
import 'package:ub_client/browser_entity_recovery.dart';
import 'package:ub_client/browser_attribute_recovery.dart';

import 'package:ub_client/browser_story_time_recovery.dart';
import 'connection.dart';
import 'browser_source_files.dart';
import 'browser_image_files.dart';
import 'browser_package_files.dart';
import 'browser_package_import_recovery.dart';
import 'browser_universe_creation_recovery.dart';

/// The service owns canon and credentials; this tab holds only its short-lived
/// CSRF token and origin-private unfinished editor input.
final class DeviceConnection {
  bool get supportsHosted => false;
  bool get isHosted => true;
  HostedConnectionChoice? hosted;
  DeviceConnection(
    List<String> arguments, {
    Future<String?> Function(String)? saveBackupFile,
    Future<bool> Function(String)? openBackupFile,
    Future<String?> Function()? pickImagePath,
    Future<String?> Function()? pickSourcePath,
    Future<String?> Function()? pickSharedSourcePath,
    Future<void> Function(String)? releasePickedPath,
    Future<String?> Function()? installationRoot,
  });
  static const _csrfKey = 'ub-browser-session-csrf';
  String? browserEnrollmentToken;
  String? _csrf;
  bool get supportsLocal => false;
  bool get supportsLocalSettings => false;
  bool get supportsBrowser => true;
  bool get available => true;
  String get unavailableMessage =>
      'Open this app from your running Universe Builder instance.';
  Future<TestedPostgresConnection> testPostgres(String endpoint) =>
      Future.error(StateError('Local setup unavailable'));
  Future<void> savePostgres(TestedPostgresConnection choice) =>
      Future.error(StateError('Local setup unavailable'));
  Future<TestedSqliteConnection> testSqlite() =>
      Future.error(StateError('Local setup unavailable'));
  Future<void> saveSqlite(TestedSqliteConnection choice) =>
      Future.error(StateError('Local setup unavailable'));

  Future<AppSession> connect() async {
    final transport = SameOriginBrowserTransport();
    final token = browserEnrollmentToken;
    browserEnrollmentToken = null;
    try {
      _csrf ??= web.window.sessionStorage.getItem(_csrfKey);
    } on Object {
      /* Reconnect remains possible in this page. */
    }
    late BrowserEngineClient client;
    try {
      client = await BrowserEngineClient.connect(
        post: transport.post,
        abort: transport.close,
        enrollmentToken: token,
        resumeCsrf: token == null ? _csrf : null,
      );
    } on Object {
      transport.close();
      _csrf = null;
      try {
        web.window.sessionStorage.removeItem(_csrfKey);
      } on Object {
        /* Storage can be disabled. */
      }
      rethrow;
    }
    _csrf = client.csrf;
    try {
      web.window.sessionStorage.setItem(_csrfKey, client.csrf);
    } on Object {
      /* Retain it in memory when storage is disabled. */
    }
    final closeStores = <void Function()>[];
    try {
      final worldStore = await BrowserWorldFormRecoveryStore.open();
      closeStores.add(worldStore.close);
      final worldRecovery = BrowserWorldFormRecovery(
        store: worldStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final typeStore = await BrowserTypeFormRecoveryStore.open();
      closeStores.add(typeStore.close);
      final typeRecovery = BrowserTypeFormRecovery(
        store: typeStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final propertyStore = await BrowserPropertyFormRecoveryStore.open();
      closeStores.add(propertyStore.close);
      final propertyRecovery = BrowserPropertyFormRecovery(
        store: propertyStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final unitStore = await BrowserUnitFormRecoveryStore.open();
      closeStores.add(unitStore.close);
      final unitRecovery = BrowserUnitFormRecovery(
        store: unitStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final relationStore = await BrowserRelationFormRecoveryStore.open();
      closeStores.add(relationStore.close);
      final relationRecovery = BrowserRelationFormRecovery(
        store: relationStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final communicationStore =
          await BrowserCommunicationFormRecoveryStore.open();
      closeStores.add(communicationStore.close);
      final communicationRecovery = BrowserCommunicationFormRecovery(
        store: communicationStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final itemPowerStore = await BrowserItemPowerFormRecoveryStore.open();
      closeStores.add(itemPowerStore.close);
      final itemPowerRecovery = BrowserItemPowerFormRecovery(
        store: itemPowerStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final issueDecisionStore =
          await BrowserIssueDecisionFormRecoveryStore.open();
      closeStores.add(issueDecisionStore.close);
      final issueDecisionRecovery = BrowserIssueDecisionFormRecovery(
        store: issueDecisionStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final exceptionStore = await BrowserExceptionFormRecoveryStore.open();
      closeStores.add(exceptionStore.close);
      final exceptionRecovery = BrowserExceptionFormRecovery(
        store: exceptionStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final workVersionStore = await BrowserWorkVersionFormRecoveryStore.open();
      closeStores.add(workVersionStore.close);
      final workVersionRecovery = BrowserWorkVersionFormRecovery(
        store: workVersionStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final sagaStore = await BrowserSagaFormRecoveryStore.open();
      closeStores.add(sagaStore.close);
      final sagaRecovery = BrowserSagaFormRecovery(
        store: sagaStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final workStore = await BrowserWorkFormRecoveryStore.open();
      closeStores.add(workStore.close);
      final workRecovery = BrowserWorkFormRecovery(
        store: workStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final sceneStore = await BrowserSceneFormRecoveryStore.open();
      closeStores.add(sceneStore.close);
      final sceneRecovery = BrowserSceneFormRecovery(
        store: sceneStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final passageStore = await BrowserPassageFormRecoveryStore.open();
      closeStores.add(passageStore.close);
      final passageRecovery = BrowserPassageFormRecovery(
        store: passageStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final interpretationStore =
          await BrowserInterpretationFormRecoveryStore.open();
      closeStores.add(interpretationStore.close);
      final interpretationRecovery = BrowserInterpretationFormRecovery(
        store: interpretationStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final assertionRetractionStore =
          await BrowserAssertionRetractionFormRecoveryStore.open();
      closeStores.add(assertionRetractionStore.close);
      final assertionRetractionRecovery =
          BrowserAssertionRetractionFormRecovery(
            store: assertionRetractionStore,
            principal: client.welcome.principal,
            call: client.call,
          );
      final assertionEndStore =
          await BrowserAssertionEndFormRecoveryStore.open();
      closeStores.add(assertionEndStore.close);
      final assertionEndRecovery = BrowserAssertionEndFormRecovery(
        store: assertionEndStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final assertionCorrectionStore =
          await BrowserAssertionCorrectionFormRecoveryStore.open();
      closeStores.add(assertionCorrectionStore.close);
      final assertionCorrectionRecovery =
          BrowserAssertionCorrectionFormRecovery(
            store: assertionCorrectionStore,
            principal: client.welcome.principal,
            call: client.call,
          );
      final eventWithdrawalStore =
          await BrowserEventWithdrawalFormRecoveryStore.open();
      closeStores.add(eventWithdrawalStore.close);
      final eventWithdrawalRecovery = BrowserEventWithdrawalFormRecovery(
        store: eventWithdrawalStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final packStore = await BrowserPackFormRecoveryStore.open();
      closeStores.add(packStore.close);
      final packRecovery = BrowserPackFormRecovery(
        store: packStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final recordRemovalStore =
          await BrowserRecordRemovalFormRecoveryStore.open();
      closeStores.add(recordRemovalStore.close);
      final recordRemovalRecovery = BrowserRecordRemovalFormRecovery(
        store: recordRemovalStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final boundaryStore = await BrowserBoundaryFormRecoveryStore.open();
      closeStores.add(boundaryStore.close);
      final boundaryRecovery = BrowserBoundaryFormRecovery(
        store: boundaryStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final commitmentStore = await BrowserCommitmentFormRecoveryStore.open();
      closeStores.add(commitmentStore.close);
      final commitmentRecovery = BrowserCommitmentFormRecovery(
        store: commitmentStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final planStore = await BrowserPlanFormRecoveryStore.open();
      closeStores.add(planStore.close);
      final planRecovery = BrowserPlanFormRecovery(
        store: planStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final representedContextStore =
          await BrowserRepresentedContextFormRecoveryStore.open();
      closeStores.add(representedContextStore.close);
      final representedContextRecovery = BrowserRepresentedContextFormRecovery(
        store: representedContextStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final memoryStore = await BrowserMemoryFormRecoveryStore.open();
      closeStores.add(memoryStore.close);
      final memoryRecovery = BrowserMemoryFormRecovery(
        store: memoryStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final storyTimeStore = await BrowserStoryTimeFormRecoveryStore.open();
      closeStores.add(storyTimeStore.close);
      final storyTimeRecovery=BrowserStoryTimeFormRecovery(store:storyTimeStore,
        principal:client.welcome.principal,call:client.call);
      final secretStore = await BrowserSecretFormRecoveryStore.open();
      closeStores.add(secretStore.close);
      final secretRecovery = BrowserSecretFormRecovery(
        store: secretStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final appearanceStore = await BrowserAppearanceFormRecoveryStore.open();
      closeStores.add(appearanceStore.close);
      final appearanceRecovery = BrowserAppearanceFormRecovery(
        store: appearanceStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final observationStore = await BrowserObservationFormRecoveryStore.open();
      closeStores.add(observationStore.close);
      final observationRecovery = BrowserObservationFormRecovery(
        store: observationStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final attitudeStore = await BrowserAttitudeFormRecoveryStore.open();
      closeStores.add(attitudeStore.close);
      final attitudeRecovery = BrowserAttitudeFormRecovery(
        store: attitudeStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final propositionStore = await BrowserPropositionFormRecoveryStore.open();
      closeStores.add(propositionStore.close);
      final propositionRecovery = BrowserPropositionFormRecovery(
        store: propositionStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final completenessStore =
          await BrowserCompletenessFormRecoveryStore.open();
      closeStores.add(completenessStore.close);
      final completenessRecovery = BrowserCompletenessFormRecovery(
        store: completenessStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final ruleStore = await BrowserRuleFormRecoveryStore.open();
      closeStores.add(ruleStore.close);
      final ruleRecovery = BrowserRuleFormRecovery(
        store: ruleStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final actionStore = await BrowserActionFormRecoveryStore.open();
      closeStores.add(actionStore.close);
      final actionRecovery = BrowserActionFormRecovery(
        store: actionStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final eventStore = await BrowserEventFormRecoveryStore.open();
      closeStores.add(eventStore.close);
      final eventRecovery = BrowserEventFormRecovery(
        store: eventStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final sourceStore = await BrowserSourceFormRecoveryStore.open();
      closeStores.add(sourceStore.close);
      final sourceRecovery = BrowserSourceFormRecovery(
        store: sourceStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final valueDefinitionStore =
          await BrowserValueDefinitionFormRecoveryStore.open();
      closeStores.add(valueDefinitionStore.close);
      final valueDefinitionRecovery = BrowserValueDefinitionFormRecovery(
        store: valueDefinitionStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final calendarStore = await BrowserCalendarFormRecoveryStore.open();
      closeStores.add(calendarStore.close);
      final calendarRecovery = BrowserCalendarFormRecovery(
        store: calendarStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final entityStore = await BrowserEntityFormRecoveryStore.open();
      closeStores.add(entityStore.close);
      final entityRecovery = BrowserEntityFormRecovery(
        store: entityStore,
        principal: client.welcome.principal,
        call: client.call,
      );
      final attributeStore = await BrowserAttributeFormRecoveryStore.open();
      closeStores.add(attributeStore.close);
      final attributeRecovery = BrowserAttributeFormRecovery(
        store: attributeStore,
        principal: client.welcome.principal,
        call: client.call,
      );

      final creationStore = await BrowserUniverseCreationFormRecoveryStore.open();
      closeStores.add(creationStore.close);
      final importStore = await BrowserPackageImportFormRecoveryStore.open();
      closeStores.add(importStore.close);
      final status = InstanceLibrary.fromWire(
        await client.call(const StatusEngineRequest()),
      );
      final importScope = (status.instance, client.welcome.principal);

      // Reference controls can request labels together; admit one call at a time,
      // without replaying a failed request.
      Future<void> pending = Future<void>.value();
      Future<T> sequenced<T>(Future<T> Function() action) {
        final result = pending.then((_) => action());
        pending = result.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        return result;
      }

      void closeRecovery() {
        for (final close in closeStores) {
          close();
        }
      }

      return AppSession(
        loadUniverseCreationForm: client.welcome.author
            ? () => creationStore.load(importScope) : null,
        saveUniverseCreationForm: client.welcome.author
            ? (form, generation) => creationStore.save(importScope, form, generation) : null,
        cancelArchiveUpload: client.close,
        loadPackageImport: client.welcome.author
            ? () => importStore.load(importScope)
            : null,
        savePackageImport: client.welcome.author
            ? (form, generation) =>
                  importStore.save(importScope, form, generation)
            : null,
        pickArchiveFile: client.welcome.author ? pickBrowserArchive : null,
        reviewArchiveFile: client.welcome.author
            ? (file, form) => sequenced(
                () => client.reviewArchiveFile(
                  upload: (csrf) => transport.postArchive(
                    file: file.source as web.File,
                    previewId: form.operation,
                    name: form.name,
                    mode: form.mode,
                    csrf: csrf,
                  ),
                ),
              )
            : null,
        downloadArchive: (universe) async {
          final archive = await sequenced(
            () => client.prepareArchiveDownload(Selector(universe.name)),
          );
          if (wireString(
                Map.fromEntries(archive.manifest.fields)['universe']!,
              ) !=
              universe.id.value) {
            throw const FormatException('Selected universe changed');
          }
          final link = web.HTMLAnchorElement()
            ..href = archive.path
            ..download = 'Universe Builder archive.sqlite';
          link.style.display = 'none';
          web.document.body!.append(link);
          try {
            link.click();
          } finally {
            link.remove();
          }
        },
        pickSourceText: pickBrowserSourceText,
        pickImage: client.welcome.author
            ? (universe) async {
                final file = await pickBrowserImage();
                if (file == null) return null;
                final result = StagedImage.fromWire(await sequenced(
                  () => client.stageImageFile(
                    upload: (csrf) => transport.postImage(
                      file: file, universe: universe, csrf: csrf,
                    ),
                  ),
                ));
                if (result.asset.originalName != file.name) {
                  throw const FormatException('Selected image differs from retained image.');
                }
                return result;
              }
            : null,
        call: (request) => sequenced(() => client.call(request)),
        close: () => sequenced(() async {
          closeRecovery();
          await client.close();
        }),
        logout: () => sequenced(() async {
          try {
            await client.logout();
          } finally {
            closeRecovery();
            _csrf = null;
            try {
              web.window.sessionStorage.removeItem(_csrfKey);
            } on Object {
              /* Storage can be disabled. */
            }
          }
        }),
        author: client.welcome.author,
        principal: client.welcome.principal,
        loadWorldForm: (scope) => sequenced(() => worldRecovery.load(scope)),
        saveWorldForm: worldRecovery.save,
        loadTypeForm: (scope) => sequenced(() => typeRecovery.load(scope)),
        saveTypeForm: typeRecovery.save,
        loadPropertyForm: (scope) =>
            sequenced(() => propertyRecovery.load(scope)),
        savePropertyForm: propertyRecovery.save,
        loadUnitForm: (scope) => sequenced(() => unitRecovery.load(scope)),
        saveUnitForm: unitRecovery.save,
        loadRelationForm: (scope) =>
            sequenced(() => relationRecovery.load(scope)),
        saveRelationForm: relationRecovery.save,
        loadCommunicationForm: (scope) =>
            sequenced(() => communicationRecovery.load(scope)),
        saveCommunicationForm: communicationRecovery.save,
        loadItemPowerForm: (scope) =>
            sequenced(() => itemPowerRecovery.load(scope)),
        saveItemPowerForm: itemPowerRecovery.save,
        loadIssueDecisionForm: (scope) =>
            sequenced(() => issueDecisionRecovery.load(scope)),
        saveIssueDecisionForm: issueDecisionRecovery.save,
        loadExceptionForm: (scope) =>
            sequenced(() => exceptionRecovery.load(scope)),
        saveExceptionForm: exceptionRecovery.save,
        loadWorkVersionForm: (scope) =>
            sequenced(() => workVersionRecovery.load(scope)),
        saveWorkVersionForm: workVersionRecovery.save,
        loadSagaForm: (scope) => sequenced(() => sagaRecovery.load(scope)),
        saveSagaForm: sagaRecovery.save,
        loadWorkForm: (scope) => sequenced(() => workRecovery.load(scope)),
        saveWorkForm: workRecovery.save,
        loadSceneForm: (scope) => sequenced(() => sceneRecovery.load(scope)),
        saveSceneForm: sceneRecovery.save,
        loadPassageForm: (scope) =>
            sequenced(() => passageRecovery.load(scope)),
        savePassageForm: passageRecovery.save,
        loadInterpretationForm: (scope) =>
            sequenced(() => interpretationRecovery.load(scope)),
        saveInterpretationForm: interpretationRecovery.save,
        loadAssertionRetractionForm: (scope) =>
            sequenced(() => assertionRetractionRecovery.load(scope)),
        saveAssertionRetractionForm: assertionRetractionRecovery.save,
        loadAssertionEndForm: (scope) =>
            sequenced(() => assertionEndRecovery.load(scope)),
        saveAssertionEndForm: assertionEndRecovery.save,
        loadAssertionCorrectionForm: (scope) =>
            sequenced(() => assertionCorrectionRecovery.load(scope)),
        saveAssertionCorrectionForm: assertionCorrectionRecovery.save,
        loadEventWithdrawalForm: (scope) =>
            sequenced(() => eventWithdrawalRecovery.load(scope)),
        saveEventWithdrawalForm: eventWithdrawalRecovery.save,
        loadPackForm: (scope) => sequenced(() => packRecovery.load(scope)),
        savePackForm: packRecovery.save,
        loadRecordRemovalForm: (scope) =>
            sequenced(() => recordRemovalRecovery.load(scope)),
        saveRecordRemovalForm: recordRemovalRecovery.save,
        loadBoundaryForm: (scope) =>
            sequenced(() => boundaryRecovery.load(scope)),
        saveBoundaryForm: boundaryRecovery.save,
        loadCommitmentForm: (scope) =>
            sequenced(() => commitmentRecovery.load(scope)),
        saveCommitmentForm: commitmentRecovery.save,
        loadPlanForm: (scope) => sequenced(() => planRecovery.load(scope)),
        savePlanForm: planRecovery.save,
        loadRepresentedContextForm: (scope) =>
            sequenced(() => representedContextRecovery.load(scope)),
        saveRepresentedContextForm: representedContextRecovery.save,
        loadMemoryForm: (scope) => sequenced(() => memoryRecovery.load(scope)),
        saveMemoryForm: memoryRecovery.save,
        loadSecretForm: (scope) =>
            sequenced(() => secretRecovery.load(scope)),
        saveSecretForm: secretRecovery.save,
        loadStoryTimeForm:(scope)=>sequenced(()=>storyTimeRecovery.load(scope)),
        saveStoryTimeForm:storyTimeRecovery.save,
        loadAppearanceForm: (scope) =>
            sequenced(() => appearanceRecovery.load(scope)),
        saveAppearanceForm: appearanceRecovery.save,
        loadObservationForm: (scope) =>
            sequenced(() => observationRecovery.load(scope)),
        saveObservationForm: observationRecovery.save,
        loadAttitudeForm: (scope) =>
            sequenced(() => attitudeRecovery.load(scope)),
        saveAttitudeForm: attitudeRecovery.save,
        loadPropositionForm: (scope) =>
            sequenced(() => propositionRecovery.load(scope)),
        savePropositionForm: propositionRecovery.save,
        loadCompletenessForm: (scope) =>
            sequenced(() => completenessRecovery.load(scope)),
        saveCompletenessForm: completenessRecovery.save,
        loadRuleForm: (scope) => sequenced(() => ruleRecovery.load(scope)),
        saveRuleForm: ruleRecovery.save,
        loadActionForm: (scope) => sequenced(() => actionRecovery.load(scope)),
        saveActionForm: actionRecovery.save,
        loadEventForm: (scope) => sequenced(() => eventRecovery.load(scope)),
        saveEventForm: eventRecovery.save,
        loadSourceForm: (scope) => sequenced(() => sourceRecovery.load(scope)),
        saveSourceForm: sourceRecovery.save,
        loadValueDefinitionForm: (scope) =>
            sequenced(() => valueDefinitionRecovery.load(scope)),
        saveValueDefinitionForm: valueDefinitionRecovery.save,
        loadCalendarForm: (scope) =>
            sequenced(() => calendarRecovery.load(scope)),
        saveCalendarForm: calendarRecovery.save,
        loadEntityForm: (scope) => sequenced(() => entityRecovery.load(scope)),
        saveEntityForm: entityRecovery.save,
        loadAttributeForm: (scope) =>
            sequenced(() => attributeRecovery.load(scope)),
        saveAttributeForm: attributeRecovery.save,
      );
    } on Object {
      for (final close in closeStores) {
        close();
      }
      await client.close();
      rethrow;
    }
  }
}
