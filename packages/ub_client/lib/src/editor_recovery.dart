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

final class LocalEntityFormRecovery {
  LocalEntityFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/entity-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedEntityForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = EntityFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedEntityForm> save(
    EditorFormScope scope,
    UnfinishedEntityForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = EntityFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalAttributeFormRecovery {
  LocalAttributeFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/attribute-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedAttributeForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = AttributeFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedAttributeForm> save(
    EditorFormScope scope,
    UnfinishedAttributeForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = AttributeFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalPropertyFormRecovery {
  LocalPropertyFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/property-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedPropertyForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = PropertyFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedPropertyForm> save(
    EditorFormScope scope,
    UnfinishedPropertyForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = PropertyFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalUnitFormRecovery {
  LocalUnitFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/unit-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedUnitForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = UnitFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedUnitForm> save(
    EditorFormScope scope,
    UnfinishedUnitForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = UnitFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalValueDefinitionFormRecovery {
  LocalValueDefinitionFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/value-definition-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedValueDefinitionForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = ValueDefinitionFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedValueDefinitionForm> save(
    EditorFormScope scope,
    UnfinishedValueDefinitionForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = ValueDefinitionFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalRelationFormRecovery {
  LocalRelationFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/relation-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedRelationForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = RelationFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedRelationForm> save(
    EditorFormScope scope,
    UnfinishedRelationForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = RelationFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalCalendarFormRecovery {
  LocalCalendarFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/calendar-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedCalendarForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = CalendarFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedCalendarForm> save(
    EditorFormScope scope,
    UnfinishedCalendarForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = CalendarFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}
