import 'package:flutter/material.dart';

import 'reader/reader_screen.dart';

/// Root widget for Narrarr.
class NarrarrApp extends StatelessWidget {
  const NarrarrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Narrarr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B4FE0),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF5B4FE0),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      // v0.1 opens straight into the reader on a bundled book. The library /
      // import flow becomes the home screen in Phase 1.
      home: const ReaderScreen(),
    );
  }
}
