import 'dart:collection';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_service/ub_service.dart';

const endpoint =
    'postgresql://test_user:disposable_secret@localhost/test_database';
Matcher failure(ConfigurationFailure code) => throwsA(
  isA<ConfigurationException>().having(
    (e) => e.failure,
    'safe failure code',
    code,
  ),
);

final class EndpointProbe extends MapBase<String, String> {
  EndpointProbe(this.entriesMap);
  final Map<String, String> entriesMap;
  int endpointReads = 0;
  @override
  String? operator [](Object? key) {
    if (key == 'UB_POSTGRES_ENDPOINT') endpointReads++;
    return entriesMap[key];
  }

  @override
  void operator []=(String key, String value) => entriesMap[key] = value;
  @override
  Iterable<String> get keys => entriesMap.keys;
  @override
  void clear() => entriesMap.clear();
  @override
  String? remove(Object? key) => entriesMap.remove(key);
}

void main() {
  test('default and explicit SQLite selection avoid environment and saved endpoint access', () async {
    for (final settings in [
      <String, String>{},
      {'UB_POSTGRES_ENDPOINT': 'malformed disposable secret'},
      {
        'UB_USE_POSTGRES': ' FALSE ',
        'UB_POSTGRES_ENDPOINT': 'malformed disposable secret',
      },
    ]) {
      final environment = EndpointProbe(settings);
      var savedReads = 0;
      final selected = await BackendConfiguration.resolve(
        environment: environment,
        savedUsePostgres: settings.containsKey('UB_USE_POSTGRES'),
        readSavedEndpoint: () async {
          savedReads++;
          throw StateError('key unavailable');
        },
      );
      expect(selected, isA<SqliteConfiguration>());
      expect(selected.usePostgres, isFalse);
      expect(environment.endpointReads, 0);
      expect(savedReads, 0);
    }
  });
  test('literal boolean normalization accepts only true and false', () async {
    for (final value in ['true', 'TRUE', ' TrUe\n']) {
      final selected = await BackendConfiguration.resolve(
        environment: {
          'UB_USE_POSTGRES': value,
          'UB_POSTGRES_ENDPOINT': endpoint,
        },
      );
      expect(selected.usePostgres, isTrue);
    }
    for (final value in ['false', 'FALSE', ' FaLsE\n']) {
      expect(
        (await BackendConfiguration.resolve(
          environment: {'UB_USE_POSTGRES': value},
          savedUsePostgres: true,
        )).usePostgres,
        isFalse,
      );
    }
    for (final value in ['', ' ', '1', '0', 'yes', 'no', 'tru', 'true false']) {
      await expectLater(
        BackendConfiguration.resolve(
          environment: {
            'UB_USE_POSTGRES': value,
            'UB_POSTGRES_ENDPOINT': endpoint,
          },
        ),
        failure(ConfigurationFailure.invalidBackendFlag),
      );
    }
  });
  test('environment backend and endpoint override saved values independently without saving', () async {
    var savedReads = 0;
    final selected = await BackendConfiguration.resolve(
      environment: {
        'UB_USE_POSTGRES': 'true',
        'UB_POSTGRES_ENDPOINT': endpoint,
      },
      savedUsePostgres: false,
      readSavedEndpoint: () async {
        savedReads++;
        return const Credential('saved disposable secret');
      },
    ) as PostgresConfiguration;
    expect(selected.endpoint.expose(), endpoint);
    expect(savedReads, 0);
    final savedSelection = await BackendConfiguration.resolve(
      environment: {'UB_POSTGRES_ENDPOINT': endpoint},
      savedUsePostgres: true,
      readSavedEndpoint: () async {
        savedReads++;
        return const Credential('saved disposable secret');
      },
    ) as PostgresConfiguration;
    expect(savedSelection.endpoint.expose(), endpoint);
    expect(savedReads, 0);
  });
  test(
    'saved endpoint is unlocked only when selected and not overridden',
    () async {
      var savedReads = 0;
      final selected = await BackendConfiguration.resolve(
        environment: {'UB_USE_POSTGRES': 'true'},
        savedUsePostgres: false,
        readSavedEndpoint: () async {
          savedReads++;
          return const Credential(endpoint);
        },
      ) as PostgresConfiguration;
      expect(selected.endpoint.expose(), endpoint);
      expect(savedReads, 1);
      final saved = await BackendConfiguration.resolve(
        environment: {},
        savedUsePostgres: true,
        readSavedEndpoint: () async {
          savedReads++;
          return const Credential(endpoint);
        },
      ) as PostgresConfiguration;
      expect(saved.endpoint.expose(), endpoint);
      expect(savedReads, 2);
    },
  );
  test(
    'explicit empty endpoint never falls back to saved credentials or SQLite',
    () async {
      for (final value in ['', ' \n']) {
        var savedReads = 0;
        await expectLater(
          BackendConfiguration.resolve(
            environment: {
              'UB_USE_POSTGRES': 'true',
              'UB_POSTGRES_ENDPOINT': value,
            },
            readSavedEndpoint: () async {
              savedReads++;
              return const Credential(endpoint);
            },
          ),
          failure(ConfigurationFailure.missingPostgresEndpoint),
        );
        expect(savedReads, 0);
      }
      await expectLater(
        BackendConfiguration.resolve(environment: {'UB_USE_POSTGRES': 'true'}),
        failure(ConfigurationFailure.missingPostgresEndpoint),
      );
      await expectLater(
        BackendConfiguration.resolve(
          environment: {},
          savedUsePostgres: true,
          readSavedEndpoint: () async => null,
        ),
        failure(ConfigurationFailure.missingPostgresEndpoint),
      );
    },
  );
  test(
    'saved decryption failure is redacted and cannot select a fallback',
    () async {
      try {
        await BackendConfiguration.resolve(
          environment: {},
          savedUsePostgres: true,
          readSavedEndpoint: () async =>
              throw StateError('key unavailable for $endpoint'),
        );
        fail('Expected saved endpoint failure');
      } on ConfigurationException catch (error) {
        expect(error.failure, ConfigurationFailure.savedEndpointUnavailable);
        expect('$error', isNot(contains('disposable_secret')));
        expect('$error', isNot(contains('test_user')));
        expect('$error', isNot(contains('localhost')));
        expect(error.message, contains('could not be unlocked'));
      }
    },
  );
  test('resolved PostgreSQL diagnostics redact exact credentials without altering their bytes', () async {
    const exact =
        'postgresql://test_user:p%40ss@localhost/db?password=disposable_query_secret';
    final selected = await BackendConfiguration.resolve(
      environment: {'UB_USE_POSTGRES': 'true', 'UB_POSTGRES_ENDPOINT': exact},
    ) as PostgresConfiguration;
    expect(selected.endpoint.expose(), exact);
    expect('$selected', 'PostgresConfiguration(endpoint: [redacted])');
    expect('${selected.endpoint}', '[redacted]');
    expect('$selected', isNot(contains('disposable_query_secret')));
    expect('$selected', isNot(contains('p%40ss')));
  });
}
