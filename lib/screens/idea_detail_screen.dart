import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/comment.dart';
import '../models/feature.dart';
import '../models/idea.dart';
import '../models/reply.dart';
import '../services/comments_service.dart';
import '../services/ideas_service.dart';
import 'idea_form_screen.dart';

/// Extension to capitalize first letter of a string
extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

/// Screen displaying full idea details
class IdeaDetailScreen extends StatefulWidget {
  final String ideaId;
  final bool isReadOnly;
  final Idea? publicIdea;

  const IdeaDetailScreen({
    super.key,
    required this.ideaId,
    this.isReadOnly = false,
    this.publicIdea,
  });

  @override
  State<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends State<IdeaDetailScreen> {
  final IdeasService _ideasService = IdeasService();
  final CommentsService _commentsService = CommentsService();
  late Stream<Idea?> _ideaStream;
  final TextEditingController _commentController = TextEditingController();
  CommentType _selectedCommentType = CommentType.comment;
  bool _isSubmittingComment = false;

  @override
  void initState() {
    super.initState();
    _ideaStream = _ideasService.streamIdea(widget.ideaId);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment(Idea idea) async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSubmittingComment = true);

    final success = await _commentsService.addComment(
      ideaId: idea.id,
      ideaName: idea.name,
      ideaOwnerId: idea.ownerId ?? '',
      type: _selectedCommentType,
      content: content,
    );

    if (mounted) {
      setState(() => _isSubmittingComment = false);
      if (success) {
        _commentController.clear();
        // No need to reload - StreamBuilder handles updates automatically
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selectedCommentType.name.capitalize()} added!'),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to add comment')));
      }
    }
  }

  IconData _getTypeIcon(Idea? idea) {
    switch (idea?.type) {
      case IdeaType.website:
        return Icons.language;
      case IdeaType.mobile:
        return Icons.phone_android;
      case IdeaType.both:
        return Icons.devices;
      default:
        return Icons.lightbulb;
    }
  }

  Color _getTypeColor(Idea? idea) {
    switch (idea?.type) {
      case IdeaType.website:
        return Colors.blue;
      case IdeaType.mobile:
        return Colors.purple;
      case IdeaType.both:
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  /// Build a visual chip showing the current stage
  Widget _buildStageChip(IdeaStage stage) {
    final (String label, Color color, IconData icon) = switch (stage) {
      IdeaStage.ideation => ('Ideation', Colors.amber, Icons.lightbulb_outline),
      IdeaStage.implementation => (
        'Building',
        Colors.orange,
        Icons.build_outlined,
      ),
      IdeaStage.completed => ('Done', Colors.green, Icons.check_circle_outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToEdit(Idea? idea) async {
    if (idea == null || widget.isReadOnly) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => IdeaFormScreen(idea: idea)),
    );
    // Real-time stream handles the updates
  }

  Future<void> _deleteIdea(Idea? idea) async {
    if (widget.isReadOnly || idea == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Idea'),
        content: Text('Are you sure you want to delete "${idea.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _ideasService.deleteIdea(idea.id);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${idea.name} deleted'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete idea'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showQuickAddFeatureDialog(Idea? idea) {
    if (widget.isReadOnly || idea == null) return;

    final nameController = TextEditingController();
    final descController = TextEditingController();
    final nameFocusNode = FocusNode();
    Priority selectedPriority = Priority.medium;
    final uuid = const Uuid();
    bool isNameEmpty = true;
    int addedCount = 0;

    // Collect features locally, sync to Firestore only when dialog closes
    final List<Feature> newFeatures = [];

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismiss
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void addFeature() {
            final feature = Feature(
              id: uuid.v4(),
              name: nameController.text.trim(),
              description: descController.text.trim(),
              priority: selectedPriority,
              // Status defaults to backlog for new features
            );

            // Add to local list
            newFeatures.add(feature);

            // Haptic feedback
            HapticFeedback.lightImpact();

            // Clear inputs for next entry
            nameController.clear();
            descController.clear();
            setDialogState(() {
              selectedPriority = Priority.medium;
              isNameEmpty = true;
              addedCount++;
            });

            // Re-focus name field
            nameFocusNode.requestFocus();
          }

          void closeDialog() async {
            // Auto-add pending feature if name is filled
            final pendingName = nameController.text.trim();
            if (pendingName.isNotEmpty) {
              final pendingFeature = Feature(
                id: uuid.v4(),
                name: pendingName,
                description: descController.text.trim(),
                priority: selectedPriority,
              );
              newFeatures.add(pendingFeature);
            }

            // Save all new features to Firestore
            if (newFeatures.isNotEmpty) {
              final updatedFeatures = List<Feature>.from(idea.features)
                ..addAll(newFeatures);
              final updatedIdea = idea.copyWith(
                features: updatedFeatures,
                updatedAt: DateTime.now(),
              );

              try {
                await _ideasService.saveIdea(updatedIdea);
                // Real-time stream handles updates

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${newFeatures.length} feature${newFeatures.length > 1 ? 's' : ''} added!',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to add features'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }

            nameFocusNode.dispose();
            Navigator.pop(dialogContext);
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: Theme.of(dialogContext).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text('Add Features'),
              ],
            ),
            content: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(dialogContext).viewInsets.bottom > 0
                      ? 16
                      : 0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Feature name with helper text
                    TextField(
                      controller: nameController,
                      focusNode: nameFocusNode,
                      decoration: const InputDecoration(
                        labelText: 'Feature name',
                        hintText: 'e.g. User login, Dark mode',
                        helperText: 'One small capability of your idea',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (value) {
                        final empty = value.trim().isEmpty;
                        if (empty != isNameEmpty) {
                          setDialogState(() => isNameEmpty = empty);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Description field
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'What does this feature do?',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),

                    // Priority selector
                    const Text('Priority'),
                    const SizedBox(height: 8),
                    Center(
                      child: ToggleButtons(
                        borderRadius: BorderRadius.circular(20),
                        isSelected: [
                          selectedPriority == Priority.low,
                          selectedPriority == Priority.medium,
                          selectedPriority == Priority.high,
                        ],
                        onPressed: (index) {
                          setDialogState(() {
                            selectedPriority = Priority.values[index];
                          });
                        },
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_downward, size: 16),
                                SizedBox(width: 4),
                                Text('Low'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: 16),
                                SizedBox(width: 4),
                                Text('Med'),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.arrow_upward, size: 16),
                                SizedBox(width: 4),
                                Text('High'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: closeDialog,
                child: Text(addedCount > 0 ? 'Done' : 'Cancel'),
              ),
              FilledButton.icon(
                onPressed: isNameEmpty ? null : addFeature,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Build Kanban-style grouped features for Implementation stage
  Widget _buildKanbanFeatures(Idea idea) {
    final backlog = idea.features
        .where((f) => f.status == FeatureStatus.backlog)
        .toList();
    final inProgress = idea.features
        .where((f) => f.status == FeatureStatus.inProgress)
        .toList();
    final completed = idea.features
        .where((f) => f.status == FeatureStatus.done)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFeatureSection(
          title: 'Backlog',
          icon: Icons.inbox_outlined,
          features: backlog,
          color: Colors.grey.shade600,
          idea: idea,
        ),
        _buildFeatureSection(
          title: 'In Progress',
          icon: Icons.autorenew,
          features: inProgress,
          color: Colors.orange,
          idea: idea,
        ),
        _buildFeatureSection(
          title: 'Completed',
          icon: Icons.check_circle,
          features: completed,
          color: Colors.green,
          idea: idea,
          isCompleted: true,
        ),
      ],
    );
  }

  /// Build a feature section with header and list
  Widget _buildFeatureSection({
    required String title,
    required IconData icon,
    required List<Feature> features,
    required Color color,
    required Idea idea,
    bool isCompleted = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              '$title (${features.length})',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (features.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 8),
            child: Text(
              'No features',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          ...features.map(
            (f) => _buildFeatureCard(
              feature: f,
              idea: idea,
              isCompleted: isCompleted,
            ),
          ),
      ],
    );
  }

  /// Build a single feature card with popup menu for status changes
  Widget _buildFeatureCard({
    required Feature feature,
    required Idea idea,
    bool isCompleted = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isCompleted ? Colors.grey.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isCompleted)
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.green.shade400,
                        ),
                      if (isCompleted) const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          feature.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: isCompleted ? Colors.grey.shade500 : null,
                          ),
                        ),
                      ),
                      // Priority indicator
                      _buildPriorityIndicator(feature.priority),
                    ],
                  ),
                  if (feature.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      feature.description,
                      style: TextStyle(
                        color: isCompleted
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Status change popup (not for read-only or completed ideas)
            if (!widget.isReadOnly && idea.stage != IdeaStage.completed)
              PopupMenuButton<FeatureStatus>(
                icon: Icon(Icons.more_vert, color: Colors.grey.shade400),
                onSelected: (status) =>
                    _updateFeatureStatus(idea.id, feature.id, status),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: FeatureStatus.backlog,
                    enabled: feature.status != FeatureStatus.backlog,
                    child: const Row(
                      children: [
                        Icon(Icons.inbox_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Move to Backlog'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: FeatureStatus.inProgress,
                    enabled: feature.status != FeatureStatus.inProgress,
                    child: const Row(
                      children: [
                        Icon(Icons.autorenew, size: 18),
                        SizedBox(width: 8),
                        Text('Move to In Progress'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: FeatureStatus.done,
                    enabled: feature.status != FeatureStatus.done,
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, size: 18),
                        SizedBox(width: 8),
                        Text('Mark as Done'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Build priority indicator chip
  Widget _buildPriorityIndicator(Priority priority) {
    final (Color color, String label) = switch (priority) {
      Priority.low => (Colors.blue.shade300, '↓'),
      Priority.medium => (Colors.amber.shade400, '●'),
      Priority.high => (Colors.red.shade400, '↑'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Update feature status
  Future<void> _updateFeatureStatus(
    String ideaId,
    String featureId,
    FeatureStatus status,
  ) async {
    try {
      await _ideasService.updateFeatureStatus(
        ideaId: ideaId,
        featureId: featureId,
        status: status,
      );
      // Real-time stream handles updates

      if (mounted) {
        final statusName = switch (status) {
          FeatureStatus.backlog => 'Backlog',
          FeatureStatus.inProgress => 'In Progress',
          FeatureStatus.done => 'Completed',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Moved to $statusName'),
            backgroundColor: switch (status) {
              FeatureStatus.backlog => Colors.grey,
              FeatureStatus.inProgress => Colors.orange,
              FeatureStatus.done => Colors.green,
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update feature'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Build standard features list (for Ideation and Completed stages)
  Widget _buildStandardFeaturesList(Idea idea) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: idea.features.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final feature = idea.features[index];
        final isCompleted = idea.stage == IdeaStage.completed;
        return Card(
          color: isCompleted ? Colors.grey.shade50 : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              feature.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: isCompleted
                                    ? Colors.grey.shade500
                                    : null,
                              ),
                            ),
                          ),
                          _buildPriorityIndicator(feature.priority),
                        ],
                      ),
                      if (feature.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          feature.description,
                          style: TextStyle(
                            color: isCompleted
                                ? Colors.grey.shade400
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Idea?>(
      stream: _ideaStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final idea = snapshot.data;
        if (idea == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Idea not found')),
          );
        }

        final typeColor = _getTypeColor(idea);

        return Scaffold(
          appBar: AppBar(
            title: Text(idea.name),
            actions: widget.isReadOnly
                ? null
                : [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _navigateToEdit(idea),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteIdea(idea),
                    ),
                  ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        typeColor.withValues(alpha: 0.2),
                        typeColor.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _getTypeIcon(idea),
                          color: typeColor,
                          size: 40,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  idea.typeDisplayName,
                                  style: TextStyle(
                                    color: typeColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                // Stage indicator chip
                                _buildStageChip(idea.stage),
                                if (idea.isPublic)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.public,
                                          size: 14,
                                          color: Colors.green.shade700,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Public',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (widget.isReadOnly && idea.ownerName != null)
                              Text(
                                'by ${idea.ownerName}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              )
                            else
                              Text(
                                'Created: ${_formatDate(idea.createdAt)}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Description
                if (idea.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Description',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          idea.description,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),

                // Features
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Features',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (!widget.isReadOnly &&
                                  idea.stage != IdeaStage.completed) ...[
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  onPressed: () =>
                                      _showQuickAddFeatureDialog(idea),
                                  icon: const Icon(Icons.add, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Quick add feature',
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '${idea.features.length} features',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (idea.features.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.featured_play_list_outlined,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No features added yet',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        )
                      // Kanban-style view for Implementation stage
                      else if (idea.stage == IdeaStage.implementation)
                        _buildKanbanFeatures(idea)
                      // Standard list for Ideation stage
                      else
                        _buildStandardFeaturesList(idea),
                    ],
                  ),
                ),

                // Comments section (for public ideas OR read-only view)
                // This allows notifications to always navigate to My Ideas screen
                if (widget.isReadOnly || idea.isPublic)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
                        const SizedBox(height: 8),
                        // Header with real-time count via StreamBuilder
                        StreamBuilder<List<Comment>>(
                          stream: _commentsService.streamComments(
                            widget.ideaId,
                          ),
                          builder: (context, snapshot) {
                            final count = snapshot.data?.length ?? 0;
                            return Row(
                              children: [
                                Text(
                                  'Comments & Feedback',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '($count)',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Comment input
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Type selector
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Type',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Animated Comment Type Selector
                                    Container(
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          final totalWidth =
                                              constraints.maxWidth;
                                          final availableWidth =
                                              totalWidth - 8; // gaps
                                          final selectedWidth =
                                              availableWidth * 0.5;
                                          final unselectedWidth =
                                              availableWidth * 0.25;

                                          return Row(
                                            children: [
                                              _buildAnimatedCommentTab(
                                                label: 'Comment',
                                                icon: Icons.chat_bubble_outline,
                                                type: CommentType.comment,
                                                width:
                                                    _selectedCommentType ==
                                                        CommentType.comment
                                                    ? selectedWidth
                                                    : unselectedWidth,
                                                color: Colors.blue,
                                              ),
                                              const SizedBox(width: 4),
                                              _buildAnimatedCommentTab(
                                                label: 'Idea',
                                                icon: Icons.lightbulb_outline,
                                                type: CommentType.suggestion,
                                                width:
                                                    _selectedCommentType ==
                                                        CommentType.suggestion
                                                    ? selectedWidth
                                                    : unselectedWidth,
                                                color: Colors.orange,
                                              ),
                                              const SizedBox(width: 4),
                                              _buildAnimatedCommentTab(
                                                label: 'Question',
                                                icon: Icons.help_outline,
                                                type: CommentType.question,
                                                width:
                                                    _selectedCommentType ==
                                                        CommentType.question
                                                    ? selectedWidth
                                                    : unselectedWidth,
                                                color: Colors.purple,
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Text input
                                TextField(
                                  controller: _commentController,
                                  decoration: InputDecoration(
                                    hintText:
                                        'Write a ${_selectedCommentType.name}...',
                                    border: const OutlineInputBorder(),
                                    suffixIcon: _isSubmittingComment
                                        ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                        : IconButton(
                                            icon: const Icon(Icons.send),
                                            onPressed: () =>
                                                _submitComment(idea),
                                          ),
                                  ),
                                  maxLines: 3,
                                  minLines: 1,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Comments list with StreamBuilder for real-time updates
                        StreamBuilder<List<Comment>>(
                          stream: _commentsService.streamComments(
                            widget.ideaId,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final comments = snapshot.data ?? [];

                            if (comments.isEmpty) {
                              return Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.chat_bubble_outline,
                                        size: 48,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No comments yet',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Be the first to share your thoughts!',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: comments.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final comment = comments[index];
                                return _CommentTileWithReplies(
                                  comment: comment,
                                  ideaId: widget.ideaId,
                                  ideaOwnerId: idea.ownerId ?? '',
                                  ideaName: idea.name,
                                  commentsService: _commentsService,
                                  formatDate: _formatDate,
                                  getCommentTypeColor: _getCommentTypeColor,
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Stage Action Button (only for owned ideas, not read-only)
          bottomNavigationBar: widget.isReadOnly
              ? null
              : _buildStageActionBar(idea),
        );
      },
    );
  }

  /// Build the stage action bar at the bottom
  Widget? _buildStageActionBar(Idea idea) {
    if (widget.isReadOnly) return null;

    final stageInfo = _getStageActionInfo(idea.stage);
    if (stageInfo == null) return null; // No action available for completed

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: ElevatedButton.icon(
          onPressed: () => _showStageConfirmationDialog(idea, stageInfo),
          style: ElevatedButton.styleFrom(
            backgroundColor: stageInfo['color'] as Color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: Icon(stageInfo['icon'] as IconData),
          label: Text(
            stageInfo['buttonText'] as String,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  /// Get stage action info based on current stage
  Map<String, dynamic>? _getStageActionInfo(IdeaStage currentStage) {
    switch (currentStage) {
      case IdeaStage.ideation:
        return {
          'buttonText': 'Start Building',
          'dialogTitle': 'Move to Build Stage?',
          'dialogContent':
              'This will transition your idea into active development. You\'ll focus on building and executing your features.',
          'nextStage': IdeaStage.implementation,
          'icon': Icons.rocket_launch_outlined,
          'color': Colors.orange,
          'successMessage': 'Moved to Build Stage!',
        };
      case IdeaStage.implementation:
        return {
          'buttonText': 'Mark as Done',
          'dialogTitle': 'Complete this Project?',
          'dialogContent':
              'Congratulations! This will mark your idea as finished. You can still view it in the Done tab.',
          'nextStage': IdeaStage.completed,
          'icon': Icons.check_circle_outline,
          'color': Colors.green,
          'successMessage': 'Project marked as Done!',
        };
      case IdeaStage.completed:
        return null; // No further action for completed ideas
    }
  }

  Future<void> _showStageConfirmationDialog(
    Idea idea,
    Map<String, dynamic> stageInfo,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              stageInfo['icon'] as IconData,
              color: stageInfo['color'] as Color,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(stageInfo['dialogTitle'] as String)),
          ],
        ),
        content: Text(stageInfo['dialogContent'] as String),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: stageInfo['color'] as Color,
              foregroundColor: Colors.white,
            ),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _executeStageTransition(idea, stageInfo);
    }
  }

  /// Execute the stage transition
  Future<void> _executeStageTransition(
    Idea idea,
    Map<String, dynamic> stageInfo,
  ) async {
    try {
      await _ideasService.updateIdeaStage(
        ideaId: idea.id,
        stage: stageInfo['nextStage'] as IdeaStage,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(stageInfo['successMessage'] as String),
          backgroundColor: stageInfo['color'] as Color,
        ),
      );

      Navigator.pop(context); // Go back to list
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update idea stage'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _getCommentTypeColor(CommentType type) {
    switch (type) {
      case CommentType.comment:
        return Colors.blue;
      case CommentType.suggestion:
        return Colors.orange;
      case CommentType.question:
        return Colors.purple;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildAnimatedCommentTab({
    required String label,
    required IconData icon,
    required CommentType type,
    required double width,
    required Color color,
  }) {
    final isSelected = _selectedCommentType == type;
    return GestureDetector(
      onTap: () {
        if (_selectedCommentType != type) {
          setState(() => _selectedCommentType = type);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: width,
        height: 40,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? color
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Widget for displaying a comment with expandable replies
class _CommentTileWithReplies extends StatefulWidget {
  final Comment comment;
  final String ideaId;
  final String ideaOwnerId;
  final String ideaName;
  final CommentsService commentsService;
  final String Function(DateTime) formatDate;
  final Color Function(CommentType) getCommentTypeColor;

  const _CommentTileWithReplies({
    required this.comment,
    required this.ideaId,
    required this.ideaOwnerId,
    required this.ideaName,
    required this.commentsService,
    required this.formatDate,
    required this.getCommentTypeColor,
  });

  @override
  State<_CommentTileWithReplies> createState() =>
      _CommentTileWithRepliesState();
}

class _CommentTileWithRepliesState extends State<_CommentTileWithReplies> {
  bool _showReplies = false;
  bool _showReplyInput = false;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  bool _isSubmitting = false;
  int _actualReplyCount = 0;
  late final Stream<List<Reply>> _repliesStream;

  @override
  void initState() {
    super.initState();
    // Initialize with stored count
    _actualReplyCount = widget.comment.replyCount;

    // Listen to replies stream to always get accurate count
    _repliesStream = widget.commentsService.streamReplies(
      widget.ideaId,
      widget.comment.id,
    );
    _repliesStream.listen((replies) {
      if (mounted && _actualReplyCount != replies.length) {
        setState(() => _actualReplyCount = replies.length);
      }
    });
  }

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;
    if (_isSubmitting) return; // Prevent double-tap

    setState(() => _isSubmitting = true);

    try {
      final success = await widget.commentsService.addReply(
        ideaId: widget.ideaId,
        commentId: widget.comment.id,
        commentAuthorId: widget.comment.authorId,
        ideaOwnerId: widget.ideaOwnerId,
        ideaName: widget.ideaName,
        content: content,
      );

      if (mounted) {
        if (success) {
          _replyController.clear();
          FocusScope.of(context).unfocus();
          setState(() {
            _showReplyInput = false;
            _showReplies = true;
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Reply added!')));
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to send reply')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key('swipe-${widget.comment.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        // Swipe to trigger reply mode (don't actually dismiss)
        HapticFeedback.lightImpact();
        setState(() {
          _showReplyInput = true;
          _showReplies = true;
        });
        // Focus the reply input after a short delay
        Future.delayed(const Duration(milliseconds: 100), () {
          _replyFocusNode.requestFocus();
        });
        return false; // Never dismiss
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(Icons.reply, color: Theme.of(context).colorScheme.primary),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Comment header
              Row(
                children: [
                  Icon(
                    widget.comment.typeIcon,
                    size: 18,
                    color: widget.getCommentTypeColor(widget.comment.type),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.comment.authorName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.formatDate(widget.comment.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.getCommentTypeColor(widget.comment.type),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.comment.typeDisplayName,
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ),
                  // Reply count badge
                  if (_actualReplyCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.reply,
                            size: 12,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '$_actualReplyCount',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              // Comment content
              Text(widget.comment.content),
              const SizedBox(height: 8),
              // Reply actions row
              Row(
                children: [
                  // View/hide replies button
                  if (_actualReplyCount > 0)
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showReplies = !_showReplies),
                      icon: Icon(
                        _showReplies ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                      label: Text(
                        _showReplies
                            ? 'Hide replies'
                            : 'View $_actualReplyCount ${_actualReplyCount == 1 ? 'reply' : 'replies'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  const Spacer(),
                  // Reply button
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _showReplyInput = !_showReplyInput;
                      // Always show replies section when opening reply input
                      if (_showReplyInput) {
                        _showReplies = true;
                      }
                    }),
                    icon: const Icon(Icons.reply, size: 18),
                    label: const Text('Reply', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              // Replies list (expandable)
              if (_showReplies)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 8),
                  child: StreamBuilder<List<Reply>>(
                    stream: widget.commentsService.streamReplies(
                      widget.ideaId,
                      widget.comment.id,
                    ),
                    builder: (context, snapshot) {
                      final replies = snapshot.data ?? [];
                      // Update actual count for the badge
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _actualReplyCount != replies.length) {
                          setState(() => _actualReplyCount = replies.length);
                        }
                      });
                      if (replies.isEmpty) {
                        return Text(
                          'No replies yet',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                        );
                      }
                      return Column(
                        children: replies
                            .map(
                              (reply) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.subdirectory_arrow_right,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  reply.authorName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  widget.formatDate(
                                                    reply.createdAt,
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey.shade500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              reply.content,
                                              style: const TextStyle(
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ),
              // Reply input (animated)
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: _showReplyInput
                    ? Padding(
                        padding: const EdgeInsets.only(left: 24, top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _replyController,
                                focusNode: _replyFocusNode,
                                decoration: const InputDecoration(
                                  hintText: 'Write a reply...',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                maxLines: 2,
                                minLines: 1,
                                textCapitalization:
                                    TextCapitalization.sentences,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _isSubmitting
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : IconButton(
                                    onPressed: _submitReply,
                                    icon: const Icon(Icons.send),
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ), // Card
    ); // Dismissible
  }
}
