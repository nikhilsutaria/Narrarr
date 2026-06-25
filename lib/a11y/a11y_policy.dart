/// When the OS screen reader (TalkBack) is on AND the app is narrating aloud,
/// the page text and the app's own voice both speak. Resolve by removing the
/// book content from the accessibility tree while self-narrating; transport
/// controls stay accessible. Pure so it is unit-testable.
bool shouldExcludeContentSemantics({
  required bool screenReaderOn,
  required bool narrating,
}) =>
    screenReaderOn && narrating;
