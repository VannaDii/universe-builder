@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/local_engine.dart';
import 'package:ub_service/local_profiles.dart';
import 'package:ub_store/installation.dart';
import 'package:ub_store/profile_credentials.dart';

import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/universe_creation.dart';

void main() {
  test(
    'app connects to the existing engine and reads only its accessible library',
    () async {
      final root = Directory('/tmp').createTempSync('ub-app-');
      final store = SqliteInstallationStore.create(root.path);
      final authority = InstallationAuthority(store);
      final author = authority.initializeAuthor();
      final writer = authority.enroll(
        authority.authenticateHello(
          EngineHello(
            protocolVersion: protocolVersion,
            profileId: author,
            credential: Credential(
              ProfileCredentialStore.read(root: root.path, profile: author),
            ),
            clientName: 'Disposable app setup',
          ),
        ),
      );
      store.close();
      final server = await LocalSqliteEngineServer.start(
        root.path,
        compatibilitySocket: false,
      );
      AppSession? owner, contributor;
      DeviceConnection connection(ProfileId profile) => DeviceConnection([
        '--installation=${root.path}',
        '--profile',
        profile.value,
        '--engine=/nonexistent/universe-engine',
      ]);
      try {
        expect(DeviceConnection(['--installation=']).available, isFalse);
        owner = await connection(author).connect();
        expect(owner.author, isTrue);
        expect(
          InstanceLibrary.fromWire(
            await owner.call(const StatusEngineRequest()),
          ).universes,
          isEmpty,
        );
        await owner.call(
          const UniverseCreationForm(
            name: 'A shared history',
            calendar: CreationCalendar.gregorian,
            date: '2040-01-01',
            time: '00:00:00',
            offset: '+05:30',
          ).request(),
        );
        final catalog = InstanceLibrary.fromWire(
          await owner.call(const StatusEngineRequest()),
        );
        expect(catalog.universes.single.name, 'A shared history');
        final description = Envelope<Description>.fromWire(
          await owner.call(
            ToolEngineRequest(
              request: DescribeSummaryRequest(
                universe: Selector('A shared history'),
              ),
            ),
          ),
          Description.fromWire,
        );
        expect(description.result.continuities, isNotEmpty);
        final continuity = description.result.continuities.single;
        final scope = EditorFormScope(
          instance: catalog.instance,
          profile: owner.principal,
          universe: catalog.universes.single.id,
          continuity: continuity.id,
        );
        final unfinished = UnfinishedWorldForm(
          baseRevision: continuity.revisionId,
          representedContext: continuity.representedContexts.single.id,
          record: RecordId.generate(),
          selector: '',
          settingType: 'Still deciding',
          rationale: 'Source notes 😀\r\n',
        );
        final saved = await owner.saveWorldForm(scope, unfinished, BigInt.zero);
        expect(saved.generation, BigInt.one);
        await owner.close();
        owner = await connection(author).connect();
        final recovered = await owner.loadWorldForm(scope);
        expect(recovered!.form.toWire().toText(), unfinished.toWire().toText());
        expect(
          (await owner.saveWorldForm(
            scope,
            unfinished,
            BigInt.zero,
          )).generation,
          BigInt.one,
        );
        await owner.close();
        expect(
          (await owner.saveWorldForm(scope, unfinished, BigInt.one)).generation,
          BigInt.two,
        );
        owner = await connection(author).connect();
        expect((await owner.loadWorldForm(scope))!.generation, BigInt.two);
        final afterRecovery = Envelope<Description>.fromWire(
          await owner.call(
            ToolEngineRequest(
              request: DescribeSummaryRequest(
                universe: Selector('A shared history'),
              ),
            ),
          ),
          Description.fromWire,
        );
        expect(afterRecovery.result.worlds, isEmpty);
        expect(
          afterRecovery.result.continuities.single.revisionId,
          continuity.revisionId,
        );
        final fictional = createdUniverse(
          await owner.call(
            const UniverseCreationForm(
              name: 'Before the first age',
              calendar: CreationCalendar.fictional,
              calendarName: 'Ages',
              initialTick: '-123456789012345678901234567890',
              tickLabel: 'beat',
            ).request(),
          ),
        );
        expect(fictional.name, 'Before the first age');
        expect(
          InstanceLibrary.fromWire(
            await owner.call(const StatusEngineRequest()),
          ).universes.map((row) => row.id),
          contains(fictional.id),
        );
        contributor = await connection(writer).connect();
        expect(contributor.author, isFalse);
        await expectLater(
          contributor.loadWorldForm(scope),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          contributor.loadWorldForm(
            EditorFormScope(
              instance: scope.instance,
              profile: contributor.principal,
              universe: scope.universe,
              continuity: scope.continuity,
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          owner.loadWorldForm(
            EditorFormScope(
              instance: OperationId.generate(),
              profile: scope.profile,
              universe: scope.universe,
              continuity: scope.continuity,
            ),
          ),
          throwsA(isA<NotFoundOrNotAccessibleError>()),
        );
        await expectLater(
          contributor.call(
            const UniverseCreationForm(
              name: 'Not permitted',
              calendar: CreationCalendar.gregorian,
              date: '2040-01-01',
              time: '00:00:00',
              offset: 'Z',
            ).request(),
          ),
          throwsA(isA<ProtocolError>()),
        );
        expect(
          InstanceLibrary.fromWire(
            await contributor.call(const StatusEngineRequest()),
          ).universes,
          isEmpty,
        );
      } finally {
        await contributor?.close();
        await owner?.close();
        await server.close();
        root.deleteSync(recursive: true);
      }
    },
  );
}
