import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  const body = '000000000000000000000001';
  final universe = UniverseId.parse('unv_$body');
  final record = RecordId.parse('rec_$body');
  test('typed IDs preserve original bodies and reject other families', () {
    expect(RecordId.parse('rec_$body'), record);
    expect(universe, isNot(record));
    for (final invalid in [
      'wld_$body',
      'rec_00000001',
      'rec_${body}0',
      'rec_00000000000000000000000A',
      'rec_00000000000000000000000é',
      'rec_$body\n',
    ]) {
      expect(() => RecordId.parse(invalid), throwsFormatException);
    }
  });
  test('new identities use secure 96-bit lowercase bodies', () {
    final first = RecordId.generate();
    final second = RecordId.generate();
    expect(first.value, matches(r'^rec_[0-9a-f]{24}$'));
    expect(first, isNot(second));
  });
  test('all definition reference mappings retain record identity', () {
    expect(CalendarId.fromRecordId(record).toRecordId(), record);
    expect(UnitId.fromRecordId(record).toRecordId(), record);
    expect(ValueDefinitionId.fromRecordId(record).toRecordId(), record);
    expect(PropositionId.fromRecordId(record).toRecordId(), record);
    expect(RuleId.fromRecordId(record).toRecordId(), record);
    expect(ExceptionId.fromRecordId(record).toRecordId(), record);
    expect(AnchorId.fromRecordId(record).toRecordId(), record);
  });
  test('wire namespace resolves explicitly and cannot cross universes', () {
    final local = RecordRef.fromCanonical(
      CanonicalValue.parseJson('{"record":"rec_$body"}'),
    );
    expect(local.toCanonical().toText(), '{"record":"rec_$body"}');
    expect(
      local.resolveNamespace(universe),
      RecordRef(universe: universe, record: record),
    );
    expect(
      local.resolveNamespace(universe).toCanonical().toText(),
      '{"record":"rec_$body","universe":"unv_$body"}',
    );
    expect(
      () => local
          .resolveNamespace(universe)
          .resolveNamespace(UniverseId.parse('unv_000000000000000000000002')),
      throwsFormatException,
    );
  });
  test('closed reference input rejects unknown fields and wrong ID types', () {
    for (final text in [
      '{"record":"ver_$body"}',
      '{"record":"rec_$body","version":"ver_$body"}',
      '{"record":null}',
      '{}',
    ]) {
      expect(
        () => RecordRef.fromCanonical(CanonicalValue.parseJson(text)),
        throwsFormatException,
      );
    }
    final version = VersionRef.fromCanonical(
      CanonicalValue.parseJson('{"record":"rec_$body","version":"ver_$body"}'),
    );
    expect(
      version.toCanonical().toText(),
      '{"record":"rec_$body","version":"ver_$body"}',
    );
    expect(
      () => VersionRef.fromCanonical(
        CanonicalValue.parseJson('{"record":"rec_$body"}'),
      ),
      throwsFormatException,
    );
    expect(
      LocalRef('new-character').toCanonical().toText(),
      '{"clientRef":"new-character"}',
    );
  });
}
