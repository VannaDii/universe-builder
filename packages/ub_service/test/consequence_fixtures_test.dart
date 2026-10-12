@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_service/consequence_execution.dart';

import 'operation_compilation_test.dart' as f;

Object? clone(Object? value) => jsonDecode(jsonEncode(value));
void applyMutation(Object? root, Map<String, dynamic> mutation) {
  final path = (mutation['path'] as String).split('.');
  var node = root;
  for (final key in path.take(path.length - 1)) {
    node = switch (node) {
      List<dynamic> list => list[int.parse(key)],
      Map<String, dynamic> map => map[key],
      _ => throw StateError('Invalid fixture path'),
    };
  }
  final key = path.last;
  if (node is Map<String, dynamic>) {
    if (mutation['value'] == null) {
      node.remove(key);
    } else {
      node[key] = mutation['value'];
    }
  } else {
    (node as List<dynamic>)[int.parse(key)] = mutation['value'];
  }
}

List<RecordVersion> rowsFrom(List<dynamic> payloads) => [
  for (var i = 0; i < payloads.length; i++)
    f.row(
      i + 1,
      RecordPayload.fromWire(
        CanonicalValue.parseWireJson(jsonEncode(payloads[i])),
      ),
    ),
];
final frame = Frame(
  universe: f.u,
  continuity: ContinuityId.parse('cont_${f.suffix(1)}'),
  revision: f.revision,
  context: f.ref(10),
  time: const TimelessFrameTime(),
  perspective: const AuthorPerspective(),
);

void main() {
  for (final name in [
    'action-effects/expected.json',
    'resource-transitions/expected.json',
    'resource-transitions/cumulative.json',
  ]) {
    final fixture = jsonDecode(
      File('../../fixtures/$name').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final raw in fixture['cases'] as List<dynamic>) {
      final c = raw as Map<String, dynamic>;
      test('$name: ${c['id']}', () {
        final payloads =
            clone(c['records'] ?? fixture['records']) as List<dynamic>;
        for (final mutation in (c['mutations'] as List<dynamic>?) ?? []) {
          final m = mutation as Map<String, dynamic>;
          applyMutation(payloads[(m['record'] as int) - 1], m);
        }
        payloads.addAll((c['extraRecords'] as List<dynamic>?) ?? []);
        final rows = rowsFrom(payloads);
        final changed = c['changed'] is List<dynamic>
            ? (c['changed'] as List<dynamic>).map((n) => f.id(n as int)).toSet()
            : rows.map((r) => r.identity.recordId).toSet();
        List<String>? exclusions;
        Object? failure;
        try {
          if (c['expand'] == true) {
            final expanded = expandEvents(rows);
            var n = 1000;
            for (final entry in expanded.entries) {
              rows.add(
                RecordVersion.build(
                  recordVersionId: f.ver(n++),
                  identity: RecordIdentity(
                    universeId: f.u,
                    recordId: entry.key,
                    recordKind: RecordKind.assertion,
                  ),
                  payload: entry.value,
                ),
              );
            }
          }
          exclusions = validateActionConsequences(
            records: rows,
            base: [],
            changed: changed,
            frame: frame,
          );
        } catch (e) {
          failure = e;
        }
        expect(failure == null, c['allowed'], reason: '$failure');
        if (c['id'] == 'historical_contractless') {
          expect(exclusions, hasLength(1));
        }
      });
    }
  }
}
