import 'package:ub_contracts/ub_contracts.dart';

import 'navigation_location.dart';

/// An index belongs to one saved draft version, never to whichever row now
/// occupies that position after another edit, removal or reorder.
SavedDraft draftForLocation(SavedDraft? draft, LibraryLocation location) {
  final index = location.operationIndex;
  if (draft == null ||
      draft.version != location.draftVersion ||
      draft.content.representedContext != location.context ||
      draft.content.proposal != null ||
      index == null ||
      index < 0 ||
      index >= draft.content.operations.length) {
    throw const FormatException(
      'This saved draft link is outdated or unavailable. Open Changes to choose the current operation.',
    );
  }
  return draft;
}
