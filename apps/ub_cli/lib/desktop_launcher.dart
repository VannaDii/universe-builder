import 'dart:io';

import 'package:ub_domain/ub_domain.dart';

/// The maintained desktop commands accept an explicit complete connection, or
/// open the normal Library connection chooser. They never initialize an engine.
final class DesktopOptions {
  DesktopOptions._(this.arguments, this.destination, this.launcher);
  final List<String> arguments;
  final String? destination, launcher;

  factory DesktopOptions.parse(
    List<String> arguments, {
    required bool shortcut,
  }) {
    if (!shortcut && arguments.length == 1 && arguments.single == '--fixture') {
      return DesktopOptions._(const ['--fixture'], null, null);
    }
    final values = <String, String>{};
    final allowed = {
      '--installation',
      '--profile',
      if (!shortcut) '--link',
      if (shortcut) ...['--destination', '--launcher'],
    };
    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      // Desktop entries expand %u to one optional trailing URI.
      if (!shortcut &&
          i == arguments.length - 1 &&
          !argument.startsWith('--')) {
        if (values.containsKey('--link')) {
          throw const FormatException('Duplicate application link');
        }
        values['--link'] = argument;
        continue;
      }
      final equal = argument.indexOf('=');
      final option = equal < 0 ? argument : argument.substring(0, equal);
      if (!allowed.contains(option) || values.containsKey(option)) {
        throw const FormatException('Unknown or duplicate desktop option');
      }
      final value = equal < 0
          ? (++i < arguments.length ? arguments[i] : '')
          : argument.substring(equal + 1);
      if (value.isEmpty || value.startsWith('--') || value.contains('\u0000')) {
        throw const FormatException('Missing desktop option');
      }
      values[option] = value;
    }
    final root = values['--installation'], profile = values['--profile'];
    if ((root == null) != (profile == null)) {
      throw const FormatException('Installation and profile must be paired');
    }
    if (profile != null) ProfileId.parse(profile);
    final link = values['--link'];
    if (link != null) {
      final uri = Uri.tryParse(link);
      if (link.contains('\u0000') ||
          uri == null ||
          uri.scheme != 'universe-builder' ||
          uri.authority.isNotEmpty ||
          !uri.path.startsWith('/') ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FormatException(
          'Expected a hostless Universe Builder link',
        );
      }
    }
    return DesktopOptions._(
      [
        if (root != null) ...[
          '--installation',
          Directory(root).absolute.path,
          '--profile',
          profile!,
        ],
        if (link != null) ...['--link', link],
      ],
      values['--destination'],
      values['--launcher'],
    );
  }
}

({String executable, List<String> arguments}) desktopCommand(
  String engine,
  List<String> arguments, {
  bool? macOS,
}) {
  final directory = File(engine).parent;
  if (macOS ?? Platform.isMacOS) {
    var bundle = directory;
    while (bundle.path != bundle.parent.path) {
      if (bundle.path.endsWith('.app')) {
        return (
          executable: '/usr/bin/open',
          arguments: ['-n', bundle.path, '--args', ...arguments],
        );
      }
      bundle = bundle.parent;
    }
  }
  if (Platform.isLinux) {
    final packaged = '${directory.parent.path}/desktop/universe_builder';
    if (File(packaged).existsSync()) {
      return (executable: packaged, arguments: arguments);
    }
  }
  return (
    executable:
        '${directory.path}/universe_builder${Platform.isWindows ? '.exe' : ''}',
    arguments: arguments,
  );
}

String _shellWord(String text) => "'${text.replaceAll("'", "'\\''")}'";

String _desktopWord(String text) {
  if (text.contains('\n') || text.contains('\r') || text.contains('\u0000')) {
    throw const FormatException('Desktop entries require single-line paths');
  }
  return '"${text.replaceAll(r'\', r'\\\\').replaceAll('"', r'\\"').replaceAll(r'$', r'\\$').replaceAll('`', r'\\`').replaceAll('%', '%%')}"';
}

Future<String> createLinuxShortcut({
  required String engine,
  required DesktopOptions options,
}) async {
  if (!Platform.isLinux) {
    throw const FormatException('Linux shortcut requires Linux');
  }
  final home = Platform.environment['HOME'];
  final data = Platform.environment['XDG_DATA_HOME'];
  final destination =
      options.destination ??
      (data?.startsWith('/') == true
          ? '$data/applications'
          : home == null
          ? throw const FormatException('Home unavailable')
          : '$home/.local/share/applications');
  final invoked = File(Platform.executable);
  final launcher =
      options.launcher ??
      (invoked.isAbsolute ? invoked.path : Platform.resolvedExecutable);
  if (!File(launcher).isAbsolute ||
      !File(launcher).existsSync() ||
      launcher.contains('=')) {
    throw const FormatException(
      'Existing absolute launcher without = required',
    );
  }
  final icon = File(
    '${File(engine).parent.parent.path}/desktop/data/icons/universe-builder.png',
  );
  if (FileSystemEntity.typeSync(icon.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Approved bundled icon unavailable');
  }
  // GIO checks the program path before expanding literal %% escapes. Keep the
  // program fixed; env executes the exact absolute launcher as an argument.
  final command = [
    '/usr/bin/env',
    launcher,
    'ux',
    ...options.arguments,
  ].map(_desktopWord).join(' ');
  if (icon.path.contains('\n') || icon.path.contains('\r')) {
    throw const FormatException('Invalid icon path');
  }
  final content =
      '[Desktop Entry]\nType=Application\nName=Universe Builder\n'
      'Exec=$command %u\nIcon=${icon.path.replaceAll(r'\', r'\\')}\n'
      'Terminal=false\nCategories=Office;\nMimeType=x-scheme-handler/universe-builder;\nStartupWMClass=com.example.universe_builder\n';
  final parent = Directory(destination).absolute;
  await parent.create(recursive: true);
  final file = File('${parent.path}/universe-builder.desktop');
  await file.create(exclusive: true);
  try {
    await file.writeAsString(content, flush: true);
    final mode = await Process.run('/bin/chmod', ['755', file.path]);
    if (mode.exitCode != 0) {
      throw const FileSystemException('Shortcut permissions unavailable');
    }
    return file.path;
  } on Object {
    await file.delete();
    rethrow;
  }
}

/// A Finder shortcut contains only a literal invocation and the approved icon.
/// Exclusive mkdir refuses an existing app or link; only our new app is cleaned
/// up if its construction fails. The target installation is never modified.
Future<String> createFinderShortcut({
  required String engine,
  required DesktopOptions options,
}) async {
  if (!Platform.isMacOS) {
    throw const FormatException('Finder shortcuts require macOS');
  }
  final home = Platform.environment['HOME'];
  final destination =
      options.destination ??
      (home == null
          ? throw const FormatException('Home unavailable')
          : '$home/Applications');
  final invoked = File(Platform.executable);
  final launcher =
      options.launcher ??
      (invoked.isAbsolute ? invoked.path : Platform.resolvedExecutable);
  if (!File(launcher).isAbsolute || !File(launcher).existsSync()) {
    throw const FormatException('Existing absolute launcher required');
  }
  final icon = File(
    '${File(engine).parent.parent.path}/Resources/AppIcon.icns',
  );
  if (FileSystemEntity.typeSync(icon.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw const FormatException('Approved bundled icon unavailable');
  }
  final parent = Directory(destination).absolute;
  await parent.create(recursive: true);
  final app = Directory('${parent.path}/Multiverse MCP.app');
  final created = await Process.run('/bin/mkdir', [app.path]);
  if (created.exitCode != 0) {
    throw const FormatException('Shortcut already exists or cannot be created');
  }
  try {
    final bin = Directory('${app.path}/Contents/MacOS');
    await bin.create(recursive: true);
    final resources = Directory('${app.path}/Contents/Resources');
    await resources.create(recursive: true);
    final script = File('${bin.path}/launch');
    await script.writeAsString(
      '#!/bin/sh\nexec ${[_shellWord(launcher), 'ux', ...options.arguments.map(_shellWord)].join(' ')}\n',
    );
    final permission = await Process.run('/bin/chmod', ['755', script.path]);
    if (permission.exitCode != 0) {
      throw const FileSystemException('Shortcut permissions unavailable');
    }
    await icon.copy('${resources.path}/universe-builder.icns');
    await File('${app.path}/Contents/Info.plist')
        .writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>launch</string>
<key>CFBundleIdentifier</key><string>local.multiverse-mcp.shortcut</string>
<key>CFBundleName</key><string>Multiverse MCP</string>
<key>CFBundleIconFile</key><string>universe-builder.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
''');
    return app.path;
  } on Object {
    await app.delete(recursive: true);
    rethrow;
  }
}
