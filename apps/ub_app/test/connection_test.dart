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
        expect(DeviceConnection([]).available, isFalse);
        owner = await connection(author).connect();
        expect(owner.author, isTrue);
        expect(
          InstanceLibrary.fromWire(
            await owner.call(const StatusEngineRequest()),
          ).universes,
          isEmpty,
        );
        await owner.call(
          const CreateUniverseEngineRequest(
            name: 'A shared history',
            start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
          ),
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
        contributor = await connection(writer).connect();
        expect(contributor.author, isFalse);
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
