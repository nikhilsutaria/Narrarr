import 'package:flutter/material.dart';

import 'library/library_screen.dart';
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
      home: const LibraryScreen(),
    );
  }
}
