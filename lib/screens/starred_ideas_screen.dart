import 'package:flutter/material.dart';
import '../models/idea.dart';
import '../services/ideas_service.dart';
import 'idea_detail_screen.dart';

/// Screen showing user's starred ideas
class StarredIdeasScreen extends StatefulWidget {
  const StarredIdeasScreen({super.key});

  @override
  State<StarredIdeasScreen> createState() => _StarredIdeasScreenState();
}

class _StarredIdeasScreenState extends State<StarredIdeasScreen> {
  final IdeasService _ideasService = IdeasService();
  List<Idea> _starredIdeas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStarredIdeas();
  }

  Future<void> _loadStarredIdeas() async {
    setState(() => _isLoading = true);
    final ideas = await _ideasService.getStarredIdeas();
    setState(() {
      _starredIdeas = ideas;
      _isLoading = false;
    });
  }

  Future<void> _unstarIdea(Idea idea) async {
    await _ideasService.unstarIdea(idea.id);
    _loadStarredIdeas();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed "${idea.name}" from starred')),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Starred Ideas')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _starredIdeas.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadStarredIdeas,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _starredIdeas.length,
                itemBuilder: (context, index) {
                  final idea = _starredIdeas[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildIdeaCard(idea),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildIdeaCard(Idea idea) {
    return Card(
      child: InkWell(
        onTap: () => _navigateToDetail(idea),
        borderRadius: BorderRadius.circular(12),
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _unstarIdea(idea),
                    icon: const Icon(Icons.star, color: Colors.amber),
                    tooltip: 'Remove from starred',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
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
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    idea.ownerName ?? 'Anonymous',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      idea.typeDisplayName,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.star_border, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No starred ideas yet',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Star ideas in Discovery to save them here!',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
