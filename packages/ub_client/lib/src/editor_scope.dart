import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

/// Opening private input rechecks the connected installation and current access.
Future<void> checkEditorRecoveryScope({
  required ProfileId principal,
  required Future<CanonicalValue> Function(EngineRequest) call,
  required EditorFormScope scope,
}) async {
  if (scope.profile != principal) {
    throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
  }
  final status = await call(const StatusEngineRequest());
  final fields = Map.fromEntries((status as CanonicalObject).fields);
  if (wireString(fields['instance_id']!) != scope.instance.value) {
    throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
  }
  String? name;
  for (final row in (fields['universes']! as CanonicalArray).items) {
    final entry = WireFields(row, {'id', 'name'});
    if (entry.string('id') == scope.universe.value) name = entry.string('name');
  }
  if (name == null) {
    throw const NotFoundOrNotAccessibleError(message: 'editor recovery');
  }
  final description = Envelope<Description>.fromWire(
    await call(
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
