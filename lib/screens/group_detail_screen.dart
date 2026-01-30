import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/group.dart';
import '../models/group_idea.dart';
import '../services/groups_service.dart';
import '../services/group_ideas_service.dart';
import 'invite_members_screen.dart';
import 'group_idea_detail_screen.dart';

/// Screen showing group details with ideas and members
/// Uses StreamBuilder for real-time updates of all data
class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  final int initialTabIndex;

  const GroupDetailScreen({
    super.key,
    required this.groupId,
    this.initialTabIndex = 0, // 0 = Ideas, 1 = Info
  });

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  final GroupsService _groupsService = GroupsService();
  final GroupIdeasService _ideasService = GroupIdeasService();

  late TabController _tabController;
  late Stream<Group?> _groupStream;
  late Stream<GroupRole?> _roleStream;
  late Stream<List<GroupMember>> _membersStream;
  late Stream<List<GroupIdea>> _ideasStream;
  late Stream<List<Map<String, dynamic>>> _requestsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _initStreams();
  }

  void _initStreams() {
    _groupStream = _groupsService.streamGroupById(widget.groupId);
    _roleStream = _groupsService.streamUserRole(widget.groupId);
    _membersStream = _groupsService.streamGroupMembers(widget.groupId);
    _ideasStream = _ideasService.streamGroupIdeas(widget.groupId);
    _requestsStream = _groupsService.streamJoinRequests(widget.groupId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _approveRequest(String userId) async {
    final success = await _groupsService.approveJoinRequest(
      widget.groupId,
      userId,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Member approved!')));
    }
  }

  Future<void> _rejectRequest(String userId) async {
    final success = await _groupsService.rejectJoinRequest(
      widget.groupId,
      userId,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request declined')));
    }
  }

  void _showDeleteGroupDialog(Group group, GroupRole userRole) {
    if (userRole != GroupRole.owner) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text(
          'Are you sure you want to delete "${group.name}"?\n\nThis will remove all members and ideas. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final success = await _groupsService.deleteGroup(
                  widget.groupId,
                );
                if (success && mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Group deleted')),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to delete group'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to delete group'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showLeaveGroupDialog(Group group, GroupRole userRole) {
    if (userRole == GroupRole.owner) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Are you sure you want to leave "${group.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await _groupsService.leaveGroup(widget.groupId);
              if (success && mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Left group')));
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _copyInviteCode(String inviteCode) {
    Clipboard.setData(ClipboardData(text: inviteCode));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invite code copied!')));
  }

  void _navigateToInvite(String inviteCode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InviteMembersScreen(
          groupId: widget.groupId,
          inviteCode: inviteCode,
        ),
      ),
    );
  }

  void _showAddIdeaDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final List<Map<String, dynamic>> features = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New Idea'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Idea Name *',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Features (${features.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextButton.icon(
                      onPressed: () => _showAddFeatureDialog(
                        context: context,
                        onAdd: (name, desc) {
                          setDialogState(() {
                            features.add({
                              'id': DateTime.now().millisecondsSinceEpoch
                                  .toString(),
                              'name': name,
                              'description': desc,
                              'createdAt': DateTime.now().toIso8601String(),
                              'isCompleted': false,
                            });
                          });
                        },
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                if (features.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...features.asMap().entries.map((entry) {
                    final index = entry.key;
                    final feature = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        dense: true,
                        title: Text(
                          feature['name'] ?? '',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: feature['description']?.isNotEmpty == true
                            ? Text(
                                feature['description'],
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, size: 18),
                          onPressed: () {
                            setDialogState(() {
                              features.removeAt(index);
                            });
                          },
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(context);
                await _ideasService.createGroupIdea(
                  groupId: widget.groupId,
                  name: name,
                  description: descController.text.trim(),
                  features: features,
                );
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddFeatureDialog({
    required BuildContext context,
    required Function(String name, String description) onAdd,
  }) {
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
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
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
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              onAdd(name, descController.text.trim());
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showVoteDialog(GroupIdea idea) {
    final currentUserId = _groupsService.currentUserId ?? '';
    int selectedRating = idea.getUserVote(currentUserId)?.rating ?? 3;

    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vote on "${idea.name}"',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              const Text('Rate this idea'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starNum = index + 1;
                  return IconButton(
                    onPressed: () {
                      setSheetState(() => selectedRating = starNum);
                    },
                    icon: Icon(
                      starNum <= selectedRating
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.amber,
                      size: 36,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _ideasService.addVote(
                      groupId: widget.groupId,
                      ideaId: idea.id,
                      rating: selectedRating,
                    );
                  },
                  child: const Text('Submit Vote'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Group?>(
      stream: _groupStream,
      builder: (context, groupSnapshot) {
        if (groupSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final group = groupSnapshot.data;
        if (group == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Group not found')),
          );
        }

        return StreamBuilder<GroupRole?>(
          stream: _roleStream,
          builder: (context, roleSnapshot) {
            final userRole = roleSnapshot.data;

            return StreamBuilder<List<GroupMember>>(
              stream: _membersStream,
              builder: (context, membersSnapshot) {
                final members = membersSnapshot.data ?? [];

                return StreamBuilder<List<GroupIdea>>(
                  stream: _ideasStream,
                  builder: (context, ideasSnapshot) {
                    final ideas = ideasSnapshot.data ?? [];

                    return StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _requestsStream,
                      builder: (context, requestsSnapshot) {
                        final joinRequests = requestsSnapshot.data ?? [];

                        return _buildMainScaffold(
                          group: group,
                          userRole: userRole,
                          members: members,
                          ideas: ideas,
                          joinRequests: joinRequests,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMainScaffold({
    required Group group,
    required GroupRole? userRole,
    required List<GroupMember> members,
    required List<GroupIdea> ideas,
    required List<Map<String, dynamic>> joinRequests,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: Text(group.name),
        actions: [
          // Only show invite button for admin/owner
          if (userRole == GroupRole.owner || userRole == GroupRole.admin)
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () => _navigateToInvite(group.inviteCode),
              tooltip: 'Invite members',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                _showDeleteGroupDialog(group, userRole!);
              } else if (value == 'leave') {
                _showLeaveGroupDialog(group, userRole!);
              }
            },
            itemBuilder: (context) => [
              if (userRole == GroupRole.owner)
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete Group', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                )
              else
                const PopupMenuItem(
                  value: 'leave',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Leave Group', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.lightbulb_outline), text: 'Ideas'),
            Tab(icon: Icon(Icons.info_outline), text: 'Info'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildIdeasTab(ideas, userRole ?? GroupRole.member),
          _buildInfoTab(group, userRole, members, joinRequests),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddIdeaDialog,
        child: const Icon(Icons.add_circle_outline),
      ),
    );
  }

  Widget _buildIdeasTab(List<GroupIdea> ideas, GroupRole userRole) {
    final notApprovedIdeas = ideas.where((i) => !i.isApproved).toList();
    final approvedIdeas = ideas.where((i) => i.isApproved).toList();
    final isAdmin = userRole == GroupRole.owner || userRole == GroupRole.admin;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const TabBar(
              tabs: [
                Tab(text: 'Not Approved'),
                Tab(text: 'Approved'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildIdeaList(
                  notApprovedIdeas,
                  isAdmin,
                  showApproveButton: true,
                ),
                _buildIdeaList(
                  approvedIdeas,
                  isAdmin,
                  showApproveButton: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdeaList(
    List<GroupIdea> ideas,
    bool isAdmin, {
    required bool showApproveButton,
  }) {
    if (ideas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No ideas here',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 18),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ideas.length,
      itemBuilder: (context, index) {
        final idea = ideas[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildIdeaCard(
            idea,
            isAdmin: isAdmin,
            showApproveButton: showApproveButton,
          ),
        );
      },
    );
  }

  Widget _buildIdeaCard(
    GroupIdea idea, {
    required bool isAdmin,
    required bool showApproveButton,
  }) {
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                GroupIdeaDetailScreen(groupId: idea.groupId, ideaId: idea.id),
          ),
        ),
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
                  if (idea.isShared)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Shared',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue.shade700,
                        ),
                      ),
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
              if (idea.features.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.checklist,
                            size: 14,
                            color: Colors.green.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${idea.features.length} feature${idea.features.length > 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  // Upvote count (Reactive)
                  StreamBuilder<int>(
                    stream: _ideasService.streamVoteCount(
                      idea.groupId,
                      idea.id,
                    ),
                    initialData: idea.voteCount,
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.thumb_up_outlined,
                              size: 14,
                              color: Colors.blue.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  // Author name
                  Text(
                    'by ${idea.authorName}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTab(
    Group group,
    GroupRole? userRole,
    List<GroupMember> members,
    List<Map<String, dynamic>> joinRequests,
  ) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (group.description.isNotEmpty) ...[
                    Text(group.description),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      Text('Created ${_formatDate(group.createdAt)}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if ((userRole == GroupRole.owner || userRole == GroupRole.admin) &&
              joinRequests.isNotEmpty) ...[
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.pending_actions,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Pending Requests (${joinRequests.length})',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...joinRequests.map((request) {
                      final userName = request['userName'] ?? 'Unknown';
                      final oderId = request['userId'] ?? '';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.shade200,
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(userName),
                        subtitle: const Text('Wants to join'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _rejectRequest(oderId),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                              onPressed: () => _approveRequest(oderId),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people),
                      const SizedBox(width: 8),
                      Text(
                        'Members (${members.length}/${Group.maxMembers})',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...members.map(
                    (member) => _buildMemberTile(member, userRole),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberTile(GroupMember member, GroupRole? userRole) {
    final canManage =
        userRole == GroupRole.owner ||
        (userRole == GroupRole.admin && member.role == GroupRole.member);
    final isOwner = member.role == GroupRole.owner;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: isOwner
            ? Colors.amber.shade100
            : Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          member.userName.isNotEmpty ? member.userName[0].toUpperCase() : '?',
          style: TextStyle(
            color: isOwner ? Colors.amber.shade800 : null,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(member.userName, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          _buildRoleBadge(member.role),
        ],
      ),
      subtitle: Text('Joined ${_formatDate(member.joinedAt)}'),
      trailing: (canManage && member.role != GroupRole.owner)
          ? PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'kick') {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Remove Member'),
                      content: Text(
                        'Remove ${member.userName} from the group?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _groupsService.removeMember(
                      widget.groupId,
                      member.userId,
                    );
                  }
                } else if (action == 'promote') {
                  await _groupsService.updateMemberRole(
                    widget.groupId,
                    member.userId,
                    GroupRole.admin,
                  );
                }
              },
              itemBuilder: (context) => [
                if (userRole == GroupRole.owner &&
                    member.role == GroupRole.member)
                  const PopupMenuItem(
                    value: 'promote',
                    child: Text('Make Admin'),
                  ),
                const PopupMenuItem(
                  value: 'kick',
                  child: Text('Remove', style: TextStyle(color: Colors.red)),
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildRoleBadge(GroupRole role) {
    Color color;
    switch (role) {
      case GroupRole.owner:
        color = Colors.amber;
        break;
      case GroupRole.admin:
        color = Colors.blue;
        break;
      case GroupRole.member:
        color = Colors.grey;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        role.name.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
