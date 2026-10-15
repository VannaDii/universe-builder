@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart' hide Description;
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_app/saved_changes.dart';
import 'package:ub_app/world_browser.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  late Directory build;
  late String executable;
  setUpAll(() async {
    build = Directory.systemTemp.createTempSync('ub-embedded-process-build-');
    final helper = [
      File('test/helpers/embedded_app_process.dart'),
      File('apps/ub_app/test/helpers/embedded_app_process.dart'),
    ].firstWhere((f) => f.existsSync()).absolute;
    final vm = File(Platform.resolvedExecutable);
    final dart = vm.uri.pathSegments.last == 'dartvm'
        ? '${vm.parent.path}/dart'
        : vm.path;
    final result = await Process.run(dart, [
      'build',
      'cli',
      '-o',
      build.path,
      '--target',
      'test/helpers/embedded_app_process.dart',
    ], workingDirectory: helper.parent.parent.parent.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    executable = '${build.path}/bundle/bin/embedded_app_process';
  });
  tearDownAll(() => build.deleteSync(recursive: true));

  for (final phase in ['save', 'validation', 'publication']) {
    test(
      'embedded app survives forced process exit after durable $phase without replaying publication',
      () async {
        final root = Directory.systemTemp.createTempSync('ub-embedded-$phase-');
        Process? child;
        var stopped = false;
        AppSession? session;
        try {
          child = await Process.start(
            executable,
            [root.path, phase],
            environment: {'UB_USE_POSTGRES': 'false'},
          );
          final diagnostics = StringBuffer();
          final errors = child.stderr.transform(utf8.decoder).listen((text) {
            if (diagnostics.length < 8192) diagnostics.write(text);
          });
          const marker = 'UB_EMBEDDED_FIXTURE ';
          final line = await child.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .firstWhere((line) => line.startsWith(marker))
              .timeout(const Duration(seconds: 30));
          final fixture = WireFields(
            CanonicalValue.parseWireJson(line.substring(marker.length)),
            {
              'fixture',
              'phase',
              'instance',
              'profile',
              'created',
              'source_form',
              'draft',
              'proposal',
              'validation',
              'receipt',
            },
          );
          expect(
            fixture.string('fixture'),
            'embedded-app-termination',
            reason: diagnostics.toString(),
          );
          expect(fixture.string('phase'), phase);
          expect(child.kill(ProcessSignal.sigkill), isTrue);
          expect(await child.exitCode, isNot(0));
          stopped = true;
          await errors.cancel();

          session = await DeviceConnection([
            '--installation',
            root.path,
          ], embeddedLocal: true).connect();
          final library = InstanceLibrary.fromWire(
            await session.call(const StatusEngineRequest()),
          );
          expect(library.instance.value, fixture.string('instance'));
          expect(session.principal.value, fixture.string('profile'));
          final created = WireFields(fixture.require('created'), {
            'universe_id',
            'continuity_id',
            'context_id',
            'revision',
            'name',
          });
          final scope = EditorFormScope(
            instance: library.instance,
            profile: session.principal,
            universe: UniverseId.parse(created.string('universe_id')),
            continuity: ContinuityId.parse(created.string('continuity_id')),
            representedContext: RecordId.parse(created.string('context_id')),
          );
          expect(
            (await session.loadSourceForm(scope))!.form.toWire().toText(),
            fixture.require('source_form').toText(),
          );
          final changes = SavedChanges(
            session: session,
            universe: const Selector('Mobile interruption'),
            scope: scope,
          );
          final draft = (await changes.load())!;
          expect(draft.toWire().toText(), fixture.require('draft').toText());
          final recovered = await changes.recover(draft);
          if (phase == 'save') {
            expect(recovered, isNull);
          } else {
            final proposal = Proposal.fromWire(fixture.require('proposal'));
            expect(recovered!.toWire().toText(), proposal.toWire().toText());
            final validation = ValidationV3.fromWire(
              fixture.require('validation'),
            ) as EvaluatedValidation;
            if (phase == 'validation') {
              expect(await changes.publication(recovered), isNull);
              await changes.approve(recovered, validation);
              final retained = (await changes.publication(recovered))!;
              expect(retained.run, validation.execution.runId);
              expect(retained.status, isNull);
            } else {
              final receipt = CommitReceipt.fromWire(
                fixture.require('receipt'),
              );
              final retained = (await changes.publication(recovered))!;
              expect(
                retained.status!.receipt!.toWire().toText(),
                receipt.toWire().toText(),
              );
              expect(
                (await changes.publish(
                  recovered,
                  retained.run,
                )).toWire().toText(),
                receipt.toWire().toText(),
              );
              final records = await changes.readPublished(recovered, receipt);
              expect(
                records.where((r) => r.payload is WorldRecord),
                hasLength(1),
              );
            }
          }
          final description = Envelope<Description>.fromWire(
            await session.call(
              ToolEngineRequest(
                request: DescribeSummaryRequest(
                  universe: const Selector('Mobile interruption'),
                  universeId: scope.universe,
                ),
              ),
            ),
            Description.fromWire,
          ).result;
          final worlds = await readContextWorlds(
            session: session,
            universe: LibraryEntry(scope.universe, 'Mobile interruption'),
            continuity: description.continuities.single,
            representedContext:
                description.continuities.single.representedContexts.single,
          );
          if (phase == 'publication') {
            final receipt = CommitReceipt.fromWire(fixture.require('receipt'));
            expect(
              description.continuities.single.revisionId,
              receipt.revision,
            );
            expect(worlds.result.worlds.single.name.value, 'River world');
          } else {
            expect(
              description.continuities.single.revisionId.value,
              created.string('revision'),
            );
            expect(worlds.result.worlds, isEmpty);
          }
        } finally {
          if (child != null && !stopped) {
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
          }
          await session?.close();
          root.deleteSync(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
