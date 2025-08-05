import 'package:flutter/material.dart';

class LoadingWidget extends StatelessWidget {
  final String? message;
  final String? secondaryMessage;
  const LoadingWidget({super.key, this.message, this.secondaryMessage});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator.adaptive(),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(message!, style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white)),
              ],
              if (secondaryMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  secondaryMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
