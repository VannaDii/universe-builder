import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

Frame sample({
  FrameTime time = const TimelessFrameTime(),
  Perspective perspective = const AuthorPerspective(),
  String? sequence,
}) => Frame(
  universe: UniverseId.parse('unv_000000000000000000000001'),
  continuity: ContinuityId.parse('cont_000000000000000000000001'),
  revision: RevisionId.parse('rev_000000000000000000000001'),
  context: RecordRef(record: RecordId.parse('rec_000000000000000000000001')),
  time: time,
  perspective: perspective,
  personalSequence: sequence,
);

void main() {
  test('perspective retains wire versus comparison encodings without granting rights', () {
    final record = RecordId.parse('rec_000000000000000000000001');
    for (final p in [
      const AuthorPerspective(),
      const ReaderPerspective(),
      CharacterPerspective(record),
      NarratorPerspective(record),
    ]) {
      expect(Perspective.fromWire(p.toWire()), p);
    }
    expect(
      CharacterPerspective(record).toWire().toText(),
      '{"character":"${record.value}"}',
    );
    expect(
      CharacterPerspective(record).toCanonical().toText(),
      '{"kind":"character","record":"${record.value}"}',
    );
    expect(
      () => Perspective.fromWire(CharacterPerspective(record).toCanonical()),
      throwsFormatException,
    );
    expect(
      () => Perspective.fromWire(
        CanonicalValue.parseJson(
          '{"character":"${record.value}","narrator":"${record.value}"}',
        ),
      ),
      throwsFormatException,
    );
  });
  test('timeless is explicit and an omitted frame time is rejected', () {
    final frame = sample();
    expect(frame.toWire().toText(), contains('"time":{"kind":"timeless"}'));
    expect(frame.toCanonical().toText(), contains('"time":"timeless"'));
    expect(
      () => Frame.fromWire(
        CanonicalObject(frame.toWire().fields.where((e) => e.key != 'time')),
      ),
      throwsFormatException,
    );
    expect(
      () => FrameTime.fromWire(CanonicalString('timeless')),
      throwsFormatException,
    );
  });
  test('event entry and exit remain distinct and require an authored side', () {
    final event = sample().context;
    final before = AtEventFrameTime(event, EventTimeSide.before);
    final after = AtEventFrameTime(event, EventTimeSide.after);
    expect(before, isNot(after));
    expect(FrameTime.fromWire(before.toWire()), before);
    expect(
      () => FrameTime.fromWire(
        CanonicalObject(before.toWire().fields.where((e) => e.key != 'side')),
      ),
      throwsFormatException,
    );
    final exact = AtFrameTime(
      ExactTime(
        CalendarId.parse('cal_000000000000000000000001'),
        '9007199254740993',
      ),
    );
    expect(
      (FrameTime.fromWire(exact.toWire()) as AtFrameTime).time,
      exact.time,
    );
  });
  test('frame pin and authored personal sequence survive decoding', () {
    final frame = sample(
      perspective: const ReaderPerspective(),
      sequence: 'experienced route',
    );
    final back = Frame.fromWire(frame.toWire());
    expect(back, frame);
    expect(back.hashCode, frame.hashCode);
    expect(back.revision.value, 'rev_000000000000000000000001');
    expect(back.personalSequence, 'experienced route');
    expect(
      () => Frame.fromWire(
        CanonicalObject([
          ...frame.toWire().fields,
          MapEntry('world', CanonicalString('wld_000000000000000000000001')),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => Frame.fromWire(
        CanonicalObject([
          ...frame.toWire().fields.where((e) => e.key != 'revision'),
          MapEntry('revision', CanonicalString(frame.continuity.value)),
        ]),
      ),
      throwsFormatException,
    );
  });
  test('null optional selectors normalize to absence without choosing a reader scene', () {
    final frame = sample();
    final back = Frame.fromWire(
      CanonicalObject([
        ...frame.toWire().fields,
        const MapEntry('readerScene', CanonicalNull()),
        const MapEntry('personalSequence', CanonicalNull()),
      ]),
    );
    expect(back, frame);
    expect(back.readerScene, isNull);
    expect(back.toWire().toText(), isNot(contains('readerScene')));
  });
}
