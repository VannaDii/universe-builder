import 'dart:io';
import 'dart:isolate';

import 'package:ub_service/embedded_engine.dart';
import 'package:ub_store/local_settings.dart';

import 'package:ub_client/local_engine.dart';
import 'package:ub_client/loopback_engine.dart';
import 'package:ub_client/editor_recovery.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_service/local_configuration.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_service/ub_service.dart'
    show PostgresConfiguration, SqliteConfiguration;
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

import 'connection.dart';
import 'local_backup_files.dart';

final class DeviceConnection {
  DeviceConnection(
    List<String> arguments, {
    this.saveBackupFile,
    this.openBackupFile,
    this.pickImagePath,
    bool? embeddedLocal,
  }) : _embeddedLocal = embeddedLocal ?? (Platform.isIOS || Platform.isAndroid) {
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      final equal = argument.indexOf('=');
      final key = equal < 0 ? argument : argument.substring(0, equal);
      if (!{'--installation', '--profile', '--engine'}.contains(key)) continue;
      final value = equal < 0
          ? (++i < arguments.length ? arguments[i] : '')
          : argument.substring(equal + 1);
      if (key == '--installation') root = value;
      if (key == '--profile') profile = value;
      if (key == '--engine') helper = value;
    }
    if (root == null && profile == null && Platform.isLinux) {
      final data = Platform.environment['XDG_DATA_HOME'];
      final home = Platform.environment['HOME'];
      if (data?.startsWith('/') == true) {
        root = '$data/universe-builder/installation';
      } else if (home?.startsWith('/') == true) {
        root = '$home/.local/share/universe-builder/installation';
      }
    }
  }
  final Future<String?> Function(String)? saveBackupFile;
  final Future<bool> Function(String)? openBackupFile;
  final Future<String?> Function()? pickImagePath;
  final bool _embeddedLocal;
  String? root, profile, helper;
  bool get supportsBrowser => false;
  String? browserEnrollmentToken;
  bool get supportsLocal => true;
  bool get available => root?.isNotEmpty == true;
  String get unavailableMessage =>
      'Open Universe Builder from a configured local installation.';
  Future<TestedPostgresConnection> testPostgres(String endpoint) async {
    if (!available) throw StateError('Local connection not configured');
    final target = await openPostgresInstallation(
      PostgresConfiguration(Credential(endpoint)),
    );
    try {
      final author = await target.transaction((session) async {
        final author = await session.authority.currentAuthor();
        final credential = ProfileCredentialStore.read(
          root: root!,
          profile: author,
        );
        final authority = PostgresServiceAuthority(session.authority);
        final principal = await authority.authenticate(
          profile: author,
          credential: Credential(credential),
        );
        await authority.requireAuthor(principal);
        return author;
      });
      return TestedPostgresConnection(
        endpoint: endpoint,
        instance: target.instanceId,
        profile: author,
      );
    } finally {
      await target.close();
    }
  }

  Future<void> savePostgres(TestedPostgresConnection choice) async {
    final current = await testPostgres(choice.endpoint);
    if (current.instance != choice.instance ||
        current.profile != choice.profile) {
      throw StateError('Selected installation changed');
    }
    await _waitForStoppedEngine();
    await saveLocalBackendConfiguration(
      root: root!,
      configuration: PostgresConfiguration(Credential(choice.endpoint)),
      expectedInstance: choice.instance,
    );
    DeviceProfileStore.write(root!, choice.profile);
    profile = choice.profile.value;
  }

  Future<TestedSqliteConnection> testSqlite() async {
    if (!available) throw StateError('Local connection not configured');
    await _waitForStoppedEngine();
    final store = SqliteInstallationStore.openExisting(root!);
    try {
      final authority = InstallationAuthority(store);
      final author = store.currentAuthor();
      final principal = authority.authenticateHello(
        EngineHello(
          protocolVersion: protocolVersion,
          profileId: author,
          credential: Credential(
            ProfileCredentialStore.read(root: root!, profile: author),
          ),
          clientName: 'universe-builder-app-setup',
        ),
      );
      authority.requireAuthor(principal);
      return TestedSqliteConnection(
        instance: store.instanceId,
        profile: author,
      );
    } finally {
      store.close();
    }
  }

  Future<void> saveSqlite(TestedSqliteConnection choice) async {
    final current = await testSqlite();
    if (current.instance != choice.instance ||
        current.profile != choice.profile) {
      throw StateError('Selected installation changed');
    }
    await saveLocalBackendConfiguration(
      root: root!,
      configuration: const SqliteConfiguration(),
      expectedInstance: choice.instance,
    );
    DeviceProfileStore.write(root!, choice.profile);
    profile = choice.profile.value;
  }

  Future<void> _waitForStoppedEngine() async {
    if (root == null || !Directory(root!).existsSync()) {
      throw StateError('Existing local installation unavailable');
    }
    // An acknowledged shutdown may still be releasing its local ownership.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      try {
        final lock = OwnedFileLock.acquire('$root/service.lock');
        lock.close();
        break;
      } on Object {
        if (DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<AppSession> connect() async {
    if (!available) throw StateError('Local connection not configured');
    EmbeddedSqliteEngine? embedded;
    late final LoopbackEngineClient client;
    if (_embeddedLocal) {
      final localRoot = root!, selectedProfile = profile;
      final selected = await Isolate.run(() async {
        LocalSettingsStore? settings;
        try {
          final path = '$localRoot/settings.sqlite';
          if (FileSystemEntity.typeSync(path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            settings = LocalSettingsStore.openExisting(path);
          }
          final configuration = await LocalBackendConfiguration.resolve(
            environment: Platform.environment,
            settings: settings,
          );
          if (configuration.usePostgres) {
            throw StateError(
              'Local mobile storage uses SQLite. Connect to PostgreSQL through a service.',
            );
          }
        } finally {
          settings?.close();
        }
        final ProfileId id;
        if (selectedProfile != null) {
          id = ProfileId.parse(selectedProfile);
        } else {
          id = SqliteInstallationStore.withBootstrap<ProfileId>(localRoot, (
            store,
          ) {
            final retained = DeviceProfileStore.read(store.root);
            if (retained != null) return retained;
            final id = store.hasProfiles
                ? store.currentAuthor()
                : InstallationAuthority(store).initializeAuthor();
            ProfileCredentialStore.read(root: store.root, profile: id);
            DeviceProfileStore.write(store.root, id);
            return id;
          });
        }
        ProfileCredentialStore.read(root: localRoot, profile: id);
        return id;
      });
      profile = selected.value;
      embedded = await EmbeddedSqliteEngine.start(localRoot);
      try {
        client = await LoopbackEngineClient.connectLocal(
          endpoint: embedded.endpoint,
          root: localRoot,
          profile: selected,
          clientName: 'universe-builder-app',
        );
      } on Object {
        await embedded.close();
        rethrow;
      }
    } else {
      final engine = helper ?? await LocalEngineClient.siblingEngine();
      if (profile == null) {
        final initialized = await Process.run(engine, [
          '--installation',
          root!,
          '--device-profile',
        ]);
        if (initialized.exitCode != 0) {
          throw StateError('Device setup unavailable');
        }
        profile = ProfileId.parse((initialized.stdout as String).trim()).value;
      }
      client = await LoopbackEngineClient.ensureRunning(
        root: root!,
        profile: ProfileId.parse(profile!),
        helper: engine,
        clientName: 'universe-builder-app',
        compatibilitySocket: false,
      );
    }
    final recovery = LocalWorldFormRecovery(root: root!, client: client);
    final typeRecovery = LocalTypeFormRecovery(root: root!, client: client);
    final propertyRecovery = LocalPropertyFormRecovery(
      root: root!,
      client: client,
    );
    final unitRecovery = LocalUnitFormRecovery(root: root!, client: client);
    final valueDefinitionRecovery = LocalValueDefinitionFormRecovery(
      root: root!,
      client: client,
    );
    final sourceRecovery = LocalSourceFormRecovery(root: root!, client: client);
    final communicationRecovery = LocalCommunicationFormRecovery(
      root: root!,
      client: client,
    );
    final itemPowerRecovery = LocalItemPowerFormRecovery(
      root: root!,
      client: client,
    );
    final issueDecisionRecovery = LocalIssueDecisionFormRecovery(
      root: root!,
      client: client,
    );
    final exceptionRecovery = LocalExceptionFormRecovery(
      root: root!,
      client: client,
    );
    final workVersionRecovery = LocalWorkVersionFormRecovery(
      root: root!,
      client: client,
    );
    final sagaRecovery = LocalSagaFormRecovery(root: root!, client: client);
    final workRecovery = LocalWorkFormRecovery(root: root!, client: client);
    final sceneRecovery = LocalSceneFormRecovery(root: root!, client: client);
    final passageRecovery = LocalPassageFormRecovery(
      root: root!,
      client: client,
    );
    final interpretationRecovery = LocalInterpretationFormRecovery(
      root: root!,
      client: client,
    );
    final assertionRetractionRecovery = LocalAssertionRetractionFormRecovery(
      root: root!,
      client: client,
    );
    final assertionEndRecovery = LocalAssertionEndFormRecovery(
      root: root!,
      client: client,
    );
    final assertionCorrectionRecovery = LocalAssertionCorrectionFormRecovery(
      root: root!,
      client: client,
    );
    final eventWithdrawalRecovery = LocalEventWithdrawalFormRecovery(
      root: root!,
      client: client,
    );
    final packRecovery = LocalPackFormRecovery(root: root!, client: client);
    final recordRemovalRecovery = LocalRecordRemovalFormRecovery(
      root: root!,
      client: client,
    );
    final boundaryRecovery = LocalBoundaryFormRecovery(
      root: root!,
      client: client,
    );
    final commitmentRecovery = LocalCommitmentFormRecovery(
      root: root!,
      client: client,
    );
    final planRecovery = LocalPlanFormRecovery(root: root!, client: client);
    final representedContextRecovery = LocalRepresentedContextFormRecovery(
      root: root!,
      client: client,
    );
    final memoryRecovery = LocalMemoryFormRecovery(root: root!, client: client);
    final secretRecovery = LocalSecretFormRecovery(
      root: root!,
      client: client,
    );
    final storyTimeRecovery = LocalStoryTimeFormRecovery(root:root!,client:client);
    final appearanceRecovery = LocalAppearanceFormRecovery(
      root: root!,
      client: client,
    );
    final observationRecovery = LocalObservationFormRecovery(
      root: root!,
      client: client,
    );
    final attitudeRecovery = LocalAttitudeFormRecovery(
      root: root!,
      client: client,
    );
    final propositionRecovery = LocalPropositionFormRecovery(
      root: root!,
      client: client,
    );
    final completenessRecovery = LocalCompletenessFormRecovery(
      root: root!,
      client: client,
    );
    final ruleRecovery = LocalRuleFormRecovery(root: root!, client: client);
    final actionRecovery = LocalActionFormRecovery(root: root!, client: client);
    final eventRecovery = LocalEventFormRecovery(root: root!, client: client);
    final relationRecovery = LocalRelationFormRecovery(
      root: root!,
      client: client,
    );
    final calendarRecovery = LocalCalendarFormRecovery(
      root: root!,
      client: client,
    );
    final entityRecovery = LocalEntityFormRecovery(root: root!, client: client);
    final attributeRecovery = LocalAttributeFormRecovery(
      root: root!,
      client: client,
    );
    // Several visible reference controls may read their labels together. The
    // native client admits one call at a time; sequence app work without retrying
    // an interrupted request or hiding its error from the caller.
    Future<void> pending = Future<void>.value();
    Future<T> sequenced<T>(Future<T> Function() action) {
      final result = pending.then((_) => action());
      pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      return result;
    }

    final files =
        Platform.isMacOS && saveBackupFile != null && openBackupFile != null
        ? LocalBackupFiles(
            root: root!,
            call: (request) => sequenced(() => client.call(request)),
            saveFile: saveBackupFile!,
            openFile: openBackupFile!,
          )
        : null;
    return AppSession(
      backupFile: files?.backup,
      restoreBackupFile: files?.restore,
      pickImage: client.welcome.author && pickImagePath != null
          ? (universe) async {
              final source = await pickImagePath!();
              if (source == null) return null;
              return StagedImage.fromWire(await sequenced(
                () => client.call(StageImageEngineRequest(universe: universe, source: source)),
              ));
            }
          : null,
      call: (request) => sequenced(() => client.call(request)),
      close: () => sequenced(() async {
        try {
          await client.close();
        } finally {
          await embedded?.close();
        }
      }),
      author: client.welcome.author,
      principal: client.welcome.principal,
      loadWorldForm: (scope) => sequenced(() => recovery.load(scope)),
      saveWorldForm: recovery.save,
      loadTypeForm: (scope) => sequenced(() => typeRecovery.load(scope)),
      saveTypeForm: typeRecovery.save,
      loadPropertyForm: (scope) =>
          sequenced(() => propertyRecovery.load(scope)),
      savePropertyForm: propertyRecovery.save,
      loadUnitForm: (scope) => sequenced(() => unitRecovery.load(scope)),
      saveUnitForm: unitRecovery.save,
      loadValueDefinitionForm: (scope) =>
          sequenced(() => valueDefinitionRecovery.load(scope)),
      saveValueDefinitionForm: valueDefinitionRecovery.save,
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
      loadPassageForm: (scope) => sequenced(() => passageRecovery.load(scope)),
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
      loadCalendarForm: (scope) =>
          sequenced(() => calendarRecovery.load(scope)),
      saveCalendarForm: calendarRecovery.save,
      loadEntityForm: (scope) => sequenced(() => entityRecovery.load(scope)),
      saveEntityForm: entityRecovery.save,
      loadAttributeForm: (scope) =>
          sequenced(() => attributeRecovery.load(scope)),
      saveAttributeForm: attributeRecovery.save,
    );
  }
}
