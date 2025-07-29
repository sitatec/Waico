import 'package:flutter/material.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';

class MeditationTypeCard extends StatelessWidget {
  final MeditationType type;
  final VoidCallback onTap;

  const MeditationTypeCard({super.key, required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getTypeColor(context).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_getTypeIcon(), color: _getTypeColor(context), size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Text(type.description, style: TextStyle(fontSize: 14, color: Colors.grey.shade600, height: 1.3)),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: Colors.grey.shade400, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(BuildContext context) {
    switch (type) {
      case MeditationType.mindfulness:
        return Theme.of(context).colorScheme.primary;
      case MeditationType.bodyScanning:
        return Colors.purple;
      case MeditationType.lovingKindness:
        return Colors.pink;
      case MeditationType.breathwork:
        return Colors.blue;
      case MeditationType.visualization:
        return Colors.orange;
      case MeditationType.walking:
        return Colors.green;
      case MeditationType.mantra:
        return Colors.indigo;
      case MeditationType.beginner:
        return Theme.of(context).colorScheme.primary;
    }
  }

  IconData _getTypeIcon() {
    switch (type) {
      case MeditationType.mindfulness:
        return Icons.self_improvement;
      case MeditationType.bodyScanning:
        return Icons.accessibility_new;
      case MeditationType.lovingKindness:
        return Icons.favorite;
      case MeditationType.breathwork:
        return Icons.air;
      case MeditationType.visualization:
        return Icons.visibility;
      case MeditationType.walking:
        return Icons.directions_walk;
      case MeditationType.mantra:
        return Icons.record_voice_over;
      case MeditationType.beginner:
        return Icons.stars;
    }
  }
}
