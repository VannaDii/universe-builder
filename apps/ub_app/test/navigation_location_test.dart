import 'package:test/test.dart';
import 'package:ub_app/navigation_location.dart';
import 'package:ub_app/record_edit_action.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('root links preserve page and exact universe identity without names or secrets', () {
    for (final section in LibrarySection.values) {
      final location = LibraryLocation(section: section);
      expect(LibraryLocation.parse(location.uri).section, section);
      expect(location.uri.query, isEmpty);
    }
    final id = UniverseId.generate();
    final location = LibraryLocation(universe: id);
    expect(LibraryLocation.parse(location.uri).universe, id);
    expect(
      LibraryLocation.parse(Uri(path: '/')).section,
      LibrarySection.library,
    );
  });
  test('editor links preserve exact scope and reject unknown capabilities', () {
    final universe = UniverseId.generate(),
        continuity = ContinuityId.generate(),
        context = RecordId.generate();
    for (final editor in LibraryLocation.editors) {
      final location = LibraryLocation(
        universe: universe,
        continuity: continuity,
        context: context,
        editor: editor,
      );
      final parsed = LibraryLocation.parse(location.uri);
      expect(parsed.universe, universe);
      expect(parsed.continuity, continuity);
      expect(parsed.context, context);
      expect(parsed.editor, editor);
    }
    expect(
      () => LibraryLocation.parse(
        Uri(
          path:
              '/universe/${universe.value}/continuity/${continuity.value}/context/${context.value}/editor/execute',
        ),
      ),
      throwsFormatException,
    );
  });
  test('record links retain the opened revision and scoped identity', () {
    final location = LibraryLocation(
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      context: RecordId.generate(),
      revision: RevisionId.generate(),
      record: RecordId.generate(),
    );
    final parsed = LibraryLocation.parse(location.uri);
    expect(parsed.uri, location.uri);
    expect(parsed.revision, location.revision);
    expect(parsed.record, location.record);
    expect(parsed.context, location.context);
    expect(parsed.editor, isNull);
    expect(
      () => LibraryLocation.parse(
        Uri.parse(location.uri.toString().replaceFirst('/revision/', '/head/')),
      ),
      throwsFormatException,
    );
  });
  test('record action links retain the revision and reject unrecognized operations', () {
    final universe = UniverseId.generate(),
        continuity = ContinuityId.generate(),
        context = RecordId.generate(),
        record = RecordId.generate(),
        revision = RevisionId.generate();
    for (final action in RecordEditAction.values) {
      final location = LibraryLocation(
        universe: universe,
        continuity: continuity,
        context: context,
        record: record,
        revision: revision,
        recordAction: action,
      );
      final parsed = LibraryLocation.parse(location.uri);
      expect(parsed.uri, location.uri);
      expect(parsed.recordAction, action);
      expect(parsed.record, record);
      expect(parsed.revision, revision);
      expect(
        () => LibraryLocation.parse(Uri.parse('${location.uri}/extra')),
        throwsFormatException,
      );
    }
    final path = LibraryLocation(
      universe: universe,
      continuity: continuity,
      context: context,
      record: record,
      revision: revision,
    ).uri;
    expect(
      () => LibraryLocation.parse(Uri.parse('$path/edit/publish')),
      throwsFormatException,
    );
    expect(
      () => LibraryLocation.parse(
        Uri.parse('$path/edit/recordRemoval?approve=true'),
      ),
      throwsFormatException,
    );
  });
  test('unrecognized paths, credentials, queries and invalid identities are rejected', () {
    for (final path in [
      '/universe/not-an-id',
      '/universe',
      '/library/extra',
      '/private',
      '/library?credential=secret',
      '/library#secret',
      'https://user:secret@example.com/library',
      'file:/library',
    ]) {
      expect(
        () => LibraryLocation.parse(Uri.parse(path)),
        throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
      );
    }
  });
}
