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
  if (!continuity.representedContexts.any(
    (item) => item.id == representedContext.id,
  )) {
    throw const FormatException(
      'Choose a represented context in this continuity.',
    );
  }
  final opened = Envelope<OpenedContext>.fromWire(
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
