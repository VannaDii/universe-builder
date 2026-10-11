import 'package:test/test.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  CanonicalValue wire(String text) => CanonicalValue.parseJson(text);
  final universe = UniverseId.parse('unv_000000000000000000000001');
  final world = WorldId.parse('wld_000000000000000000000001');
  final calendar = CalendarId.parse('cal_000000000000000000000001');
  final context = RecordRef(
    universe: universe,
    record: RecordId.parse('rec_000000000000000000000001'),
  );
  final version = VersionRef(
    universe: universe,
    record: context.record,
    version: RecordVersionId.parse('ver_000000000000000000000001'),
  );
  test('all applicability forms retain identity, order and separate wire encodings', () {
    final forms = <Applicability>[
      const UniverseApplicability(),
      WorldsApplicability([world]),
      const ConditionalApplicability(),
      const UnspecifiedApplicability(),
      WorldsApplicability([]),
    ];
    expect(forms.toSet(), hasLength(5));
    for (final form in forms) {
      expect(Applicability.fromWire(form.toWire()), form);
    }
    final worlds = WorldsApplicability([world, world]);
    expect(worlds.toWire().toText(), contains('"world_ids"'));
    expect(worlds.toCanonical().toText(), contains('"worldIds"'));
    expect(worlds.worldIds, hasLength(2));
    expect(() => worlds.worldIds.clear(), throwsUnsupportedError);
    expect(
      () => Applicability.fromWire(worlds.toCanonical()),
      throwsFormatException,
    );
    expect(
      () =>
          Applicability.fromWire(wire('{"kind":"unspecified","world_ids":[]}')),
      throwsFormatException,
    );
  });
  test('scope requires explicit context and applicability while optional realm normalizes null', () {
    final scope = Scope(
      applicability: WorldsApplicability([world]),
      context: context,
    );
    expect(Scope.fromWire(scope.toWire()), scope);
    final fields = (scope.toWire()).fields;
    final explicitNull = CanonicalObject([
      ...fields,
      const MapEntry('realm', CanonicalNull()),
    ]);
    expect(Scope.fromWire(explicitNull), scope);
    expect(scope.toWire().toText(), isNot(contains('"realm"')));
    expect(scope.toCanonical().toText(), contains('"worldIds"'));
    expect(
      () => Scope.fromWire(wire('{"applicability":{"kind":"universe_wide"}}')),
      throwsFormatException,
    );
    expect(
      () => Scope.fromWire(
        wire('{"context":{"record":"${context.record.value}"}}'),
      ),
      throwsFormatException,
    );
  });
  test('validity keeps unknown, unspecified and infinity distinct without inferred clocks', () {
    final unknown = IntervalValidity(
      const UnknownBound(),
      const ExactBound('E20'),
    );
    final infinite = IntervalValidity(
      const UnboundedBound(),
      const ExactBound('E20'),
    );
    expect(unknown, isNot(infinite));
    expect(const UnknownValidity(), isNot(const UnspecifiedValidity()));
    final forms = <Validity>[
      const UnknownValidity(),
      const UnspecifiedValidity(),
      const ConditionalValidity(),
      InstantValidity(ExactTime(calendar, 'E12')),
      unknown,
      infinite,
      CalendarIntervalValidity(
        calendar,
        const ExactBound('E12'),
        const ExactBound('E20'),
      ),
      const PersistentValidity(UnknownBound()),
    ];
    for (final form in forms) {
      expect(Validity.fromWire(form.toWire()), form);
      expect(form.toCanonical().toText(), form.toWire().toText());
    }
    expect(unknown.asInterval(), (
      const UnknownBound(),
      const ExactBound('E20'),
    ));
    expect(const PersistentValidity(UnknownBound()).asInterval(), (
      const UnknownBound(),
      const UnboundedBound(),
    ));
    expect(const UnknownValidity().asInterval(), isNull);
    expect(const ConditionalValidity().isTemporal, isFalse);
    expect(unknown.isTemporal, isTrue);
  });
  test('instant interval projection accepts only exact or authored degenerate intervals', () {
    expect(InstantValidity(ExactTime(calendar, '10')).asInterval(), (
      const ExactBound('10'),
      const ExactBound('10'),
    ));
    expect(
      InstantValidity(
        IntervalTime(calendar, const ExactBound('10'), const ExactBound('10')),
      ).asInterval(),
      (const ExactBound('10'), const ExactBound('10')),
    );
    expect(
      InstantValidity(
        IntervalTime(calendar, const ExactBound('10'), const ExactBound('11')),
      ).asInterval(),
      isNull,
    );
    expect(
      InstantValidity(ApproximateTime(calendar, '10', IntegerValue('1')))
          .asInterval(),
      isNull,
    );
    expect(
      InstantValidity(
        IntervalTime(calendar, const UnknownBound(), const ExactBound('10')),
      ).asInterval(),
      isNull,
    );
  });
  test('validity canonical encoding retains nested record range spelling', () {
    final interval = Validity.fromWire(
      wire(
        '''{"kind":"interval","start":{"kind":"approximate","value":"10",
      "uncertainty":{"kind":"range","lower":{"kind":"integer","digits":"1"},"upper":{"kind":"integer","digits":"2"},
      "lower_inclusive":true,"upper_inclusive":false}},"end":{"kind":"unknown"}}''',
      ),
    );
    expect(interval.toCanonical().toText(), contains('"lower_inclusive"'));
    expect(
      interval.toCanonical().toText(),
      isNot(contains('"lowerInclusive"')),
    );
  });
  test('every evidence basis retains its authored provenance and verified state', () {
    final forms = <EvidenceBasis>[
      const AuthorDecisionBasis('Authored fact'),
      SourceAnchorBasis(context, false),
      SourceAnchorBasis(context, true),
      EventEffectBasis(context, 'authored slot'),
      InstanceInitializationBasis(
        version,
        version,
        RevisionId.parse('rev_000000000000000000000001'),
      ),
      const ImportedClaimBasis(),
      DerivationBasis([version, version], 'evaluator-v1'),
    ];
    for (final form in forms) {
      expect(EvidenceBasis.fromWire(form.toWire()), form);
    }
    expect(forms[1], isNot(forms[2]));
    expect(
      () => EvidenceBasis.fromWire(
        wire(
          '{"kind":"source_anchor","anchor":{"record":"${context.record.value}"}}',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => EvidenceBasis.fromWire(
        wire('{"kind":"imported_claim","verified":true}'),
      ),
      throwsFormatException,
    );
  });
  test('derivation wire null differs from omitted comparison evaluator and preserves ordered pins', () {
    final absent = EvidenceBasis.fromWire(
      wire('{"kind":"derivation","chain":[]}'),
    );
    final explicit = EvidenceBasis.fromWire(
      wire('{"kind":"derivation","chain":[],"evaluator":null}'),
    );
    expect(absent, explicit);
    expect(
      absent.toWire().toText(),
      '{"chain":[],"evaluator":null,"kind":"derivation"}',
    );
    expect(absent.toCanonical().toText(), '{"chain":[],"kind":"derivation"}');
    final chain = DerivationBasis([version, version], null);
    expect(chain.chain, hasLength(2));
    expect(() => chain.chain.clear(), throwsUnsupportedError);
  });
  test(
    'polarity, precision and persistence remain closed independent dimensions',
    () {
      for (final item in Polarity.values) {
        expect(Polarity.fromWire(item.toWire()), item);
      }
      for (final item in Precision.values) {
        expect(Precision.fromWire(item.toWire()), item);
      }
      for (final item in PersistenceSemantics.values) {
        expect(PersistenceSemantics.fromWire(item.toWire()), item);
      }
      expect(Precision.oneOf.toWire().value, 'one_of');
      expect(
        () => Precision.fromWire(wire('"certain"')),
        throwsFormatException,
      );
      expect(
        () => PersistenceSemantics.fromWire(wire('"persistent"')),
        throwsFormatException,
      );
    },
  );
}
