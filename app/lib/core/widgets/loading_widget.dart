import 'package:flutter/material.dart';

class LoadingWidget extends StatelessWidget {
  final String? message;
  const LoadingWidget({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator.adaptive(),
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(message!, style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white)),
            ],
          ],
        ),
      ),
    );
  }
}
