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
  test('draft links preserve unsigned 64-bit versions exactly', () {
    final location = LibraryLocation(
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      context: RecordId.generate(),
      draftVersion: BigInt.parse('18446744073709551615'),
      operationIndex: 3,
    );
    final parsed = LibraryLocation.parse(location.uri);
    expect(parsed.uri, location.uri);
    expect(parsed.draftVersion, location.draftVersion);
    expect(parsed.operationIndex, 3);
    final prefix = location.uri.toString().split('/draft/').first;
    for (final suffix in [
      '-1/operation/0',
      '18446744073709551616/operation/0',
      '01/operation/0',
      '1/operation/-1',
      '1/operation/01',
      '1/operation/4294967296',
    ]) {
      expect(
        () => LibraryLocation.parse(Uri.parse('$prefix/draft/$suffix')),
        throwsFormatException,
      );
    }
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
  test('native links retain the existing exact routes without connection authority', () {
    final universe = UniverseId.generate(),
        continuity = ContinuityId.generate(),
        context = RecordId.generate();
    final locations = [
      const LibraryLocation(),
      const LibraryLocation(section: LibrarySection.settings),
      LibraryLocation(universe: universe),
      LibraryLocation(
        universe: universe,
        continuity: continuity,
        context: context,
        editor: 'source',
      ),
      LibraryLocation(
        universe: universe,
        continuity: continuity,
        context: context,
        record: RecordId.generate(),
        revision: RevisionId.generate(),
      ),
      LibraryLocation(
        universe: universe,
        continuity: continuity,
        context: context,
        draftVersion: BigInt.parse('18446744073709551615'),
        operationIndex: 3,
      ),
    ];
    for (final location in locations) {
      expect(
        location.nativeUri.toString(),
        'universe-builder://${location.uri}',
      );
      expect(location.nativeUri.authority, isEmpty);
      expect(LibraryLocation.parse(location.nativeUri).uri, location.uri);
      expect(
        LibraryLocation.parse(Uri.parse('universe-builder:${location.uri}'))
            .uri,
        location.uri,
      );
    }
  });
  test('native links reject account selection, credentials and executable requests', () {
    for (final value in [
      'universe-builder://host/library',
      'universe-builder://user:secret@/library',
      'universe-builder:///library?profile=other',
      'universe-builder:///library?endpoint=https://other',
      'universe-builder:///library#token',
      'universe-builder:library',
      'universe-builder:///publish',
      'universe-builder:///library/extra',
      'universe-builder:///universe/not-an-id',
    ]) {
      expect(
        () => LibraryLocation.parse(Uri.parse(value)),
        throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
      );
    }
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
