import 'package:flutter/material.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';

class MeditationGuideCard extends StatelessWidget {
  final MeditationGuide guide;
  final VoidCallback onTap;
  final VoidCallback onToggleCompletion;
  final VoidCallback? onDelete;

  const MeditationGuideCard({
    super.key,
    required this.guide,
    required this.onTap,
    required this.onToggleCompletion,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: guide.isCompleted
            ? Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), width: 2)
            : null,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Type icon and completion status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guide.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: guide.isCompleted ? Colors.grey.shade600 : Colors.black87,
                          decoration: guide.isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              guide.type,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            '${guide.durationMinutes} min',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      if (guide.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          guide.description,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Actions
                Column(
                  children: [
                    // Completion toggle
                    IconButton(
                      onPressed: onToggleCompletion,
                      icon: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: guide.isCompleted
                              ? Theme.of(context).colorScheme.primary
                              : _getTypeColor(context).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          guide.isCompleted ? Icons.check : _getTypeIcon(),
                          color: guide.isCompleted ? Colors.white : _getTypeColor(context),
                          size: 22,
                        ),
                      ),
                    ),
                    if (onDelete != null)
                      IconButton(
                        onPressed: onDelete,
                        icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(BuildContext context) {
    switch (guide.type.toLowerCase()) {
      case 'mindfulness':
        return Theme.of(context).colorScheme.primary;
      case 'body scanning':
        return Colors.purple;
      case 'loving kindness':
        return Colors.pink;
      case 'breathwork':
        return Colors.blue;
      case 'visualization':
        return Colors.orange;
      case 'walking meditation':
        return Colors.green;
      case 'mantra':
        return Colors.indigo;
      case 'beginner friendly':
        return Theme.of(context).colorScheme.primary;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  IconData _getTypeIcon() {
    switch (guide.type.toLowerCase()) {
      case 'mindfulness':
        return Icons.self_improvement;
      case 'body scanning':
        return Icons.accessibility_new;
      case 'loving kindness':
        return Icons.favorite;
      case 'breathwork':
        return Icons.air;
      case 'visualization':
        return Icons.visibility;
      case 'walking meditation':
        return Icons.directions_walk;
      case 'mantra':
        return Icons.record_voice_over;
      case 'beginner friendly':
        return Icons.stars;
      default:
        return Icons.self_improvement;
    }
  }
}
