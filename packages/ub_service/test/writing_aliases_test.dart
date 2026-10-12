import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_service/ub_service.dart';

import 'operation_compilation_test.dart' as f;
import 'rule_checks_test.dart' as facts;
import 'writing_contexts_test.dart' as contexts;
import 'writing_binding_test.dart' as binding;

void main() {
  test('aliases preserve explicit qualifiers and pinned identities without manufacturing knowledge', () {
    final base = contexts.rows();
    final result = compileWritingAliases(
      frame: facts.frame(),
      base: base,
      aliases: [
        WritingAlias(
          object: 'Mara',
          text: 'Captain',
          language: 'en',
          community: 'Crew',
          role: 'rank',
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    final op = result.operations.single as AddNameOperation;
    expect(op.record, f.ref(80));
    expect(op.expectedVersion, f.ver(80));
    expect(op.name.validity, const UnspecifiedValidity());
    expect(op.name.language, 'en');
    expect(op.name.community, 'Crew');
    expect(op.name.role, 'rank');
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: result.operations,
    );
    expect(candidate.length, base.length);
    expect(
      candidate.where(
        (r) =>
            r.payload is EpistemicAttitudeRecord ||
            r.payload is CommunicationRecord,
      ),
      isEmpty,
    );
    expect(resolveWritingObject(candidate, 'Captain', facts.frame()), f.id(80));
    final repeated = compileWritingAliases(
      frame: facts.frame(),
      base: candidate,
      aliases: [
        WritingAlias(
          object: 'Captain',
          text: 'Captain',
          language: 'en',
          community: 'Crew',
          role: 'rank',
        ),
        WritingAlias(object: 'Mara', text: 'New'),
        WritingAlias(object: 'Captain', text: 'Another'),
      ],
    );
    expect(repeated.unchanged, ['Existing alias: Captain — Captain']);
    expect(repeated.operations, hasLength(1));
    expect(repeated.clarifications.single, contains('only one new alias'));
  });

  test('timed aliases require authored chronology and remain time-scoped', () {
    final base = contexts.rows();
    final result = compileWritingAliases(
      frame: facts.frame(),
      base: base,
      aliases: [
        WritingAlias(
          object: 'Mara',
          text: 'Captain',
          atTick: '9007199254740993',
          lifetime: FactUntilLifetime(endTick: '9007199254740995'),
        ),
      ],
    );
    expect(result.clarifications, isEmpty);
    final op = result.operations.single as AddNameOperation;
    expect(
      op.name.validity,
      CalendarIntervalValidity(
        facts.calendar,
        const ExactBound('9007199254740993'),
        const ExactBound('9007199254740995'),
      ),
    );
    final candidate = compileWritingCandidate(
      universe: f.u,
      revision: f.revision,
      base: base,
      operations: result.operations,
    );
    expect(
      resolveWritingObject(
        candidate,
        'Captain',
        facts.frame(time: AtFrameTime(ExactTime(facts.calendar, '10'))),
      ),
      isNull,
    );
    expect(
      resolveWritingObject(
        candidate,
        'Captain',
        facts.frame(
          time: AtFrameTime(ExactTime(facts.calendar, '9007199254740994')),
        ),
      ),
      f.id(80),
    );
    expect(
      resolveWritingObject(
        candidate,
        'Captain',
        facts.frame(
          time: AtFrameTime(ExactTime(facts.calendar, '9007199254740995')),
        ),
      ),
      isNull,
    );
    final missing = compileWritingAliases(
      frame: facts.frame(),
      base: [base[1]],
      aliases: [WritingAlias(object: 'Mara', text: 'Captain', atTick: '20')],
    );
    expect(missing.operations, isEmpty);
    expect(missing.clarifications.single, contains('exact authored calendar'));
    final instant = compileWritingAliases(
      frame: facts.frame(time: AtFrameTime(ExactTime(facts.calendar, '20'))),
      base: base,
      aliases: [
        WritingAlias(
          object: 'Mara',
          text: 'Now',
          lifetime: const FactUnspecifiedLifetime(),
        ),
      ],
    );
    expect(
      (instant.operations.single as AddNameOperation).name.validity,
      InstantValidity(ExactTime(facts.calendar, '20')),
    );
  });

  test(
    'aliases cannot bind ambiguous absent newly introduced or blank names',
    () {
      final base = contexts.rows();
      final result = compileWritingAliases(
        frame: facts.frame(),
        base: base,
        aliases: [
          WritingAlias(object: 'Mara', text: 'Captain'),
          WritingAlias(object: 'Captain', text: 'Leader'),
          WritingAlias(object: 'Absent', text: 'Name'),
          WritingAlias(object: 'Mara', text: '\u0085\u3000'),
        ],
      );
      expect(result.operations, hasLength(1));
      expect(result.clarifications, hasLength(3));
      final ambiguous = compileWritingAliases(
        frame: facts.frame(),
        base: [
          ...base,
          f.row(81, binding.entity(labels: {'en': 'Mara'})),
        ],
        aliases: [WritingAlias(object: 'Mara', text: 'Captain')],
      );
      expect(ambiguous.operations, isEmpty);
      expect(ambiguous.clarifications, hasLength(1));
    },
  );
}
