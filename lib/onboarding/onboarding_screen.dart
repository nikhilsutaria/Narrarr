import 'package:flutter/material.dart';

/// First-run intro: what Narrarr is and the privacy promise. Single screen with
/// a clear primary action.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome to Narrarr', style: text.headlineMedium),
              const SizedBox(height: 16),
              Text(
                'Read your own EPUBs while an offline neural voice reads along, '
                'highlighting each sentence. Pocket your phone and just listen '
                'with lock-screen controls.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'Fully offline. No account. No telemetry. Nothing leaves your '
                'device.',
                style: text.bodyLarge,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onDone,
                  child: const Text('Get started'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
