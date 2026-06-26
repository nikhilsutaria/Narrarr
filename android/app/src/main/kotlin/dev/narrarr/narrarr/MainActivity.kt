package dev.narrarr.narrarr

import com.ryanheise.audioservice.AudioServiceFragmentActivity

// Two host-Activity constraints must both hold:
//  - flutter_readium's ReadiumReaderWidget casts the host Activity to a
//    FragmentActivity, so it must extend FlutterFragmentActivity (not the
//    default FlutterActivity). See docs/poc/04-reader-spike-findings.md §B.
//  - audio_service requires the Activity to be its own AudioServiceActivity
//    subclass, or AudioService.init throws "The Activity class declared in
//    your AndroidManifest.xml is wrong".
// AudioServiceFragmentActivity extends FlutterFragmentActivity, satisfying both.
class MainActivity : AudioServiceFragmentActivity()
