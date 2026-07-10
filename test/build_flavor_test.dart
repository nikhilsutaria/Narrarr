import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/build_flavor.dart';

void main() {
  tearDown(() => BuildFlavor.debugOverride = null);

  test('unflavored builds (tests, plain flutter run) are not qa', () {
    expect(BuildFlavor.isQa, isFalse);
  });

  test('debugOverride selects the flavor', () {
    BuildFlavor.debugOverride = 'qa';
    expect(BuildFlavor.isQa, isTrue);
    BuildFlavor.debugOverride = 'prod';
    expect(BuildFlavor.isQa, isFalse);
  });
}
