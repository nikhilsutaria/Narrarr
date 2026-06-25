import 'package:flutter/material.dart';

import 'library/library_screen.dart';
import 'onboarding/onboarding_screen.dart';
import 'onboarding/onboarding_store.dart';
import 'ui/theme.dart';

/// Root widget for Narrarr.
class NarrarrApp extends StatelessWidget {
  const NarrarrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Narrarr',
      debugShowCheckedModeBanner: false,
      theme: narrarrLightTheme,
      darkTheme: narrarrDarkTheme,
      home: const _RootGate(),
    );
  }
}

/// Shows onboarding on first run, then the library.
class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  final _store = OnboardingStore();
  bool? _seen;

  @override
  void initState() {
    super.initState();
    _store.seen().then((v) {
      if (mounted) setState(() => _seen = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_seen == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_seen == false) {
      return OnboardingScreen(onDone: () async {
        await _store.markSeen();
        if (mounted) setState(() => _seen = true);
      });
    }
    return const LibraryScreen();
  }
}
