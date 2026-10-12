import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_service/ub_service.dart';

PostgresConnectionOptions parse(String value, {bool local = false}) =>
    PostgresConnectionOptions.parse(
      Credential(value),
      allowLoopbackDevelopment: local,
    );
Matcher failure(ConfigurationFailure code) => throwsA(
  isA<ConfigurationException>().having(
    (e) => e.failure,
    'safe failure code',
    code,
  ),
);
void main() {
  test('URI credentials database and IPv6 preserve decoded values without splitting encoded separators', () {
    final p = parse(
      'postgresql://writer%3Aname:p%40ss%3Aword%2F%25@[::1]:5544/Campaign%20%C3%A9',
    );
    expect(p.host, '::1');
    expect(p.port, 5544);
    expect(p.username, 'writer:name');
    expect(p.password!.expose(), 'p@ss:word/%');
    expect(p.database, 'Campaign é');
    expect(p.tlsMode, PostgresTlsMode.verifyFull);
    expect(
      parse('postgres://host.example/Campaign%2Fone').database,
      'Campaign/one',
    );
    expect(parse('POSTGRESQL://host.example/database').port, 5432);
    expect(parse('postgres://host.example/database').username, isNull);
    expect(parse('postgres://host.example/database').password, isNull);
  });
  test('query credentials database and port overrides are explicit and preserve exact input scalar', () {
    const raw =
        'postgres://old:old@host.example:5433/old?user=writer&password=p%40ss%2Bword&dbname=Campaign+one&port=5544';
    final selected = PostgresConfiguration(const Credential(raw));
    expect(selected.endpoint.expose(), raw);
    expect(selected.connection.username, 'writer');
    expect(selected.connection.password!.expose(), 'p@ss+word');
    expect(selected.connection.database, 'Campaign one');
    expect(selected.connection.port, 5544);
    expect(
      parse('postgres://host.example?database=Campaign&username=writer')
          .database,
      'Campaign',
    );
  });
  test('verified TLS is default and unverified modes require explicit literal loopback development', () {
    for (final host in ['host.example', 'localhost', '127.0.0.1', '[::1]']) {
      expect(parse('postgres://$host/db').tlsMode, PostgresTlsMode.verifyFull);
      for (final mode in ['disable', 'require']) {
        expect(
          () => parse('postgres://$host/db?sslmode=$mode'),
          failure(ConfigurationFailure.unverifiedTls),
        );
      }
    }
    for (final host in ['localhost', '127.0.0.1', '127.1.2.3', '[::1]']) {
      expect(
        parse('postgres://$host/db?sslmode=disable', local: true).tlsMode,
        PostgresTlsMode.disable,
      );
      expect(
        parse('postgres://$host/db?sslmode=require', local: true).tlsMode,
        PostgresTlsMode.require,
      );
    }
    for (final host in [
      'remote.example',
      '127.0.0.999',
      'localhost.example',
      '[::2]',
    ]) {
      expect(
        () => parse('postgres://$host/db?sslmode=disable', local: true),
        failure(ConfigurationFailure.unverifiedTls),
      );
    }
  });
  test('TLS modes are never silently approximated and certificate options remain explicit', () {
    for (final mode in ['allow', 'prefer', 'verify-ca', 'unknown', '']) {
      expect(
        () => parse('postgres://localhost/db?sslmode=$mode', local: true),
        failure(ConfigurationFailure.unsupportedConnectionOption),
      );
    }
    final p = parse(
      'postgres://host.example/db?sslmode=verify-full&sslrootcert=%2Fprivate%20certs%2Froot.pem&sslcert=%2Fcert.pem&sslkey=%2Fkey.pem',
    );
    expect(p.rootCertificate, '/private certs/root.pem');
    expect(p.clientCertificate, '/cert.pem');
    expect(p.clientKey, '/key.pem');
    for (final params in [
      'sslcert=/cert.pem',
      'sslkey=/key.pem',
      'sslrootcert=',
      'sslmode=disable&sslrootcert=/root.pem',
      'sslmode=require&sslrootcert=/root.pem',
      'sslmode=disable&sslcert=/cert.pem&sslkey=/key.pem',
    ]) {
      expect(
        () => parse('postgres://localhost/db?$params', local: true),
        failure(ConfigurationFailure.unsupportedConnectionOption),
      );
    }
  });
  test('application name and connect timeout retain supplied values with bounded integer parsing', () {
    final p = parse(
      'postgres://host.example/db?application_name=Universe+Builder&connect_timeout=30',
    );
    expect(p.applicationName, 'Universe Builder');
    expect(p.connectTimeout, const Duration(seconds: 30));
    expect(
      parse('postgres://host.example/db?connect_timeout=2147483647')
          .connectTimeout,
      const Duration(seconds: 2147483647),
    );
    for (final seconds in [
      '0',
      '-1',
      '1.0',
      '1e2',
      '2147483648',
      'not_a_number',
    ]) {
      expect(
        () => parse('postgres://host.example/db?connect_timeout=$seconds'),
        failure(ConfigurationFailure.invalidEndpoint),
      );
    }
    for (final port in ['0', '-1', '1.0', '65536', 'text']) {
      expect(
        () => parse('postgres://host.example/db?port=$port'),
        failure(ConfigurationFailure.invalidEndpoint),
      );
    }
    expect(
      () => parse('postgres://host.example:65536/db'),
      failure(ConfigurationFailure.invalidEndpoint),
    );
    expect(
      () => parse('postgres://host.example:/db'),
      failure(ConfigurationFailure.invalidEndpoint),
    );
  });
  test('unsupported and duplicate options fail instead of being ignored or guessed', () {
    for (final params in [
      'password=a&password=b',
      'sslmode=verify-full&sslmode=verify-full',
      'user=a&username=b',
      'dbname=a&database=b',
    ]) {
      expect(
        () => parse('postgres://host.example/db?$params'),
        failure(ConfigurationFailure.invalidEndpoint),
      );
    }
    for (final params in [
      'options=-csearch_path%3Dpublic',
      'host=other.example',
      'replication=true',
      'client_encoding=LATIN1',
      'secret_option=disposable_secret',
    ]) {
      expect(
        () => parse('postgres://host.example/db?$params'),
        failure(ConfigurationFailure.unsupportedConnectionOption),
      );
    }
  });
  test('malformed locators escapes and missing database cannot acquire implicit defaults', () {
    for (final uri in [
      'http://host.example/db',
      'postgres://',
      'postgres:///db',
      'postgres://host.example',
      'postgres://host.example/',
      'postgres://a.example,b.example/db',
      'postgres://host.example/a/b',
      'postgres://host.example/db#fragment',
      'postgres://writer:p@ss@host.example/db',
      'postgres://writer:p%ZZ@host.example/db',
      'postgres://writer:p%FF@host.example/db',
      ' postgres://host.example/db',
      'postgres://host.example/db ',
      'postgres://host.example/db?password=a%00b',
      'postgres://host.example/db?password=a%0Ab',
    ]) {
      expect(
        () => parse(uri),
        failure(ConfigurationFailure.invalidEndpoint),
        reason: 'malformed disposable endpoint',
      );
    }
  });
  test('all endpoint failures and parsed diagnostics redact userinfo query secrets and locators', () {
    const secret = 'disposable_secret';
    for (final raw in [
      'postgres://writer:$secret@host.example/db?unexpected=$secret',
      'postgres://writer:$secret@host.example/db?sslmode=disable',
      'postgres://writer:$secret@host.example/db?password=%FF',
    ]) {
      try {
        parse(raw);
        fail('Expected redacted failure');
      } on ConfigurationException catch (error) {
        expect('$error', isNot(contains(secret)));
        expect('$error', isNot(contains('writer')));
        expect('$error', isNot(contains('host.example')));
        expect('$error', isNot(contains('%FF')));
      }
    }
    expect(
      '${parse('postgres://writer:$secret@host.example/db')}',
      'PostgresConnectionOptions([redacted])',
    );
  });
  test('shared resolver validates only selected PostgreSQL without fallback and threads explicit loopback intent', () async {
    var savedReads = 0;
    final sqlite = await BackendConfiguration.resolve(
      environment: {
        'UB_USE_POSTGRES': 'false',
        'UB_POSTGRES_ENDPOINT': 'malformed disposable secret',
      },
      readSavedEndpoint: () async {
        savedReads++;
        return const Credential('malformed');
      },
    );
    expect(sqlite, isA<SqliteConfiguration>());
    expect(savedReads, 0);
    await expectLater(
      BackendConfiguration.resolve(
        environment: {
          'UB_USE_POSTGRES': 'true',
          'UB_POSTGRES_ENDPOINT': 'malformed',
        },
        readSavedEndpoint: () async {
          savedReads++;
          return const Credential('postgres://localhost/db');
        },
      ),
      failure(ConfigurationFailure.invalidEndpoint),
    );
    expect(savedReads, 0);
    await expectLater(
      BackendConfiguration.resolve(
        environment: {},
        savedUsePostgres: true,
        readSavedEndpoint: () async => const Credential('malformed'),
      ),
      failure(ConfigurationFailure.invalidEndpoint),
    );
    final development = await BackendConfiguration.resolve(
      environment: {
        'UB_USE_POSTGRES': 'true',
        'UB_POSTGRES_ENDPOINT': 'postgres://localhost/db?sslmode=disable',
      },
      allowLoopbackDevelopment: true,
    ) as PostgresConfiguration;
    expect(development.connection.tlsMode, PostgresTlsMode.disable);
  });
}
