import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import '../models/idea.dart';
import '../services/ideas_service.dart';
import 'idea_detail_screen.dart';

/// Discovery screen showing public ideas from the community
class DiscoveryScreen extends StatefulWidget {
  final bool isVisible;

  const DiscoveryScreen({super.key, this.isVisible = false});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final IdeasService _ideasService = IdeasService();
  String _searchQuery = '';

  // Showcase keys
  final GlobalKey _searchShowcaseKey = GlobalKey();
  final GlobalKey _starIdeaShowcaseKey = GlobalKey();
  bool _showcaseTriggered = false;

  Future<void> _triggerShowcaseIfNeeded(BuildContext showcaseContext) async {
    if (!widget.isVisible || _showcaseTriggered) return;
    _showcaseTriggered = true;

    final prefs = await SharedPreferences.getInstance();
    final isFirstVisit = prefs.getBool('first_discover_visit') ?? true;
    if (isFirstVisit && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShowCaseWidget.of(
          showcaseContext,
        ).startShowCase([_searchShowcaseKey, _starIdeaShowcaseKey]);
      });
      await prefs.setBool('first_discover_visit', false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (showcaseContext) {
        if (widget.isVisible) {
          _triggerShowcaseIfNeeded(showcaseContext);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Discover Ideas'),
            centerTitle: true,
          ),
          body: StreamBuilder<Set<String>>(
            stream: _ideasService.streamStarredIdeaIds(),
            builder: (context, starredSnapshot) {
              final starredIds = starredSnapshot.data ?? {};

              return StreamBuilder<List<Idea>>(
                stream: _ideasService.streamPublicIdeas(),
                builder: (context, ideasSnapshot) {
                  if (ideasSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final ideas = ideasSnapshot.data ?? [];
                  final filteredIdeas = _filterIdeas(ideas);

                  return Column(
                    children: [
                      // Search bar with Showcase
                      Showcase(
                        key: _searchShowcaseKey,
                        description:
                            'Search for public ideas from the community',
                        targetPadding: const EdgeInsets.all(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: TextField(
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                            decoration: InputDecoration(
                              hintText: 'Search community ideas...',
                              prefixIcon: Icon(
                                Icons.search,
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.7),
                              ),
                              filled: false,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Ideas list
                      Expanded(
                        child: filteredIdeas.isEmpty
                            ? _buildEmptyState()
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: filteredIdeas.length,
                                itemBuilder: (context, index) {
                                  final idea = filteredIdeas[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _buildIdeaCard(
                                      idea,
                                      starredIds,
                                      index,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  List<Idea> _filterIdeas(List<Idea> ideas) {
    if (_searchQuery.isEmpty) return ideas;
    final query = _searchQuery.toLowerCase();
    return ideas.where((idea) {
      return idea.name.toLowerCase().contains(query) ||
          idea.description.toLowerCase().contains(query) ||
          (idea.ownerName?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> _toggleStar(Idea idea, Set<String> starredIds) async {
    final isStarred = starredIds.contains(idea.id);

    try {
      if (isStarred) {
        await _ideasService.unstarIdea(idea.id);
      } else {
        await _ideasService.starIdea(idea);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update star: $e')));
      }
    }
  }

  void _navigateToDetail(Idea idea) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IdeaDetailScreen(
          ideaId: idea.id,
          isReadOnly: true,
          publicIdea: idea,
        ),
      ),
    );
  }

  Widget _buildIdeaCard(Idea idea, Set<String> starredIds, int index) {
    final isStarred = starredIds.contains(idea.id);

    return Card(
      child: InkWell(
        onTap: () => _navigateToDetail(idea),
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 48, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title only (no type badge here)
                  Text(
                    idea.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (idea.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      idea.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          idea.ownerName ?? 'Anonymous',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          idea.typeDisplayName,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${idea.features.length}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      Icon(
                        Icons.auto_awesome,
                        size: 12,
                        color: Colors.grey.shade500,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Star button at top-right
            Positioned(
              top: 4,
              right: 4,
              child: index == 0
                  ? Showcase(
                      key: _starIdeaShowcaseKey,
                      description: 'Tap to star ideas you like!',
                      targetShapeBorder: const CircleBorder(),
                      child: IconButton(
                        icon: Icon(
                          isStarred ? Icons.star : Icons.star_border,
                          color: isStarred ? Colors.amber : Colors.grey,
                        ),
                        onPressed: () => _toggleStar(idea, starredIds),
                        tooltip: isStarred
                            ? 'Remove from starred'
                            : 'Add to starred',
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        isStarred ? Icons.star : Icons.star_border,
                        color: isStarred ? Colors.amber : Colors.grey,
                      ),
                      onPressed: () => _toggleStar(idea, starredIds),
                      tooltip: isStarred
                          ? 'Remove from starred'
                          : 'Add to starred',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.explore_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'No public ideas yet' : 'No ideas found',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Be the first to share your idea with the community!'
                : 'Try a different search term',
            style: TextStyle(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
