import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';

import '../models/idea.dart';
import '../services/ideas_service.dart';
import '../services/notifications_service.dart';
import '../widgets/idea_card.dart';
import 'idea_detail_screen.dart';
import 'idea_form_screen.dart';
import 'notifications_screen.dart';

/// Home screen displaying list of all ideas with a locked stream lifecycle
class HomeScreen extends StatefulWidget {
  final bool isVisible;

  const HomeScreen({super.key, this.isVisible = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final IdeasService _ideasService = IdeasService();
  final NotificationsService _notificationsService = NotificationsService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ValueNotifier<String> _searchQuery = ValueNotifier('');
  // TabController removed in favor of custom AnimatedTabs

  // Showcase keys
  final GlobalKey _fabShowcaseKey = GlobalKey();
  final GlobalKey _tabsShowcaseKey = GlobalKey();

  late String _userId;
  Stream<List<Idea>>? _ideasStream;
  IdeaStage _currentStage = IdeaStage.ideation;
  bool _showcaseTriggered = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _triggerShowcaseIfNeeded(BuildContext showcaseContext) async {
    if (!widget.isVisible || _showcaseTriggered) return;
    _showcaseTriggered = true;

    final prefs = await SharedPreferences.getInstance();
    final isFirstHomeVisit = prefs.getBool('first_home_visit') ?? true;
    if (isFirstHomeVisit && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShowCaseWidget.of(
          showcaseContext,
        ).startShowCase([_fabShowcaseKey, _tabsShowcaseKey]);
      });
      await prefs.setBool('first_home_visit', false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchQuery.dispose();
    super.dispose();
  }

  // _onTabChanged removed - replaced by _selectStage

  String get _searchHint {
    switch (_currentStage) {
      case IdeaStage.ideation:
        return 'Search ideas, tags...';
      case IdeaStage.implementation:
        return 'Search active projects...';
      case IdeaStage.completed:
        return 'Search completed projects...';
    }
  }

  Future<void> _deleteIdea(Idea idea) async {
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

  void _navigateToDetail(Idea idea) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IdeaDetailScreen(ideaId: idea.id),
      ),
    );
  }

  void _navigateToAdd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const IdeaFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ShowCaseWidget(
      builder: (showcaseContext) {
        if (widget.isVisible) {
          // Trigger showcase on first home visit
          _triggerShowcaseIfNeeded(showcaseContext);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('My Ideas'),
            centerTitle: true,
            elevation: 0,
            actions: [
              StreamBuilder<int>(
                stream: _notificationsService.streamUnreadCount(),
                builder: (context, snapshot) {
                  final unreadCount = snapshot.data ?? 0;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const NotificationsScreen(),
                            ),
                          );
                        },
                        tooltip: 'Notifications',
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          body: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data == null) {
                return const Center(
                  child: Text('Please sign in to view ideas'),
                );
              }

              final uid = snapshot.data!.uid;

              // Initialize stream ONLY ONCE (protected by null check or user change)
              if (_ideasStream == null ||
                  (_ideasStream != null && _userId != uid)) {
                print('INIT STREAM (Auth Ready). UID: $uid');
                _userId = uid;
                _ideasStream = _ideasService.streamMyIdeas(
                  _userId,
                  _currentStage,
                );
              }

              return _buildContent();
            },
          ),
          floatingActionButton: _currentStage == IdeaStage.completed
              ? null
              : Showcase(
                  key: _fabShowcaseKey,
                  description: 'Create your first idea here!',
                  targetPadding: const EdgeInsets.all(8),
                  child: FloatingActionButton.extended(
                    onPressed: _navigateToAdd,
                    icon: Icon(
                      _currentStage == IdeaStage.ideation
                          ? Icons.add_circle_outline
                          : Icons.add_task,
                    ),
                    label: Text(
                      _currentStage == IdeaStage.ideation
                          ? 'New Idea'
                          : 'Add Task',
                    ),
                  ),
                ),
        );
      }, // Close builder block
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // Search bar (Minimal Outline)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: TextField(
            key: const ValueKey('search_field'),
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (value) => _searchQuery.value = value,
            decoration: InputDecoration(
              hintText: _searchHint,
              prefixIcon: Icon(
                Icons.search,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.7),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _searchQuery.value = '';
                },
              ),
              filled: false,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withValues(alpha: 0.5),
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

        // Animated Stage Selector
        Showcase(
          key: _tabsShowcaseKey,
          description: 'Ideas → Execution → Done. Track your progress!',
          targetPadding: const EdgeInsets.all(8),
          child: Container(
            height: 56,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(28),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                // Selected gets 50% width, unselected gets 25% each (approx)
                // using a small gap of 4px between items
                final availableWidth = totalWidth - 8; // 2 gaps of 4px
                final selectedWidth = availableWidth * 0.5;
                final unselectedWidth = availableWidth * 0.25;

                return Row(
                  children: [
                    _buildAnimatedTab(
                      label: 'Ideas',
                      icon: _currentStage == IdeaStage.ideation
                          ? Icons.lightbulb
                          : Icons.lightbulb_outline,
                      stage: IdeaStage.ideation,
                      width: _currentStage == IdeaStage.ideation
                          ? selectedWidth
                          : unselectedWidth,
                    ),
                    const SizedBox(width: 4),
                    _buildAnimatedTab(
                      label: 'Execution',
                      icon: _currentStage == IdeaStage.implementation
                          ? Icons
                                .bolt // Changed icon to bolt as it fits 'Execution' better than settings
                          : Icons.bolt_outlined,
                      stage: IdeaStage.implementation,
                      width: _currentStage == IdeaStage.implementation
                          ? selectedWidth
                          : unselectedWidth,
                    ),
                    const SizedBox(width: 4),
                    _buildAnimatedTab(
                      label: 'Done',
                      icon: _currentStage == IdeaStage.completed
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                      stage: IdeaStage.completed,
                      width: _currentStage == IdeaStage.completed
                          ? selectedWidth
                          : unselectedWidth,
                    ),
                  ],
                );
              },
            ),
          ),
        ), // Close Showcase

        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: _searchQuery,
            builder: (context, query, _) {
              return StreamBuilder<List<Idea>>(
                stream: _ideasStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyState();
                  }

                  // Apply local search filter
                  final ideas = snapshot.data!.where((idea) {
                    if (query.isEmpty) return true;
                    final q = query.toLowerCase();
                    return idea.name.toLowerCase().contains(q) ||
                        idea.description.toLowerCase().contains(q) ||
                        idea.features.any(
                          (f) => f.name.toLowerCase().contains(q),
                        );
                  }).toList();

                  if (ideas.isEmpty) {
                    return _buildEmptyState(isSearch: true);
                  }

                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: ListView.builder(
                      key: ValueKey(_currentStage),
                      padding: const EdgeInsets.all(16),
                      itemCount: ideas.length,
                      itemBuilder: (context, index) {
                        final idea = ideas[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: IdeaCard(
                            idea: idea,
                            onTap: () => _navigateToDetail(idea),
                            onDelete: () => _deleteIdea(idea),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({bool isSearch = false}) {
    String message;
    String? subMessage;
    IconData icon;
    Widget? actionButton;

    if (isSearch) {
      message = 'No ideas found matching \"${_searchQuery.value}\"';
      icon = Icons.search_off;
    } else {
      switch (_currentStage) {
        case IdeaStage.ideation:
          message = 'Capture your ideas before they fade.';
          subMessage = 'Tap + to save your first idea.';
          icon = Icons.lightbulb_outline;
          break;
        case IdeaStage.implementation:
          message = 'No active projects yet.';
          subMessage = 'Move an idea here to start building!';
          icon = Icons.settings_outlined;
          actionButton = TextButton.icon(
            onPressed: () => _selectStage(IdeaStage.ideation),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Move an Idea'),
          );
          break;
        case IdeaStage.completed:
          message = 'No completed projects yet.';
          subMessage = 'Every finished project starts as an idea.';
          icon = Icons.check_circle_outline;
          break;
      }
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          if (subMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              subMessage,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ],
          if (actionButton != null) ...[
            const SizedBox(height: 16),
            actionButton,
          ],
        ],
      ),
    );
  }

  Widget _buildAnimatedTab({
    required String label,
    required IconData icon,
    required IdeaStage stage,
    required double width,
  }) {
    final isSelected = _currentStage == stage;
    return GestureDetector(
      onTap: () => _selectStage(stage),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: width,
        height: 48,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
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

  void _selectStage(IdeaStage newStage) {
    if (newStage == _currentStage) return;

    // Haptic feedback
    HapticFeedback.selectionClick();

    setState(() {
      _currentStage = newStage;
      // Re-initialize stream with new stage
      if (_userId.isNotEmpty) {
        _ideasStream = _ideasService.streamMyIdeas(_userId, _currentStage);
      }
    });

    // Clear search when changing tabs
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      FocusScope.of(context).unfocus();
    }
  }
}
