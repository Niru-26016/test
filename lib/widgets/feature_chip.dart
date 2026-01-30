import 'package:flutter/material.dart';
import '../models/feature.dart';

/// A chip widget displaying a feature with priority-based coloring
class FeatureChip extends StatelessWidget {
  final Feature feature;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const FeatureChip({
    super.key,
    required this.feature,
    this.onTap,
    this.onDelete,
  });

  Color _getPriorityColor(BuildContext context) {
    switch (feature.priority) {
      case Priority.high:
        return Colors.red.shade400;
      case Priority.medium:
        return Colors.orange.shade400;
      case Priority.low:
        return Colors.green.shade400;
    }
  }

  IconData _getPriorityIcon() {
    switch (feature.priority) {
      case Priority.high:
        return Icons.keyboard_arrow_up;
      case Priority.medium:
        return Icons.remove;
      case Priority.low:
        return Icons.keyboard_arrow_down;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getPriorityColor(context);

    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getPriorityIcon(), size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  feature.name,
                  style: TextStyle(color: color, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(Icons.close, size: 16, color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
