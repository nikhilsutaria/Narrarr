package dev.narrarr.narrarr

import io.flutter.embedding.android.FlutterFragmentActivity

// flutter_readium's ReadiumReaderWidget casts the host Activity to a
// FragmentActivity, so the app must use FlutterFragmentActivity (not the
// default FlutterActivity). See docs/poc/04-reader-spike-findings.md §B.
class MainActivity : FlutterFragmentActivity()
