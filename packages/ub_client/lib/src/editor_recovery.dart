import 'dart:isolate';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

import 'loopback_engine.dart';

Future<void> _checkEditorScope(
  LoopbackEngineClient client,
  EditorFormScope scope,
) async {
  if (scope.profile != client.welcome.principal) {
    throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
  }
  final status = await client.call(const StatusEngineRequest());
  final fields = Map.fromEntries((status as CanonicalObject).fields);
  if (wireString(fields['instance_id']!) != scope.instance.value) {
    throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
  }
  String? name;
  for (final row in (fields['universes']! as CanonicalArray).items) {
    final entry = WireFields(row, {'id', 'name'});
    if (entry.string('id') == scope.universe.value) {
      name = entry.string('name');
    }
  }
  if (name == null) {
    throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
  }
  final description = Envelope<Description>.fromWire(
    await client.call(
      ToolEngineRequest(
        request: DescribeSummaryRequest(universe: Selector(name)),
      ),
    ),
    Description.fromWire,
  );
  if (!description.result.continuities.any(
    (entry) =>
        entry.id == scope.continuity &&
        (scope.representedContext == null ||
            entry.representedContexts.any(
              (context) => context.id == scope.representedContext,
            )),
  )) {
    throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
  }
}

final class LocalWorldFormRecovery {
  LocalWorldFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/world-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedWorldForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = WorldFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedWorldForm> save(
    EditorFormScope scope,
    UnfinishedWorldForm form,
    BigInt expectedGeneration,
  ) async {
    // Pending input remains recoverable through a dropped connection. Opening
    // it rechecks live access; this local write grants no service authority.
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = WorldFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalTypeFormRecovery {
  LocalTypeFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/type-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedTypeForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = TypeFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedTypeForm> save(
    EditorFormScope scope,
    UnfinishedTypeForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = TypeFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}
