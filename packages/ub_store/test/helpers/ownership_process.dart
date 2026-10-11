import 'dart:convert';
import 'dart:io';

import 'package:ub_store/src/ownership.dart';

Future<void> main(List<String> args) async {
  try {
    final lock = OwnedFileLock.acquire(args[0]);
    try {
      if (args.length > 1 && args[1] == 'hold') {
        stdout.writeln('owned');
        await stdout.flush();
        await stdin
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first;
      }
    } finally {
      lock.close();
    }
  } on FileSystemException {
    exitCode = 2;
  }
}
