import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/group_idea.dart';
import '../models/feature.dart';
import '../models/group.dart';
import '../services/group_ideas_service.dart';
import '../services/groups_service.dart';

/// Screen showing group idea details with features
class GroupIdeaDetailScreen extends StatefulWidget {
  final String groupId;
  final String ideaId;

  const GroupIdeaDetailScreen({
    super.key,
    required this.groupId,
    required this.ideaId,
  });

  @override
  State<GroupIdeaDetailScreen> createState() => _GroupIdeaDetailScreenState();
}

class _GroupIdeaDetailScreenState extends State<GroupIdeaDetailScreen> {
  final GroupIdeasService _ideasService = GroupIdeasService();
  final GroupsService _groupsService = GroupsService();

  late Stream<GroupIdea?> _ideaStream;
  late Stream<GroupRole?> _roleStream;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    _ideaStream = _ideasService.streamGroupIdeaById(
      widget.groupId,
      widget.ideaId,
    );
    _roleStream = _groupsService.streamUserRole(widget.groupId);
  }

  void _showStatusChangeMenu(Feature feature) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                'Move Feature: ${feature.name}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.hourglass_empty, color: Colors.orange),
              title: const Text('Move to Waiting (Backlog)'),
              subtitle: const Text('Ready for team members to pick up'),
              enabled: feature.status != FeatureStatus.backlog,
              onTap: () async {
                Navigator.pop(context);
                await _ideasService.updateFeatureStatus(
                  groupId: widget.groupId,
                  ideaId: widget.ideaId,
                  featureId: feature.id,
                  status: FeatureStatus.backlog,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.autorenew, color: Colors.blue),
              title: const Text('Move to Execution (In Progress)'),
              subtitle: const Text('Currently being worked on'),
              enabled: feature.status != FeatureStatus.inProgress,
              onTap: () async {
                Navigator.pop(context);
                await _ideasService.updateFeatureStatus(
                  groupId: widget.groupId,
                  ideaId: widget.ideaId,
                  featureId: feature.id,
                  status: FeatureStatus.inProgress,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('Move to Done (Completed)'),
              subtitle: const Text('Feature is implemented and verified'),
              enabled: feature.status != FeatureStatus.done,
              onTap: () async {
                Navigator.pop(context);
                await _ideasService.updateFeatureStatus(
                  groupId: widget.groupId,
                  ideaId: widget.ideaId,
                  featureId: feature.id,
                  status: FeatureStatus.done,
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showAddFeatureDialog(bool ideaIsApproved) {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Feature'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Feature Name *',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(ctx);

              final feature = await _ideasService.addFeature(
                groupId: widget.groupId,
                ideaId: widget.ideaId,
                name: name,
                description: descController.text.trim(),
              );

              if (mounted && feature != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ideaIsApproved
                          ? 'Feature added (pending approval)'
                          : 'Feature added!',
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to add feature. Please try again.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GroupRole?>(
      stream: _roleStream,
      builder: (context, roleSnapshot) {
        final role = roleSnapshot.data;
        final isAdmin = role == GroupRole.owner || role == GroupRole.admin;

        return StreamBuilder<GroupIdea?>(
          stream: _ideaStream,
          builder: (context, ideaSnapshot) {
            if (ideaSnapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                appBar: AppBar(title: const Text('Idea Details')),
                body: const Center(child: CircularProgressIndicator()),
              );
            }

            final idea = ideaSnapshot.data;
            if (idea == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Idea Details')),
                body: const Center(child: Text('Idea not found')),
              );
            }

            return Scaffold(
              appBar: AppBar(
                title: const Text('Idea Details'),
                actions: [
                  if (isAdmin ||
                      (idea.authorId == _ideasService.userId &&
                          !idea.isApproved))
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: 'Delete Idea',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Idea?'),
                            content: const Text(
                              'Are you sure you want to delete this idea? This action cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true && mounted) {
                          final success = await _ideasService.deleteGroupIdea(
                            widget.groupId,
                            widget.ideaId,
                          );
                          if (mounted) {
                            if (success) {
                              Navigator.pop(context); // Close detail screen
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to delete idea'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Idea Header
                    _buildIdeaHeader(idea, isAdmin),
                    const SizedBox(height: 24),

                    // Features Section
                    _buildFeaturesSection(idea, isAdmin),
                  ],
                ),
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _showAddFeatureDialog(idea.isApproved),
                icon: const Icon(Icons.add),
                label: const Text('Add Feature'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildIdeaHeader(GroupIdea idea, bool isAdmin) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    idea.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Status badge
                if (!idea.isApproved)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_empty,
                          size: 14,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Pending',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (idea.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                idea.description,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.person, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  'by ${idea.authorName}',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
                const Spacer(),
                // Upvote button with real-time vote status (Animated)
                StreamBuilder<bool>(
                  stream: _ideasService.streamUserVoteStatus(
                    widget.groupId,
                    widget.ideaId,
                  ),
                  builder: (context, voteSnapshot) {
                    final hasVoted = voteSnapshot.data ?? false;
                    return _AnimatedUpvoteButton(
                      count: idea.voteCount,
                      hasVoted: hasVoted,
                      onTap: () async {
                        await _ideasService.toggleVote(
                          widget.groupId,
                          widget.ideaId,
                        );
                      },
                      size: 16,
                    );
                  },
                ),
              ],
            ),
            // Admin approval button for unapproved ideas
            if (isAdmin && !idea.isApproved) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final success = await _ideasService.approveIdea(
                      widget.groupId,
                      widget.ideaId,
                    );
                    if (mounted && success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Idea approved!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Approve Idea'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesSection(GroupIdea idea, bool isAdmin) {
    // Use features directly from the idea
    final features = idea.features;

    final ideaIsApproved = idea.isApproved;

    // For not approved ideas - show simple list without tabs
    if (!ideaIsApproved) {
      return _buildSimpleFeatureList(features, ideaIsApproved, isAdmin);
    }

    // For approved ideas - show tabs
    final backlogFeatures = features
        .where((f) => f.status == FeatureStatus.backlog)
        .toList();
    final inProgressFeatures = features
        .where((f) => f.status == FeatureStatus.inProgress)
        .toList();
    final doneFeatures = features
        .where((f) => f.status == FeatureStatus.done)
        .toList();

    return DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.list_alt, size: 20),
              const SizedBox(width: 8),
              Text(
                'Features',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const TabBar(
              tabs: const [
                Tab(icon: Icon(Icons.hourglass_empty), text: 'Waiting'),
                Tab(icon: Icon(Icons.autorenew), text: 'Execution'),
                Tab(icon: Icon(Icons.check_circle), text: 'Done'),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: TabBarView(
              children: [
                _buildFeatureTabContent(
                  backlogFeatures,
                  ideaIsApproved,
                  isAdmin,
                ),
                _buildFeatureTabContent(
                  inProgressFeatures,
                  ideaIsApproved,
                  isAdmin,
                ),
                _buildFeatureTabContent(doneFeatures, ideaIsApproved, isAdmin),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleFeatureList(
    List<Feature> features,
    bool ideaIsApproved,
    bool isAdmin,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.list_alt, size: 20),
            const SizedBox(width: 8),
            Text(
              'Features',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'No approval needed',
                style: TextStyle(fontSize: 10, color: Colors.blue.shade700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (features.isEmpty)
          _buildEmptyFeatures()
        else
          Column(
            children: features
                .map((f) => _buildFeatureTile(f, ideaIsApproved, isAdmin))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildFeatureTabContent(
    List<Feature> features,
    bool ideaIsApproved,
    bool isAdmin,
  ) {
    if (features.isEmpty) {
      return Center(
        child: Text(
          'No features here',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: features
          .map((f) => _buildFeatureTile(f, ideaIsApproved, isAdmin))
          .toList(),
    );
  }

  Widget _buildEmptyFeatures() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.list_alt, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                'No features yet',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap + to add the first feature',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureTile(Feature feature, bool ideaIsApproved, bool isAdmin) {
    // Get status color and icon based on Feature's FeatureStatus enum
    final statusColor = switch (feature.status) {
      FeatureStatus.backlog => Colors.orange,
      FeatureStatus.inProgress => Colors.blue,
      FeatureStatus.done => Colors.green,
    };

    final statusIcon = switch (feature.status) {
      FeatureStatus.backlog => Icons.hourglass_empty,
      FeatureStatus.inProgress => Icons.autorenew,
      FeatureStatus.done => Icons.check_circle,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    feature.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                // Status badge
                GestureDetector(
                  onTap: (isAdmin && ideaIsApproved)
                      ? () => _showStatusChangeMenu(feature)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: (isAdmin && ideaIsApproved)
                          ? Border.all(color: statusColor.withOpacity(0.5))
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          feature.statusDisplayName,
                          style: TextStyle(color: statusColor, fontSize: 12),
                        ),
                        if (isAdmin && ideaIsApproved) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 14,
                            color: statusColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (feature.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                feature.description,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                // Priority badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    feature.priority.name,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                  ),
                ),
                const Spacer(),
                // Upvote button (Animated)
                Builder(
                  builder: (context) {
                    final currentUserId = _ideasService.userId;
                    final hasVoted =
                        currentUserId != null &&
                        feature.hasVoted(currentUserId);

                    return _AnimatedUpvoteButton(
                      count: feature.voteCount,
                      hasVoted: hasVoted,
                      onTap: () async {
                        await _ideasService.toggleFeatureVote(
                          groupId: widget.groupId,
                          ideaId: widget.ideaId,
                          featureId: feature.id,
                        );
                      },
                      size: 14,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A reusable animated upvote button
class _AnimatedUpvoteButton extends StatefulWidget {
  final int count;
  final bool hasVoted;
  final VoidCallback onTap;
  final double size;

  const _AnimatedUpvoteButton({
    required this.count,
    required this.hasVoted,
    required this.onTap,
    required this.size,
  });

  @override
  State<_AnimatedUpvoteButton> createState() => _AnimatedUpvoteButtonState();
}

class _AnimatedUpvoteButtonState extends State<_AnimatedUpvoteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _AnimatedUpvoteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasVoted != oldWidget.hasVoted) {
      _controller.forward().then((_) => _controller.reverse());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: widget.size * 0.75,
            vertical: widget.size * 0.4,
          ),
          decoration: BoxDecoration(
            color: widget.hasVoted ? Colors.blue.shade100 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.hasVoted
                  ? Colors.blue.shade400
                  : Colors.blue.shade200,
              width: widget.hasVoted ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.hasVoted ? Icons.thumb_up : Icons.thumb_up_outlined,
                size: widget.size,
                color: widget.hasVoted
                    ? Colors.blue.shade700
                    : Colors.blue.shade600,
              ),
              SizedBox(width: widget.size * 0.4),
              Text(
                '${widget.count}',
                style: TextStyle(
                  fontSize: widget.size * 0.85,
                  fontWeight: FontWeight.bold,
                  color: widget.hasVoted
                      ? Colors.blue.shade700
                      : Colors.blue.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
