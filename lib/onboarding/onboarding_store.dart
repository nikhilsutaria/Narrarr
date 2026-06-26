import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Tracks whether the first-run onboarding has been shown.
class OnboardingStore {
  OnboardingStore({File? file}) : _injected = file;
  final File? _injected;

  Future<File> _file() async =>
      _injected ??
      File(p.join((await getApplicationSupportDirectory()).path,
          'onboarding.json'));

  Future<bool> seen() async => (await _file()).exists();

  Future<void> markSeen() async {
    final f = await _file();
    await f.writeAsString('{"seen":true}');
  }
}
