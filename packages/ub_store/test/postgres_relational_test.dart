@TestOn('vm')
library;

import 'required_evidence_fixture.dart';

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/catalog.dart';
import 'package:ub_store/src/postgres_relational.dart';
import 'package:ub_store/src/postgres_schema.dart';
import 'package:ub_store/src/postgres_values.dart';

void main() {
  final port = int.tryParse(
    Platform.environment['UB_TEST_POSTGRES_PORT'] ?? '',
  );
  group(
    'PostgreSQL normative typed bodies',
    () {
      late Connection connection;
      late UniverseId universe;
      late String schema;
      late String role;
      setUpAll(() async {
        connection = await Connection.open(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: 'postgres',
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        universe = UniverseId.generate();
        schema = postgresUniverseSchema(universe);
        role = 'ub_fixture_${UniverseId.generate().value}';
        await connection.execute(
          'CREATE ROLE "$role" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE',
        );
        await connection.runTx((tx) async {
          // Other live suites also edit this database's fixture-role ACL.
          await tx.execute(
            "SELECT pg_advisory_xact_lock(hashtext('ub_disposable_fixture_roles'))",
          );
          await tx.execute('GRANT CREATE ON DATABASE ub_disposable TO "$role"');
        });
        await connection.execute('SET ROLE "$role"');
        await connection.runTx((tx) async {
          await tx.execute('CREATE SCHEMA $schema');
          for (final statement in postgresBodySchema(universe)) {
            await tx.execute(statement);
          }
        });
      });
      tearDownAll(() async {
        // The restart case reconnects as the restricted fixture role. Cleanup
        // uses a fresh administrator session rather than relying on RESET ROLE.
        await connection.close();
        final administrator = await Connection.open(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: 'postgres',
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        try {
          await administrator.execute('DROP SCHEMA IF EXISTS $schema CASCADE');
          await administrator.runTx((tx) async {
            await tx.execute(
              "SELECT pg_advisory_xact_lock(hashtext('ub_disposable_fixture_roles'))",
            );
            await tx.execute('DROP OWNED BY "$role"');
            await tx.execute('DROP ROLE "$role"');
          });
        } finally {
          await administrator.close();
        }
      });

      test(
        'complete typed schema provisions without superuser and rolls back',
        () async {
          expect(
            (await connection.execute(
              'SELECT rolsuper FROM pg_roles WHERE rolname=current_user',
            )).single.single,
            isFalse,
          );
          expect(
            (await connection.execute(
              'SELECT count(*) FROM pg_tables WHERE schemaname=\$1',
              parameters: [schema.substring(1, schema.length - 1)],
            )).single.single,
            905,
          );
          final interrupted = UniverseId.generate();
          final namespace = postgresUniverseSchema(interrupted);
          await expectLater(
            connection.runTx((tx) async {
              await tx.execute('CREATE SCHEMA $namespace');
              for (final statement in postgresBodySchema(interrupted)) {
                await tx.execute(statement);
              }
              await PostgresRelationalCodec(tx, interrupted).put(
                'Value',
                CanonicalValue.parseJson(
                  '{"kind":"text","text":"unpublished"}',
                ),
              );
              throw StateError('Interrupted provision');
            }),
            throwsStateError,
          );
          expect(
            (await connection.execute(
              'SELECT count(*) FROM pg_namespace WHERE nspname=\$1',
              parameters: [namespace.substring(1, namespace.length - 1)],
            )).single.single,
            0,
          );
        },
      );

      test('policy source membership retains exact operation bytes on a new connection', () async {
        final sources = [RecordId.generate(), RecordId.generate()];
        final values = [
          for (final members in [<RecordId>[], sources])
            DefineUniversePolicyOperation(
              clientRef: RecordId.generate().value,
              key: 'Memoir 記憶',
              realWorld: true,
              activate: true,
              sourceCategoryMembers: members,
            ).toWire(),
        ];
        final pointers = await connection.runTx((tx) async {
          final codec = PostgresRelationalCodec(tx, universe);
          return [
            for (final value in values)
              await codec.put('DomainOperation', value),
          ];
        });
        await connection.close();
        connection = await Connection.open(
          Endpoint(
            host: '127.0.0.1',
            port: port!,
            database: 'ub_disposable',
            username: role,
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        await connection.runTx((tx) async {
          final codec = PostgresRelationalCodec(tx, universe);
          for (var i = 0; i < values.length; i++) {
            final restored = await codec.get('DomainOperation', pointers[i]);
            expect(restored.toText(), values[i].toText());
            expect(
              DomainOperation.fromWire(restored).toWire().toText(),
              values[i].toText(),
            );
          }
        });
      });

      test(
        'all frozen payloads survive a new connection with unchanged digests',
        () async {
          const root = '../../docs/decisions/relational-storage';
          final cases = (CanonicalValue.parseJson(
            File('$root/canonical-oracle.json').readAsStringSync(),
          ) as CanonicalArray).items.map(objectFields).toList();
          final semantic = objectFields(
            CanonicalValue.parseJson(
              File('$root/semantic-oracle.json').readAsStringSync(),
            ),
          );
          for (final value in (semantic['versions'] as CanonicalArray).items) {
            final item = objectFields(value);
            cases.add({
              'value': item['value']!,
              'canonical': CanonicalString(item['value']!.toText()),
              'digest': item['digest']!,
            });
          }
          for (final review in [false, true]) {
            final payload = requiredEvidencePayload(universe, review: review);
            cases.add({
              'value': payload,
              'canonical': CanonicalString(payload.toText()),
              'digest': CanonicalString(payloadDigest('rule', payload)),
            });
          }
          final event = sourcedEventPayload(universe);
          for (final marked in [false, true]) {
            final payload = fictionalDeparturePayload(universe, marked);
            cases.add({
              'value': payload,
              'canonical': CanonicalString(payload.toText()),
              'digest': CanonicalString(payloadDigest('exception', payload)),
            });
          }
          cases.add({
            'value': event,
            'canonical': CanonicalString(event.toText()),
            'digest': CanonicalString(payloadDigest('event', event)),
          });
          final pointers = await connection.runTx((tx) async {
            final codec = PostgresRelationalCodec(tx, universe);
            return [
              for (final item in cases)
                await codec.put('Payload', item['value']!),
            ];
          });
          await connection.close();
          connection = await Connection.open(
            Endpoint(
              host: '127.0.0.1',
              port: port!,
              database: 'ub_disposable',
              username: role,
            ),
            settings: const ConnectionSettings(sslMode: SslMode.disable),
          );
          final reading = Stopwatch()..start();
          await connection.runTx((tx) async {
            final codec = PostgresRelationalCodec(tx, universe);
            for (var i = 0; i < cases.length; i++) {
              final value = await codec.get('Payload', pointers[i]);
              expect(
                value.toText(),
                (cases[i]['canonical'] as CanonicalString).value,
              );
              final kind =
                  (objectFields(value)['record_kind'] as CanonicalString).value;
              expect(
                payloadDigest(kind, value),
                (cases[i]['digest'] as CanonicalString).value,
              );
            }
          });
          stdout.writeln(
            'PostgreSQL: read and verify ${cases.length} frozen payloads '
            '${reading.elapsedMilliseconds} ms',
          );
          await connection.close();
          connection = await Connection.open(
            Endpoint(
              host: '127.0.0.1',
              port: port,
              database: 'ub_disposable',
              username: role,
            ),
            settings: const ConnectionSettings(sslMode: SslMode.disable),
          );
          final batched = Stopwatch()..start();
          await connection.runTx((tx) async {
            final codec = PostgresRelationalCodec(tx, universe);
            for (var offset = 0; offset < pointers.length; offset += 50) {
              final end = offset + 50 < pointers.length
                  ? offset + 50
                  : pointers.length;
              final values = await codec.getMany(
                'Payload',
                pointers.sublist(offset, end),
              );
              for (var i = offset; i < end; i++) {
                final value = values[i - offset];
                expect(
                  value.toText(),
                  (cases[i]['canonical'] as CanonicalString).value,
                );
                final kind =
                    (objectFields(value)['record_kind'] as CanonicalString)
                        .value;
                expect(
                  payloadDigest(kind, value),
                  (cases[i]['digest'] as CanonicalString).value,
                );
              }
            }
            final repeated = await codec.getMany('Payload', [
              pointers.last,
              pointers.first,
              pointers.last,
            ]);
            expect(repeated.map((v) => v.toText()), [
              (cases.last['canonical'] as CanonicalString).value,
              (cases.first['canonical'] as CanonicalString).value,
              (cases.last['canonical'] as CanonicalString).value,
            ]);
          });
          stdout.writeln(
            'PostgreSQL: batch read and verify ${cases.length} frozen payloads '
            'plus repeated roots ${batched.elapsedMilliseconds} ms',
          );
          final writing = Stopwatch()..start();
          final written = await connection.runTx((tx) async {
            final codec = PostgresRelationalCodec(tx, universe);
            final result = <Object?>[];
            for (var offset = 0; offset < cases.length; offset += 50) {
              final end = (offset + 50).clamp(0, cases.length);
              result.addAll(
                await codec.putMany('Payload', [
                  for (final item in cases.getRange(offset, end))
                    item['value']!,
                ]),
              );
            }
            return result;
          });
          stdout.writeln(
            'PostgreSQL: batch write ${cases.length} frozen payloads '
            '${writing.elapsedMilliseconds} ms',
          );
          expect(written.toSet().intersection(pointers.toSet()), isEmpty);
          await connection.close();
          connection = await Connection.open(
            Endpoint(
              host: '127.0.0.1',
              port: port,
              database: 'ub_disposable',
              username: role,
            ),
            settings: const ConnectionSettings(sslMode: SslMode.disable),
          );
          await connection.runTx((tx) async {
            final codec = PostgresRelationalCodec(tx, universe);
            for (var i = 0; i < written.length; i++) {
              final value = await codec.get('Payload', written[i]);
              expect(
                value.toText(),
                (cases[i]['canonical'] as CanonicalString).value,
              );
              final kind =
                  (objectFields(value)['record_kind'] as CanonicalString).value;
              expect(
                payloadDigest(kind, value),
                (cases[i]['digest'] as CanonicalString).value,
              );
            }
          });
        },
      );

      test('absence, explicit null, exact amounts, NUL map keys and ordered repeats survive', () async {
        await connection.runTx((tx) async {
          final codec = PostgresRelationalCodec(tx, universe);
          for (final text in [
            '{"record":"rec_000000000000000000000001"}',
            '{"record":"rec_000000000000000000000001","universe":null}',
          ]) {
            final value = CanonicalValue.parseJson(text);
            expect(
              (await codec.get(
                'RecordRef',
                await codec.put('RecordRef', value),
              )).toText(),
              value.toText(),
            );
          }
          for (final text in [
            '{"kind":"integer","digits":"+0007"}',
            '{"kind":"decimal","digits":"30.00"}',
            '{"kind":"rational","numerator":"0007","denominator":"03"}',
            '{"kind":"text","text":"\\ufeffcafé 😀\\u0000\\r\\n"}',
            '{"kind":"sequence","items":[{"kind":"text","text":"β"},{"kind":"text","text":"🌲"},{"kind":"text","text":"β"}]}',
            '{"kind":"structured","definition":"vdef_000000000000000000000001","fields":{"\\u0000é":{"kind":"decimal","digits":"0.00"},"é":{"kind":"integer","digits":"9007199254740993"}}}',
          ]) {
            final value = CanonicalValue.parseJson(text);
            expect(
              (await codec.get(
                'Value',
                await codec.put('Value', value),
              )).toText(),
              value.toText(),
            );
          }
          final scalar = BodyCatalog.instance.models.entries
              .firstWhere(
                (e) =>
                    e.value.kind == 'integer' &&
                    e.value.minimum == null &&
                    e.value.maximum == null,
              )
              .key;
          for (final text in ['18446744073709551615', '-9223372036854775808']) {
            final value = CanonicalValue.parseJson(text);
            expect(
              (await codec.get(
                scalar,
                await codec.put(scalar, value),
              )).toText(),
              text,
            );
          }
        });
      });

      test(
        'rollback removes partial bodies; immutable rows refuse mutation',
        () async {
          final before = (await connection.execute(
            'SELECT count(*) FROM $schema.r_value',
          )).single.single;
          await expectLater(
            connection.runTx((tx) async {
              final codec = PostgresRelationalCodec(tx, universe);
              await codec.put(
                'Value',
                CanonicalValue.parseJson('{"kind":"integer","digits":"7"}'),
              );
              await codec.put(
                'Value',
                CanonicalValue.parseJson('{"kind":"integer","digits":7}'),
              );
            }),
            throwsFormatException,
          );
          expect(
            (await connection.execute('SELECT count(*) FROM $schema.r_value'))
                .single
                .single,
            before,
          );
          final row = await connection.runTx(
            (tx) => PostgresRelationalCodec(tx, universe).put(
              'Value',
              CanonicalValue.parseJson('{"kind":"integer","digits":"7"}'),
            ),
          );
          for (final statement in [
            'UPDATE $schema.r_value SET variant=0 WHERE __row_id=\$1',
            'DELETE FROM $schema.r_value WHERE __row_id=\$1',
          ]) {
            await expectLater(
              connection.execute(statement, parameters: [row]),
              throwsA(
                isA<ServerException>().having((e) => e.code, 'code', '55000'),
              ),
            );
          }
        },
      );

      test('foreign keys, ordinal gaps and recursive graphs are rejected', () async {
        await expectLater(
          connection.runTx(
            (tx) => tx.execute(
              'INSERT INTO $schema.r_value(variant,v13) VALUES(13,999999)',
            ),
          ),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23503'),
          ),
        );
        for (final cycle in [false, true]) {
          await expectLater(
            connection.runTx((tx) async {
              final codec = PostgresRelationalCodec(tx, universe);
              final root = await codec.put(
                'Value',
                CanonicalValue.parseJson('{"kind":"sequence","items":[]}'),
              );
              final variant = (await tx.execute(
                'SELECT v13 FROM $schema.r_value WHERE __row_id=\$1',
                parameters: [root],
              )).single.single;
              final owner = (await tx.execute(
                'SELECT items FROM $schema.r_value_v13 WHERE __row_id=\$1',
                parameters: [variant],
              )).single.single;
              final child = cycle
                  ? root
                  : await codec.put(
                      'Value',
                      CanonicalValue.parseJson('{"kind":"text","text":"one"}'),
                    );
              await tx.execute(
                'INSERT INTO $schema.r_value_v13_items_items(owner,ordinal,item) VALUES(\$1,\$2,\$3)',
                parameters: [owner, cycle ? 0 : 1, child],
              );
              await expectLater(
                codec.get('Value', root),
                throwsFormatException,
              );
              await expectLater(
                codec.getMany('Value', [root]),
                throwsFormatException,
              );
              throw StateError('Discard malformed fixture');
            }),
            throwsStateError,
          );
        }
      });
      test(
        'batch limits and missing roots preserve subsequent reads',
        () async {
          await connection.runTx((tx) async {
            final codec = PostgresRelationalCodec(tx, universe);
            expect(await codec.getMany('Value', []), isEmpty);
            await expectLater(
              codec.getMany('Value', List.filled(51, 1)),
              throwsRangeError,
            );
            await expectLater(
              codec.getMany('Value', [-1]),
              throwsFormatException,
            );
            final value = CanonicalValue.parseJson(
              '{"kind":"text","text":"\\ufeff\\ufeffé\\u0000😀"}',
            );
            final root = await codec.put('Value', value);
            expect(
              (await codec.getMany('Value', [
                root,
                root,
              ])).map((v) => v.toText()),
              [value.toText(), value.toText()],
            );
          });
        },
      );
      test('broad valid bodies fall back without becoming an admission limit', () async {
        final value = CanonicalValue.parseJson(
          '{"kind":"sequence","items":['
          '${List.filled(6000, '{"kind":"integer","digits":"+0007"}').join(',')}'
          ']}',
        );
        await connection.runTx((tx) async {
          final codec = PostgresRelationalCodec(tx, universe);
          final root = (await codec.putMany('Value', [value])).single;
          expect((await codec.get('Value', root)).toText(), value.toText());
          expect(
            (await codec.getMany('Value', [root])).single.toText(),
            value.toText(),
          );
        });
      }, timeout: const Timeout(Duration(minutes: 2)));
      test('batch writes reject invalid input before writing and roll back interruption', () async {
        final value = CanonicalValue.parseJson(
          '{"kind":"text","text":"記憶\\u0000😀"}',
        );
        Future<int> count() async =>
            (await connection.execute('SELECT count(*) FROM $schema.r_value'))
                    .single
                    .single
                as int;
        final before = await count();
        await connection.runTx((tx) async {
          final codec = PostgresRelationalCodec(tx, universe);
          expect(await codec.putMany('Value', []), isEmpty);
          await expectLater(
            codec.putMany('Value', List.filled(51, value)),
            throwsRangeError,
          );
          await expectLater(
            codec.putMany('Value', [value, const CanonicalBool(true)]),
            throwsFormatException,
          );
        });
        expect(await count(), before);
        await expectLater(
          connection.runTx((tx) async {
            final codec = PostgresRelationalCodec(tx, universe);
            final pointers = await codec.putMany('Value', [value, value]);
            expect(pointers.toSet(), hasLength(2));
            expect(
              (await codec.get('Value', pointers.first)).toText(),
              value.toText(),
            );
            throw StateError('Interrupted batch');
          }),
          throwsStateError,
        );
        expect(await count(), before);
      });
    },
    skip: port == null
        ? 'Set UB_TEST_POSTGRES_PORT for the disposable local ub_disposable database.'
        : false,
  );
}
