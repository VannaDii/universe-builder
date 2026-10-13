import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

RepresentedContextSummary? selectedRepresentedContext(
  ContinuitySummary continuity,
  RecordId? preferred,
) {
  for (final context in continuity.representedContexts) {
    if (context.id == preferred) return context;
  }
  return continuity.representedContexts.length == 1
      ? continuity.representedContexts.single
      : null;
}

String representedContextName(RepresentedContextSummary context) {
  final english = context.labels['en'];
  if (english != null && english.isNotEmpty) return english;
  for (final label in context.labels.values) {
    if (label.isNotEmpty) return label;
  }
  return 'Unnamed context';
}

/// Every world read uses the chosen context at this continuity's exact head.
Future<Envelope<Description>> readContextWorlds({
  required AppSession session,
  required LibraryEntry universe,
  required ContinuitySummary continuity,
  required RepresentedContextSummary representedContext,
}) async {
  final opened = await openAuthorReadContext(
    session,
    universe,
    continuity,
    representedContext,
  );
  return Envelope<Description>.fromWire(
    await session.call(
      ToolEngineRequest(
        request: DescribeWorldsRequest(
          universe: Selector(universe.name),
          universeId: universe.id,
          contextId: opened.contextId,
        ),
      ),
    ),
    Description.fromWire,
  );
}

Future<OpenedContext> openAuthorReadContext(
  AppSession session,
  LibraryEntry universe,
  ContinuitySummary continuity,
  RepresentedContextSummary representedContext,
) async {
  if (!continuity.representedContexts.any(
    (item) => item.id == representedContext.id,
  )) {
    throw const FormatException(
      'Choose a represented context in this continuity.',
    );
  }
  return Envelope<OpenedContext>.fromWire(
    await session.call(
      ToolEngineRequest(
        request: OpenContextRequest(
          universe: Selector(universe.name),
          universeId: universe.id,
          continuityId: continuity.id,
          revision: ExactRevisionSelector(revisionId: continuity.revisionId),
          representedContext: ContextIdSelector(representedContext.id),
          temporalQuery: const TimelessFrameTime(),
          temporalSystems: [],
          perspective: const AuthorPerspective(),
        ),
      ),
    ),
    OpenedContext.fromWire,
  ).result;
}

Future<RecordVersion> readPublishedWorld({
  required AppSession session,
  required LibraryEntry universe,
  required ContinuitySummary continuity,
  required RepresentedContextSummary representedContext,
  required WorldSummary world,
}) async {
  final opened = await openAuthorReadContext(
    session,
    universe,
    continuity,
    representedContext,
  );
  final recordId = RecordId.parse(
    '${RecordId.prefix}${world.id.value.substring(WorldId.prefix.length)}',
  );
  final read = Envelope<Records>.fromWire(
    await session.call(
      ToolEngineRequest(
        request: GetRequest(
          universe: Selector(universe.name),
          universeId: universe.id,
          contextId: opened.contextId,
          recordIds: [recordId],
          fieldGroups: [FieldGroup.payload],
        ),
      ),
    ),
    Records.fromWire,
  );
  if (!read.delivery.complete ||
      read.result.records.length != 1 ||
      read.result.records.single.identity.recordId != recordId ||
      read.result.records.single.payload is! WorldRecord) {
    throw const FormatException(
      'This world is not available as a complete record in the selected context.',
    );
  }
  return read.result.records.single;
}
