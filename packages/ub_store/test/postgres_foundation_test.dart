@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  final available = port != null && port > 0 && port <= 65535;
  group(
    'real PostgreSQL foundation',
    () {
      late Connection connection;
      late String first, second, role;
      setUp(() async {
        connection = await Connection.open(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: 'postgres',
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        first = postgresUniverseSchema(UniverseId.generate());
        second = postgresUniverseSchema(UniverseId.generate());
        role = 'ub_fixture_${UniverseId.generate().value}';
        await connection.execute(
          'CREATE ROLE "$role" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE',
        );
        await connection.execute(
          'GRANT CREATE ON DATABASE ub_disposable TO "$role"',
        );
        await connection.execute('SET ROLE "$role"');
        for (final schema in [first, second]) {
          await connection.execute('CREATE SCHEMA $schema');
          await connection.execute(
            'CREATE TABLE $schema.exact_fixture('
            'row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, '
            'authored_text BYTEA NOT NULL, exact_amount TEXT NOT NULL, '
            'exact_u64 TEXT NOT NULL, optional_text BYTEA, '
            'selector_key TEXT COLLATE "C" NOT NULL UNIQUE)',
          );
        }
      });
      tearDown(() async {
        try {
          await connection.execute('RESET ROLE');
          for (final schema in [first, second]) {
            await connection.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
          }
          await connection.execute('DROP OWNED BY "$role"');
          await connection.execute('DROP ROLE "$role"');
        } finally {
          await connection.close();
        }
      });

      test('non-superuser namespace setup and exact typed values round trip', () async {
        const text = '\uFEFF\uFEFFcafé e\u0301 😀\u0000\r\n';
        const amount = '1.00000000000000000000000000001';
        const unsigned = '18446744073709551615';
        final result = await connection.execute(
          Sql.named(
            'INSERT INTO $first.exact_fixture(authored_text,exact_amount,exact_u64,optional_text,selector_key) '
            'VALUES(@text,@amount,@unsigned,NULL,@key) RETURNING row_id',
          ),
          parameters: {
            'text': TypedValue(Type.byteArray, postgresAuthoredText(text)),
            'amount': amount,
            'unsigned': unsigned,
            'key': 'shared selector',
          },
        );
        expect(result.single.single, 1);
        final row = (await connection.execute(
          'SELECT authored_text,exact_amount,exact_u64,optional_text FROM $first.exact_fixture',
        )).single;
        expect(readPostgresAuthoredText(row[0] as Uint8List), text);
        expect(row[1], amount);
        expect(row[2], unsigned);
        expect(row[3], isNull);
        await connection.execute(
          Sql.named(
            'INSERT INTO $second.exact_fixture(authored_text,exact_amount,exact_u64,optional_text,selector_key) '
            'VALUES(@text,@amount,@unsigned,@empty,@key)',
          ),
          parameters: {
            'text': TypedValue(
              Type.byteArray,
              postgresAuthoredText('Other universe'),
            ),
            'amount': amount,
            'unsigned': unsigned,
            'empty': TypedValue(Type.byteArray, postgresAuthoredText('')),
            'key': 'shared selector',
          },
        );
        expect(
          (await connection.execute(
                'SELECT optional_text FROM $second.exact_fixture',
              )).single.single
              as Uint8List,
          isEmpty,
        );
        expect(
          (await connection.execute(
            'SELECT rolsuper FROM pg_roles WHERE rolname=current_user',
          )).single.single,
          isFalse,
        );
      });

      test('transaction rollback and locked competing writes preserve one owner', () async {
        await expectLater(
          connection.runTx((tx) async {
            await tx.execute(
              'CREATE TABLE $first.rollback_fixture(id BIGINT PRIMARY KEY)',
            );
            await tx.execute('INSERT INTO $first.rollback_fixture VALUES(1)');
            throw StateError('Disposable interrupted transaction');
          }),
          throwsStateError,
        );
        expect(
          (await connection.execute(
            Sql.named('SELECT to_regclass(@name)::text'),
            parameters: {
              'name':
                  '${first.substring(1, first.length - 1)}.rollback_fixture',
            },
          )).single.single,
          isNull,
        );
        await connection.execute(
          'CREATE TABLE $first.lock_fixture(id BIGINT PRIMARY KEY, generation BIGINT NOT NULL)',
        );
        await connection.execute('INSERT INTO $first.lock_fixture VALUES(1,0)');
        final contender = await Connection.open(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: role,
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        try {
          await connection.runTx((tx) async {
            await tx.execute(
              'SELECT generation FROM $first.lock_fixture WHERE id=1 FOR UPDATE',
            );
            await expectLater(
              contender.runTx((other) async {
                await other.execute("SET LOCAL lock_timeout='100ms'");
                await other.execute(
                  'UPDATE $first.lock_fixture SET generation=1 WHERE id=1',
                );
              }),
              throwsA(
                isA<ServerException>().having((e) => e.code, 'code', '55P03'),
              ),
            );
            await tx.execute(
              'UPDATE $first.lock_fixture SET generation=1 WHERE id=1',
            );
          });
          expect(
            (await contender.execute(
              'UPDATE $first.lock_fixture SET generation=2 WHERE id=1 AND generation=0',
            )).affectedRows,
            0,
          );
          expect(
            (await contender.execute(
              'SELECT generation FROM $first.lock_fixture WHERE id=1',
            )).single.single,
            1,
          );
        } finally {
          await contender.close();
        }
      });
      test('pooled reuse does not carry transaction-local universe namespace', () async {
        final pool = Pool<void>.withEndpoints(
          [
            Endpoint(
              host: '127.0.0.1',
              port: port!,
              database: 'ub_disposable',
              username: role,
            ),
          ],
          settings: const PoolSettings(
            maxConnectionCount: 1,
            sslMode: SslMode.disable,
          ),
        );
        try {
          final baseline = (await pool.execute('SHOW search_path'))
              .single
              .single;
          Object? pid;
          for (final schema in [first, second]) {
            await pool.runTx((tx) async {
              final current = (await tx.execute('SELECT pg_backend_pid()'))
                  .single
                  .single;
              pid ??= current;
              expect(current, pid);
              await tx.execute('SET LOCAL search_path TO $schema');
              expect(
                (await tx.execute('SELECT current_schema()')).single.single,
                schema.substring(1, schema.length - 1),
              );
              await tx.execute(
                Sql.named(
                  'INSERT INTO $schema.exact_fixture(authored_text,exact_amount,exact_u64,selector_key) '
                  'VALUES(@text,@amount,@integer,@key)',
                ),
                parameters: {
                  'text': TypedValue(
                    Type.byteArray,
                    postgresAuthoredText(schema),
                  ),
                  'amount': '0.000000000000000001',
                  'integer': '18446744073709551615',
                  'key': 'same normalized selector',
                },
              );
            });
            expect(
              (await pool.execute('SHOW search_path')).single.single,
              baseline,
            );
          }
          for (final schema in [first, second]) {
            final rows = await pool.execute(
              'SELECT authored_text FROM $schema.exact_fixture',
            );
            expect(rows.length, 1);
            expect(
              readPostgresAuthoredText(rows.single.single as Uint8List),
              schema,
            );
          }
          await expectLater(
            pool.runTx((tx) async {
              await tx.execute('SET LOCAL search_path TO $first');
              throw StateError('Interrupted checkout');
            }),
            throwsStateError,
          );
          expect(
            (await pool.execute('SHOW search_path')).single.single,
            baseline,
          );
        } finally {
          await pool.close();
        }
      });
    },
    skip: available ? false : 'Set UB_TEST_POSTGRES_PORT for the disposable local ub_disposable database.',
  );

  test(
    'authored text codec refuses invalid Unicode and retains exact bytes',
    () {
      expect(
        () => postgresAuthoredText(String.fromCharCode(0xd800)),
        throwsFormatException,
      );
      expect(() => readPostgresAuthoredText([0xff]), throwsFormatException);
      expect(
        readPostgresAuthoredText(postgresAuthoredText('\uFEFF\u0000😀')),
        '\uFEFF\u0000😀',
      );
    },
  );
}
