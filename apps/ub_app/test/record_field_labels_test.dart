import 'package:test/test.dart';
import 'package:ub_app/record_field_labels.dart';

void main() {
  test('review preserves authored keys that collide with schema labels', () {
    for (final map in [
      'metadata',
      'labels',
      'qualifiers',
      'fields',
      'unitStructure',
      'dependencies',
    ]) {
      final authored = exactChildKeysAreAuthored(map);
      expect(authored, isTrue);
      for (final key in [
        'kind',
        'selector',
        'labels',
        'fields',
        'chosen_name',
        'en_US',
        ' 記憶 😀 ',
      ]) {
        expect(exactFieldLabel(key, authoredKeys: authored), key);
        // Values are typed data, even when the author's key is "labels".
        expect(exactChildKeysAreAuthored(key, authoredKeys: authored), isFalse);
      }
    }
  });

  test(
    'schema values and validity use type rather than record-type labels',
    () {
      expect(exactFieldLabel('kind'), 'Type');
      expect(exactFieldLabel('record_kind'), 'Record type');
      expect(
        exactFieldLabel('classificationResolution'),
        'Classification status',
      );
      expect(
        exactFieldLabel('worldAssociations'),
        'World associations (not location)',
      );
    },
  );
}
