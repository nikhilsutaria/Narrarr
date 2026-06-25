import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/a11y/a11y_policy.dart';

void main() {
  test('exclude content semantics only when screen reader is on AND narrating',
      () {
    expect(
      shouldExcludeContentSemantics(screenReaderOn: true, narrating: true),
      isTrue,
    );
    expect(
      shouldExcludeContentSemantics(screenReaderOn: true, narrating: false),
      isFalse,
    );
    expect(
      shouldExcludeContentSemantics(screenReaderOn: false, narrating: true),
      isFalse,
    );
    expect(
      shouldExcludeContentSemantics(screenReaderOn: false, narrating: false),
      isFalse,
    );
  });
}
