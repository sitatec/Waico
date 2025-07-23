import 'package:flutter/material.dart';

class SetupProgressIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final List<String> stepTitles;

  const SetupProgressIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.stepTitles,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // Progress bar
        Container(
          height: 4,
          decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (currentStep + 1) / totalSteps,
            child: Container(
              decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(2)),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Step indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(totalSteps, (index) {
            final isActive = index == currentStep;
            final isCompleted = index < currentStep;

            return Expanded(
              child: Column(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted
                          ? theme.colorScheme.primary
                          : isActive
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: isActive || isCompleted ? theme.colorScheme.primary : Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      isCompleted
                          ? Icons.check
                          : isActive
                          ? Icons.circle
                          : Icons.circle_outlined,
                      color: isCompleted || isActive ? Colors.white : Colors.grey.shade400,
                      size: isActive ? 10 : 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stepTitles[index],
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isActive || isCompleted ? theme.colorScheme.primary : Colors.grey.shade600,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}
