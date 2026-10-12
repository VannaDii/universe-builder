import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/context_binding.dart';

import 'proposal_state_test.dart' as proposals;
import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as frames;
import 'proposal_authorization_test.dart' as permissions;

void main() {
  test(
    'retained context admits only the exact owner and scope before expiry',
    () {
      final stored = StoredContext(
        owner: proposals.actor,
        scope: 'exact-scope',
        expires: BigInt.from(10),
        frame: frames.frame(),
      );
      final decoded = StoredContext.fromWire(stored.toWire());
      Frame admit(ProfileId owner, String scope, int now) => decoded.admit(
        principal: owner,
        scopeHash: scope,
        universe: f.u,
        epochSeconds: BigInt.from(now),
      );
      expect(
        admit(proposals.actor, 'exact-scope', 10).toWire().toText(),
        stored.frame.toWire().toText(),
      );
      expect(
        () => admit(proposals.actor, 'exact-scope', 11),
        throwsA(isA<ContextExpiredError>()),
      );
      expect(
        () => admit(proposals.other, 'exact-scope', 11),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(
        () => admit(proposals.actor, 'changed-scope', 9),
        throwsA(isA<NotFoundOrNotAccessibleError>()),
      );
      expect(
        () => StoredContext(
          owner: proposals.actor,
          scope: '',
          expires: BigInt.one << 64,
          frame: frames.frame(),
        ),
        throwsFormatException,
      );
    },
  );

  test('world focus resolves visible normalized aliases and exact guards', () {
    final records = [
      f.row(1, WorldRecord(selector: 'Campaign', aliases: ['Shared Realm'])),
      f.row(2, WorldRecord(selector: 'Hidden World')),
    ];
    WorldId? resolve(String? name, {WorldId? guard}) => resolveWorldFocus(
      world: name == null ? null : Selector(name),
      guard: guard,
      records: records,
      scope: {permissions.world(1)},
    );
    expect(resolve(' shared realm '), permissions.world(1));
    expect(
      resolve('Campaign', guard: permissions.world(1)),
      permissions.world(1),
    );
    expect(resolve(null, guard: permissions.world(2)), isNull);
    expect(
      () => resolve('Hidden World'),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
    expect(
      () => resolve('Campaign', guard: permissions.world(2)),
      throwsA(isA<WorldScopeConflictError>()),
    );
    final duplicate = [
      ...records,
      f.row(3, WorldRecord(selector: 'Other', aliases: ['Campaign'])),
    ];
    expect(
      () => resolveWorldFocus(
        world: const Selector('Campaign'),
        guard: null,
        records: duplicate,
        scope: null,
      ),
      throwsA(isA<NotFoundOrNotAccessibleError>()),
    );
  });
}
