import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

CanonicalValue wire(String text) => CanonicalValue.parseWireJson(text);
final invalid = throwsA(isA<InvalidArgumentError>());

void main() {
  test(
    'ordinary numbers and quoted text remain distinct exact author inputs',
    () {
      for (final raw in [
        '30.00',
        '1E3',
        '18446744073709551616',
        '-9223372036854775809',
      ]) {
        final numeric = FactValue.fromWire(wire(raw)) as FactNumberValue;
        expect(numeric.toWire(), isA<CanonicalNumber>());
        expect(numeric.toWire().toText(), wire(raw).toText());
        final quoted = FactValue.fromWire(wire('"$raw"'));
        expect(quoted, isA<FactTextValue>());
        expect(quoted.toWire(), isA<CanonicalString>());
      }
      expect(FactValue.fromWire(wire('true')), isA<FactBooleanValue>());
    },
  );
  test(
    'named object and unit amount preserve untagged historical precedence',
    () {
      final object = FactValue.fromWire(
        wire('{"object":"Mara","amount":1,"unit":"m","extra":null}'),
      ) as FactObjectValue;
      expect(object.object, 'Mara');
      expect(object.toWire().toText(), '{"object":"Mara"}');
      final quantity = FactValue.fromWire(
        wire('{"object":false,"amount":30.00,"unit":"Authored Unit"}'),
      ) as FactQuantityValue;
      expect(quantity.amount.digits, '30.00');
      expect(quantity.unit, 'Authored Unit');
      expect(
        quantity.toWire().toText(),
        '{"amount":30.00,"unit":"Authored Unit"}',
      );
      for (final raw in [
        'null',
        '[]',
        '{"kind":"integer","digits":"30"}',
        '{"amount":"30.00","unit":"m"}',
        '{"object":false}',
      ]) {
        expect(
          () => FactValue.fromWire(wire(raw)),
          throwsFormatException,
          reason: raw,
        );
      }
      expect(
        () => FactNumberValue(const CanonicalNumber('01')),
        throwsFormatException,
      );
      expect(
        () => FactNumberValue(const CanonicalNumber('NaN')),
        throwsFormatException,
      );
    },
  );
  test('fact defaults preserve unspecified time scope and lifetime with explicit nullable tick', () {
    final fact = FactChange.fromWire(wire('{"property":"age","value":40}'));
    expect(fact.statement, 'objective');
    expect(fact.scope, 'unspecified');
    expect(fact.when, 'unspecified');
    expect(fact.negated, isFalse);
    expect(fact.lifetime, isA<FactUnspecifiedLifetime>());
    expect(fact.toWire().toText(), contains('"at_tick":null'));
    expect(fact.toWire().toText(), isNot(contains('at_date')));
    for (final raw in [
      '{"property":"age","value":40,"negated":null}',
      '{"property":"age","value":40,"lifetime":null}',
      '{"property":"age","value":40,"statement":null}',
      '{"property":"age","value":40,"extra":false}',
    ]) {
      expect(() => FactChange.fromWire(wire(raw)), throwsFormatException);
    }
  });
  test('attributed statements do not change into objective fact declarations', () {
    for (final statement in [
      'dialogue',
      'belief',
      'plan',
      'hypothetical',
      'metaphor',
    ]) {
      final fact = FactChange.fromWire(
        wire(
          '{"property":"holder","value":{"object":"Mara"},"statement":"$statement","scope":"Earth","when":"scene","at_tick":"9007199254740993"}',
        ),
      );
      expect(fact.statement, statement);
      expect(fact.atTick, '9007199254740993');
      expect(fact.scope, 'Earth');
      expect(FactChange.fromWire(fact.toWire()).statement, statement);
    }
  });
  test('ending lifetime keeps authored dates and exclusive end separate from unchanged stock', () {
    expect(
      FactLifetime.fromWire(wire('{"kind":"until"}')).toWire().toText(),
      '{"end_tick":"","kind":"until"}',
    );
    final until = FactLifetime.fromWire(
      wire(
        '{"kind":"until","end_tick":"9007199254740993","end_date":"1900-01-01"}',
      ),
    ) as FactUntilLifetime;
    expect(until.endTick, '9007199254740993');
    expect(until.endDate, '1900-01-01');
    expect(
      () => FactLifetime.fromWire(
        wire('{"kind":"until_changed","end_tick":"3"}'),
      ),
      throwsFormatException,
    );
    final ending = WritingFactEnding.fromWire(
      wire(
        '{"fact_handle":"exact version","reason":"ended","end_date":"1900-01-01"}',
      ),
    );
    expect(ending.endTick, '');
    expect(ending.endDate, '1900-01-01');
    expect(
      WritingFactWithdrawal.fromWire(
        wire('{"fact_handle":"exact version","reason":"unsupported"}'),
      ).toWire().toText(),
      '{"fact_handle":"exact version","reason":"unsupported"}',
    );
  });
  test('independent instance intent shared characteristics and initial values stay separate', () {
    final object = ObjectChange.fromWire(wire('{"name":"Mara"}'));
    expect(object.introduce, isFalse);
    expect(object.classification, isNull);
    expect(object.facts, isEmpty);
    final source = [
      FactChange(
        property: 'stock',
        value: FactNumberValue(const CanonicalNumber('8')),
      ),
    ];
    final definition = DefinitionChange(name: 'Pistol', initialValues: source);
    source.clear();
    expect(definition.initialValues, hasLength(1));
    expect(definition.sharedAttributes, isEmpty);
    expect(definition.initialValues.clear, throwsUnsupportedError);
    expect(definition.parent, isNull);
    expect(definition.scope, 'unspecified');
    expect(
      () => ObjectChange.fromWire(wire('{"name":"Mara","facts":null}')),
      throwsFormatException,
    );
  });
  test('author-facing claims and historical corrections retain opaque handles exact values', () {
    final claim = WritingClaim.fromWire(
      wire('{"subject":"Mara","property":"age","value":30.00}'),
    );
    expect(claim.value, isA<FactNumberValue>());
    final correction = WritingCorrection.fromWire(
      wire(
        '{"fact_handle":"opaque pinned handle","value":30.00,"reason":"transcription correction"}',
      ),
    );
    expect(correction.factHandle, 'opaque pinned handle');
    expect(correction.value.toWire().toText(), '30.00');
    expect(
      () => WritingCorrection.fromWire(
        wire('{"fact_handle":"opaque","value":30.00}'),
      ),
      throwsFormatException,
    );
  });
  test('ordinary research requires explicit exact objects but permits empty contract discovery', () {
    final facts = ReadFactsRequest.fromWire(
      wire(
        '{"universe":"Cycle","context_id":"ctx_000000000000000000000001","object_names":["Mara"]}',
      ),
    );
    expect(
      Request.fromTool(facts.toolName, facts.toArgs()),
      isA<ReadFactsRequest>(),
    );
    expect(
      ReadRequest.fromTool(facts.toolName, facts.toArgs()),
      isA<ReadFactsRequest>(),
    );
    final contracts = ReadContractsRequest.fromWire(
      wire('{"universe":"Cycle","context_id":"ctx_000000000000000000000001"}'),
    );
    contracts.validate();
    expect(contracts.actionNames, isEmpty);
    expect(
      Request.decode(contracts.toWire().toBytes()),
      isA<ReadContractsRequest>(),
    );
    expect(
      () => Request.fromTool(
        'universe_read_facts',
        wire(
          '{"universe":"Cycle","context_id":"ctx_000000000000000000000001","object_names":[]}',
        ),
      ),
      invalid,
    );
    expect(
      () => Request.fromTool(
        'universe_read_facts',
        wire(
          '{"universe":"Cycle","context_id":"ctx_000000000000000000000001","object_names":[" "]}',
        ),
      ),
      invalid,
    );
    expect(
      () => Request.fromTool(
        'universe_read_contracts',
        wire(
          '{"universe":"Cycle","context_id":"ctx_000000000000000000000001","action_names":[" "]}',
        ),
      ),
      invalid,
    );
    expect(
      () => Request.fromTool(
        'universe_read_facts',
        wire(
          '{"universe":"Cycle","context_id":"ctx_000000000000000000000001","object_names":["Mara"],"world":null}',
        ),
      ),
      invalid,
    );
    expect(
      () => Request.fromTool(
        'universe_read_facts',
        wire(
          '{"universe":"Cycle","context_id":"ctx_000000000000000000000001","object_names":["Mara"],"world":"*"}',
        ),
      ),
      invalid,
    );
    expect(
      () => Request.fromTool(
        'universe_read_contracts',
        wire(
          '{"universe":"Cycle","context_id":"ctx_000000000000000000000001","action_names":null}',
        ),
      ),
      invalid,
    );
  });
}
