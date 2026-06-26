import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/onboarding/onboarding_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('seen flips after markSeen', () async {
    final tmp = Directory.systemTemp.createTempSync('ob');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = OnboardingStore(file: File(p.join(tmp.path, 'ob.json')));
    expect(await store.seen(), isFalse);
    await store.markSeen();
    expect(await store.seen(), isTrue);
  });
}
