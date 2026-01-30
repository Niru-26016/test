import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import '../models/group.dart';
import '../services/groups_service.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';

/// Screen showing list of user's groups
class GroupsListScreen extends StatefulWidget {
  final bool isVisible;

  const GroupsListScreen({super.key, this.isVisible = false});

  @override
  State<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends State<GroupsListScreen> {
  final GroupsService _groupsService = GroupsService();

  // Showcase keys
  final GlobalKey _createGroupShowcaseKey = GlobalKey();
  final GlobalKey _joinGroupShowcaseKey = GlobalKey();
  bool _showcaseTriggered = false;

  Future<void> _triggerShowcaseIfNeeded(BuildContext showcaseContext) async {
    if (!widget.isVisible || _showcaseTriggered) return;
    _showcaseTriggered = true;

    final prefs = await SharedPreferences.getInstance();
    final isFirstVisit = prefs.getBool('first_groups_visit') ?? true;
    if (isFirstVisit && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShowCaseWidget.of(
          showcaseContext,
        ).startShowCase([_createGroupShowcaseKey, _joinGroupShowcaseKey]);
      });
      await prefs.setBool('first_groups_visit', false);
    }
  }

  void _navigateToCreateGroup() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateGroupScreen()),
    );
  }

  void _navigateToGroupDetail(Group group) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupDetailScreen(groupId: group.id),
      ),
    );
  }

  void _showJoinGroupDialog() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request to Join Group'),
        content: TextField(
          controller: codeController,
          decoration: const InputDecoration(
            labelText: 'Invite Code',
            hintText: 'e.g., ABCD-A3X9',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.vpn_key),
          ),
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [UpperCaseTextFormatter()],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isEmpty) return;

              Navigator.pop(context);
              final error = await _groupsService.requestToJoin(code);

              if (mounted) {
                if (error == null) {
                  // Show success dialog
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 8),
                          Text('Request Sent!'),
                        ],
                      ),
                      content: const Text(
                        'Your request to join the group has been sent. The group owner will review your request.',
                      ),
                      actions: [
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                }
              }
            },
            child: const Text('Request'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptInvite(String groupId, String groupName) async {
    final success = await _groupsService.acceptGroupInvite(groupId);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('You joined "$groupName"!')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to join group')));
      }
    }
  }

  Future<void> _declineInvite(String inviteId) async {
    await _groupsService.declineGroupInvite(inviteId);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation declined')));
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
            title: const Text('My Groups'),
            centerTitle: true,
            actions: [
              Showcase(
                key: _joinGroupShowcaseKey,
                description: 'Join existing groups with an invite code',
                targetPadding: const EdgeInsets.all(4),
                child: IconButton(
                  icon: const Icon(Icons.group_add),
                  onPressed: _showJoinGroupDialog,
                  tooltip: 'Request to join',
                ),
              ),
            ],
          ),
          body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _groupsService.streamMyGroupInvites(),
            builder: (context, invitesSnapshot) {
              final invites = invitesSnapshot.data ?? [];

              return StreamBuilder<List<Group>>(
                stream: _groupsService.streamMyGroups(),
                builder: (context, groupsSnapshot) {
                  if (groupsSnapshot.connectionState ==
                          ConnectionState.waiting &&
                      invitesSnapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final groups = groupsSnapshot.data ?? [];

                  if (groups.isEmpty && invites.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Pending invites section
                      if (invites.isNotEmpty) ...[
                        _buildInvitesSection(invites),
                        const SizedBox(height: 16),
                      ],
                      // Groups list
                      ...groups.map(
                        (group) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildGroupCard(group),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          floatingActionButton: Showcase(
            key: _createGroupShowcaseKey,
            description: 'Start a new group to collaborate on ideas!',
            targetPadding: const EdgeInsets.all(8),
            child: FloatingActionButton.extended(
              onPressed: _navigateToCreateGroup,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('New Group'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInvitesSection(List<Map<String, dynamic>> invites) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.mail, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text(
                  'Group Invitations (${invites.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...invites.map((invite) => _buildInviteItem(invite)),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteItem(Map<String, dynamic> invite) {
    final groupName = invite['groupName'] ?? 'Unknown Group';
    final groupId = invite['groupId'] ?? '';
    final inviteId =
        invite['id'] ?? '${groupId}_${_groupsService.currentUserId}';
    final invitedByName = invite['invitedByName'] ?? 'Someone';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  groupName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Invited by $invitedByName',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _declineInvite(inviteId),
            child: const Text('Decline'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _acceptInvite(groupId, groupName),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(Group group) {
    return Card(
      child: InkWell(
        onTap: () => _navigateToGroupDetail(group),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.groups,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (group.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        group.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.person,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${group.memberCount}/${Group.maxMembers}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        // Invite code hidden from list - only visible to admin/owner in group detail
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
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
          Icon(Icons.groups_outlined, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No groups yet',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a group or join one with an invite code',
            style: TextStyle(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _showJoinGroupDialog,
                icon: const Icon(Icons.vpn_key),
                label: const Text('Join'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _navigateToCreateGroup,
                icon: const Icon(Icons.add),
                label: const Text('Create'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Text formatter to convert to uppercase
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
