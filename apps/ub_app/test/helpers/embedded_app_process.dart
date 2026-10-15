import 'dart:io';

import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/world_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

// Disposable app-side peer. The parent kills this process after a durable
// response, before the waiting app-side operation consumes its completion.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 ||
      !{'save', 'validation', 'publication'}.contains(arguments[1])) {
    throw const FormatException(
      'Choose a disposable root and interruption phase.',
    );
  }
  final phase = arguments[1];
  AppSession? session;
  try {
    session = await DeviceConnection([
      '--installation',
      arguments[0],
    ], embeddedLocal: true).connect();
    final status = InstanceLibrary.fromWire(
      await session.call(const StatusEngineRequest()),
    );
    final created = await session.call(
      const CreateUniverseEngineRequest(
        name: 'Mobile interruption',
        start: GregorianUniverseStart('2040-01-01T00:00:00Z'),
      ),
    );
    final fields = WireFields(created, {
      'universe_id',
      'continuity_id',
      'context_id',
      'revision',
      'name',
    });
    final scope = EditorFormScope(
      instance: status.instance,
      profile: session.principal,
      universe: UniverseId.parse(fields.string('universe_id')),
      continuity: ContinuityId.parse(fields.string('continuity_id')),
      representedContext: RecordId.parse(fields.string('context_id')),
    );
    final source = UnfinishedSourceForm(
      baseRevision: RevisionId.parse(fields.string('revision')),
      representedContext: scope.representedContext!,
      clientRef: 'private mobile input',
      label: 'Recollection 記憶 😀',
      text: '\ufeffFirst line\r\nSecond line 😀\r\n',
    );
    await session.saveSourceForm(scope, source, BigInt.zero);
    await session.call(
      worldDraftRequest(
        universe: const Selector('Mobile interruption'),
        continuity: scope.continuity,
        previous: null,
        form: UnfinishedWorldForm(
          baseRevision: source.baseRevision,
          representedContext: scope.representedContext!,
          record: RecordId.generate(),
          selector: 'River world',
          settingType: '',
          rationale: 'Create the disposable campaign world.',
        ),
      ),
    );
    final changes = SavedChanges(
      session: session,
      universe: const Selector('Mobile interruption'),
      scope: scope,
    );
    Proposal? proposal;
    EvaluatedValidation? validation;
    CommitReceipt? receipt;
    if (phase != 'save') {
      proposal = await changes.submit((await changes.load())!);
      validation = await changes.validate(proposal) as EvaluatedValidation;
    }
    if (phase == 'publication') {
      await changes.approve(proposal!, validation!);
      receipt = await changes.publish(proposal, validation.execution.runId);
    }
    final draft = (await changes.load())!;
    stdout.writeln(
      'UB_EMBEDDED_FIXTURE ${CanonicalObject([MapEntry('fixture', CanonicalString('embedded-app-termination')), MapEntry('phase', CanonicalString(phase)), MapEntry('instance', CanonicalString(status.instance.value)), MapEntry('profile', CanonicalString(session.principal.value)), MapEntry('created', created), MapEntry('source_form', source.toWire()), MapEntry('draft', draft.toWire()), if (proposal != null) MapEntry('proposal', proposal.toWire()), if (validation != null) MapEntry('validation', validation.toWire()), if (receipt != null) MapEntry('receipt', receipt.toWire())]).toText()}',
    );
    await stdout.flush();
    // No further mutations or replies. Keep both app and embedded worker alive
    // until the parent terminates the process without graceful shutdown.
    await stdin.drain<void>();
  } on Object catch (error) {
    stderr.writeln('Embedded fixture failed: ${error.runtimeType}');
    exitCode = 1;
  } finally {
    await session?.close();
  }
}
