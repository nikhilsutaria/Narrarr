import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show appFlavor;

/// Which build flavor this binary was built as (`flutter run --flavor qa`).
///
/// - **qa** bundles the sample book (The Odyssey) and the default Amy voice,
///   so the whole read-aloud loop works out of the box with no network.
/// - **prod** (and unflavored builds, including `flutter test`) ships clean:
///   no sample book, and every voice — Amy included — is download-on-demand,
///   which keeps the released bundle small.
class BuildFlavor {
  BuildFlavor._();

  /// Test seam: [appFlavor] is baked in at build time, so tests set this
  /// instead. Reset to null in tearDown.
  @visibleForTesting
  static String? debugOverride;

  static bool get isQa => (debugOverride ?? appFlavor) == 'qa';
}
