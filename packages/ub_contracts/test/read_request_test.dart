import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

final universeId = UniverseId.parse('unv_000000000000000000000001');
final contextId = ContextId.parse('ctx_000000000000000000000001');
final recordId = RecordId.parse('rec_000000000000000000000001');
final worldId = WorldId.parse('wld_000000000000000000000001');
final continuityId = ContinuityId.parse('cont_000000000000000000000001');
final revisionId = RevisionId.parse('rev_000000000000000000000001');
final calendarId = CalendarId.parse('cal_000000000000000000000001');
const universe = Selector('é🌲 cycle');

CanonicalObject fields(
  CanonicalObject value,
  Map<String, CanonicalValue> changes,
) => CanonicalObject(
  {
    ...{for (final e in value.fields) e.key: e.value},
    ...changes,
  }.entries,
);

void main() {
  final reads = <ReadRequest>[
    DescribeSummaryRequest(universe: universe),
    DescribeCapabilitiesRequest(universe: universe, universeId: universeId),
    DescribeWorldsRequest(universe: universe, contextId: contextId),
    DescribeDefinitionsRequest(
      universe: universe,
      contextId: contextId,
      world: const Selector('Earth'),
      worldId: worldId,
    ),
    OpenContextRequest(
      universe: universe,
      continuityId: continuityId,
      revision: ExactRevisionSelector(revisionId: revisionId),
      representedContext: ContextNameSelector('Earth proper'),
      temporalQuery: AtEventFrameTime(
        RecordRef(record: recordId),
        EventTimeSide.after,
      ),
      temporalSystems: [calendarId],
      perspective: NarratorPerspective(recordId),
      readerScene: ContextIdSelector(recordId),
    ),
    SearchRequest(
      universe: universe,
      contextId: contextId,
      query: 'é search',
      typedFilters: Filters(recordKinds: RecordKind.values),
      limit: 100,
      cursor: 'opaque',
    ),
    GetRequest(
      universe: universe,
      contextId: contextId,
      recordIds: [recordId],
      fieldGroups: FieldGroup.values,
    ),
    GetStateRequest(
      universe: universe,
      contextId: contextId,
      entityIds: [recordId],
      predicateFilters: [],
      event: recordId,
      eventSide: EventTimeSide.before,
    ),
    GetContextRequest(
      universe: universe,
      contextId: contextId,
      focusIds: [recordId],
      purpose: 'research',
      byteBudget: 65536,
    ),
  ];
  for (final read in reads) {
    test('read request preserves closed owning wire: ${read.runtimeType}', () {
      read.validate();
      final parsed = ReadRequest.fromTool(read.toolName, read.toArgs());
      expect(parsed.toWire().toText(), read.toWire().toText());
      expect(
        ReadRequest.fromWire(read.toWire()).toWire().toText(),
        read.toWire().toText(),
      );
      expect(
        () => ReadRequest.fromTool(
          read.toolName,
          fields(read.toArgs(), {'extra': const CanonicalNull()}),
        ),
        isAInvalidArgument,
      );
      expect(
        () => ReadRequest.fromTool(
          read.toolName,
          fields(read.toArgs(), {'universe_id': const CanonicalNull()}),
        ),
        isAInvalidArgument,
      );
    });
  }
  test('selectors enforce exact routing UTF-8 bounds and Rust whitespace', () {
    final args = reads.first.toArgs();
    for (final text in [
      '',
      ' ',
      '\u0085name',
      ' name',
      '*',
      'a/b',
      r'a\b',
      'a\u0000b',
      'a\u009fb',
      'é' * 129,
    ]) {
      expect(
        () => ReadRequest.fromTool(
          'universe_describe',
          fields(args, {'universe': CanonicalString(text)}),
        ),
        isAInvalidArgument,
        reason: text,
      );
    }
    for (final text in ['é' * 128, 'name ', '\ufeff']) {
      ReadRequest.fromTool(
        'universe_describe',
        fields(args, {'universe': CanonicalString(text)}),
      );
    }
  });
  test('world ID and event side guards never imply missing scope', () {
    final state = GetStateRequest(
      universe: universe,
      contextId: contextId,
      entityIds: [recordId],
      predicateFilters: [],
    );
    for (final extra in [
      {'world_id': CanonicalString(worldId.value)},
      {'event': CanonicalString(recordId.value)},
      {'event_side': CanonicalString('after')},
      {'world': const CanonicalNull()},
      {'event': const CanonicalNull(), 'event_side': const CanonicalNull()},
    ]) {
      expect(
        () =>
            ReadRequest.fromTool(state.toolName, fields(state.toArgs(), extra)),
        isAInvalidArgument,
      );
    }
  });
  test('request list counts are bounded while filter lists retain owning semantics', () {
    for (final count in [0, 101]) {
      final r = GetRequest(
        universe: universe,
        contextId: contextId,
        recordIds: List.filled(count, recordId),
        fieldGroups: [],
      );
      expect(r.validate, isAInvalidArgument);
    }
    final ids = [recordId];
    final filters = [RecordKind.entity];
    final r = GetRequest(
      universe: universe,
      contextId: contextId,
      recordIds: ids,
      fieldGroups: [],
    );
    final f = Filters(recordKinds: filters);
    ids.clear();
    filters.clear();
    expect(r.recordIds, hasLength(1));
    expect(f.recordKinds, hasLength(1));
    expect(r.recordIds.clear, throwsUnsupportedError);
    expect(
      () => ReadRequest.fromTool(
        r.toolName,
        fields(r.toArgs(), {'record_ids': const CanonicalNull()}),
      ),
      isAInvalidArgument,
    );
  });
  test('request u32 parsing and semantic budget limits reject overflow or rounding', () {
    final search = reads.whereType<SearchRequest>().single;
    for (final raw in [
      '0',
      '101',
      '4294967296',
      '9007199254740993',
      '1.0',
      '-1',
    ]) {
      expect(
        () => ReadRequest.fromTool(
          search.toolName,
          fields(search.toArgs(), {'limit': CanonicalNumber(raw)}),
        ),
        isAInvalidArgument,
      );
    }
    final context = reads.whereType<GetContextRequest>().single;
    for (final raw in ['255', '65537']) {
      expect(
        () => ReadRequest.fromTool(
          context.toolName,
          fields(context.toArgs(), {'byte_budget': CanonicalNumber(raw)}),
        ),
        isAInvalidArgument,
      );
    }
    expect(
      () => ReadRequest.fromTool(
        context.toolName,
        fields(context.toArgs(), {'purpose': CanonicalString('é' * 2049)}),
      ),
      isAInvalidArgument,
    );
  });
  test('selectors distinguish opaque identity from explicit name objects', () {
    expect(
      RepresentedContextSelector.fromWire(CanonicalString(recordId.value)),
      isA<ContextIdSelector>(),
    );
    expect(
      RepresentedContextSelector.fromWire(
        CanonicalObject([MapEntry('name', CanonicalString(recordId.value))]),
      ),
      isA<ContextNameSelector>(),
    );
    expect(
      () => RepresentedContextSelector.fromWire(CanonicalString('Earth')),
      throwsFormatException,
    );
    expect(
      () => RevisionSelector.fromWire(
        CanonicalValue.parseJson(
          '{"kind":"head","revision_id":"${revisionId.value}"}',
        ),
      ),
      throwsFormatException,
    );
  });
  test('protocol errors preserve domain wire code and public error code distinction', () {
    const error = DomainError(message: 'unknown authored value');
    expect(error.code, 'DOMAIN_ERROR');
    expect(ProtocolError.fromWire(error.toWire()), error);
    expect(ProtocolError.fromWire(error.toWire()).hashCode, error.hashCode);
    expect(const Selector('Earth'), const Selector('Earth'));
    expect(const Selector('Earth'), isNot(const Selector('earth')));
    expect(error.isProtocolFailure, isTrue);
    expect(ProtocolError.fromWire(error.toWire()), isA<DomainError>());
    expect(
      ProtocolError.fromWire(error.toWire()).toWire().toText(),
      error.toWire().toText(),
    );
    expect(const ApprovalStaleError().isProtocolFailure, isFalse);
    expect(
      const NotFoundOrNotAccessibleError(message: 'not accessible')
          .isProtocolFailure,
      isFalse,
    );
    expect(
      () => ProtocolError.fromWire(
        CanonicalValue.parseJson('{"code":"APPROVAL_STALE","message":"extra"}'),
      ),
      throwsFormatException,
    );
  });
}

final isAInvalidArgument = throwsA(isA<InvalidArgumentError>());
