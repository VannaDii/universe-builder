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

final class LocalEventFormRecovery {
  LocalEventFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/event-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedEventForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = EventFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedEventForm> save(
    EditorFormScope scope,
    UnfinishedEventForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = EventFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalSourceFormRecovery {
  LocalSourceFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/source-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedSourceForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = SourceFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedSourceForm> save(
    EditorFormScope scope,
    UnfinishedSourceForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = SourceFormRecoveryStore.open(path);
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

final class LocalActionFormRecovery {
  LocalActionFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/action-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedActionForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = ActionFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedActionForm> save(
    EditorFormScope scope,
    UnfinishedActionForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = ActionFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalRuleFormRecovery {
  LocalRuleFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/rule-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedRuleForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = RuleFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedRuleForm> save(
    EditorFormScope scope,
    UnfinishedRuleForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = RuleFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalCompletenessFormRecovery {
  LocalCompletenessFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/completeness-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedCompletenessForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = CompletenessFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedCompletenessForm> save(
    EditorFormScope scope,
    UnfinishedCompletenessForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = CompletenessFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalPropositionFormRecovery {
  LocalPropositionFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/proposition-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedPropositionForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = PropositionFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedPropositionForm> save(
    EditorFormScope scope,
    UnfinishedPropositionForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = PropositionFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalAttitudeFormRecovery {
  LocalAttitudeFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/attitude-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedAttitudeForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = AttitudeFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedAttitudeForm> save(
    EditorFormScope scope,
    UnfinishedAttitudeForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = AttitudeFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalObservationFormRecovery {
  LocalObservationFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/observation-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedObservationForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = ObservationFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedObservationForm> save(
    EditorFormScope scope,
    UnfinishedObservationForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = ObservationFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalCommunicationFormRecovery {
  LocalCommunicationFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/communication-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedCommunicationForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = CommunicationFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedCommunicationForm> save(
    EditorFormScope scope,
    UnfinishedCommunicationForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = CommunicationFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalMemoryFormRecovery {
  LocalMemoryFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/memory-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedMemoryForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = MemoryFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedMemoryForm> save(
    EditorFormScope scope,
    UnfinishedMemoryForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = MemoryFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalPlanFormRecovery {
  LocalPlanFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/plan-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedPlanForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = PlanFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedPlanForm> save(
    EditorFormScope scope,
    UnfinishedPlanForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = PlanFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalCommitmentFormRecovery {
  LocalCommitmentFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/commitment-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedCommitmentForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = CommitmentFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedCommitmentForm> save(
    EditorFormScope scope,
    UnfinishedCommitmentForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = CommitmentFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalItemPowerFormRecovery {
  LocalItemPowerFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/item-power-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedItemPowerForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = ItemPowerFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedItemPowerForm> save(
    EditorFormScope scope,
    UnfinishedItemPowerForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = ItemPowerFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalRepresentedContextFormRecovery {
  LocalRepresentedContextFormRecovery({
    required String root,
    required this.client,
  }) : _path = '$root/client-recovery/represented-context-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedRepresentedContextForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = RepresentedContextFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedRepresentedContextForm> save(
    EditorFormScope scope,
    UnfinishedRepresentedContextForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = RepresentedContextFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalBoundaryFormRecovery {
  LocalBoundaryFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/boundary-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedBoundaryForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = BoundaryFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedBoundaryForm> save(
    EditorFormScope scope,
    UnfinishedBoundaryForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = BoundaryFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalIssueDecisionFormRecovery {
  LocalIssueDecisionFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/issue-decision-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedIssueDecisionForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = IssueDecisionFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedIssueDecisionForm> save(
    EditorFormScope scope,
    UnfinishedIssueDecisionForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = IssueDecisionFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalExceptionFormRecovery {
  LocalExceptionFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/exception-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedExceptionForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = ExceptionFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedExceptionForm> save(
    EditorFormScope scope,
    UnfinishedExceptionForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = ExceptionFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalWorkFormRecovery {
  LocalWorkFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/work-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedWorkForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = WorkFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedWorkForm> save(
    EditorFormScope scope,
    UnfinishedWorkForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = WorkFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalSagaFormRecovery {
  LocalSagaFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/saga-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedSagaForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = SagaFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedSagaForm> save(
    EditorFormScope scope,
    UnfinishedSagaForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = SagaFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalWorkVersionFormRecovery {
  LocalWorkVersionFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/work-version-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedWorkVersionForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = WorkVersionFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedWorkVersionForm> save(
    EditorFormScope scope,
    UnfinishedWorkVersionForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = WorkVersionFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalSceneFormRecovery {
  LocalSceneFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/scene-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedSceneForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = SceneFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedSceneForm> save(
    EditorFormScope scope,
    UnfinishedSceneForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = SceneFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalPassageFormRecovery {
  LocalPassageFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/passage-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedPassageForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = PassageFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedPassageForm> save(
    EditorFormScope scope,
    UnfinishedPassageForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = PassageFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalInterpretationFormRecovery {
  LocalInterpretationFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/interpretation-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedInterpretationForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = InterpretationFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedInterpretationForm> save(
    EditorFormScope scope,
    UnfinishedInterpretationForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = InterpretationFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalAssertionRetractionFormRecovery {
  LocalAssertionRetractionFormRecovery({
    required String root,
    required this.client,
  }) : _path = '$root/client-recovery/assertion-retraction-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedAssertionRetractionForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = AssertionRetractionFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedAssertionRetractionForm> save(
    EditorFormScope scope,
    UnfinishedAssertionRetractionForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = AssertionRetractionFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalAssertionEndFormRecovery {
  LocalAssertionEndFormRecovery({required String root, required this.client})
    : _path = '$root/client-recovery/assertion-end-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedAssertionEndForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = AssertionEndFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedAssertionEndForm> save(
    EditorFormScope scope,
    UnfinishedAssertionEndForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = AssertionEndFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}

final class LocalAssertionCorrectionFormRecovery {
  LocalAssertionCorrectionFormRecovery({
    required String root,
    required this.client,
  }) : _path = '$root/client-recovery/assertion-correction-forms.sqlite';
  final String _path;
  final LoopbackEngineClient client;

  Future<SavedAssertionCorrectionForm?> load(EditorFormScope scope) async {
    await _checkEditorScope(client, scope);
    final path = _path;
    return Isolate.run(() {
      final store = AssertionCorrectionFormRecoveryStore.open(path);
      try {
        return store.load(scope);
      } finally {
        store.close();
      }
    });
  }

  Future<SavedAssertionCorrectionForm> save(
    EditorFormScope scope,
    UnfinishedAssertionCorrectionForm form,
    BigInt expectedGeneration,
  ) async {
    if (scope.profile != client.welcome.principal) {
      throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
    }
    final path = _path;
    return Isolate.run(() {
      final store = AssertionCorrectionFormRecoveryStore.open(path);
      try {
        return store.save(scope, form, expectedGeneration);
      } finally {
        store.close();
      }
    });
  }
}
