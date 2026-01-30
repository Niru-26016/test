import 'package:flutter/material.dart';
import '../services/notifications_service.dart';
import 'idea_detail_screen.dart';
import 'main_screen.dart';
import 'group_detail_screen.dart';

/// Screen showing user's notifications
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsService _notificationsService = NotificationsService();

  Future<void> _markAllAsRead() async {
    await _notificationsService.markAllAsRead();
  }

  Future<void> _deleteNotification(AppNotification notification) async {
    await _notificationsService.deleteNotification(notification.id);
  }

  Future<void> _deleteAllNotifications() async {
    await _notificationsService.deleteAllNotifications();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications deleted')),
      );
    }
  }

  void _showDeleteAllDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Notifications'),
        content: const Text(
          'Are you sure you want to delete all notifications? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAllNotifications();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  void _onNotificationTap(AppNotification notification) async {
    // Mark as read in database
    if (!notification.isRead) {
      await _notificationsService.markAsRead(notification.id);
    }

    // Handle group invite notifications - navigate to Groups tab
    if (notification.type == 'group_invite' && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => const MainScreen(initialIndex: 2),
        ),
        (route) => false,
      );
      return;
    }

    // Handle join request notifications - navigate to Group Info tab
    // For admins/owners to accept/decline the request
    if (notification.type == 'join_request' &&
        notification.ideaId != null &&
        mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => GroupDetailScreen(
            groupId: notification.ideaId!,
            initialTabIndex: 1, // Navigate to Info tab
          ),
        ),
      );
      return;
    }

    // Navigate to idea if available (for other notifications like star, comment)
    if (notification.ideaId != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IdeaDetailScreen(ideaId: notification.ideaId!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          StreamBuilder<List<AppNotification>>(
            stream: _notificationsService.streamNotifications(),
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? [];
              if (notifications.isEmpty) return const SizedBox.shrink();

              final hasUnread = notifications.any((n) => !n.isRead);

              return PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'mark_read') {
                    await _markAllAsRead();
                  } else if (value == 'delete_all') {
                    _showDeleteAllDialog();
                  }
                },
                itemBuilder: (context) => [
                  if (hasUnread)
                    const PopupMenuItem(
                      value: 'mark_read',
                      child: Row(
                        children: [
                          Icon(Icons.done_all),
                          SizedBox(width: 8),
                          Text('Mark all read'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete_all',
                    child: Row(
                      children: [
                        Icon(Icons.delete_sweep, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete all', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _notificationsService.streamNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final notification = notifications[index];
              return _buildNotificationTile(notification);
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationTile(AppNotification notification) {
    return Dismissible(
      key: Key(notification.id),
      // Only allow swipe-to-mark-read if unread, always allow delete
      direction: notification.isRead
          ? DismissDirection
                .endToStart // Already read: only allow delete
          : DismissDirection.horizontal, // Unread: allow both directions
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Swipe left-to-right: Mark as read
          if (!notification.isRead) {
            await _notificationsService.markAsRead(notification.id);
          }
          return false; // Don't dismiss, just mark as read
        } else {
          // Swipe right-to-left: Delete
          return true;
        }
      },
      onDismissed: (_) => _deleteNotification(notification),
      // Right-to-left background (delete)
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      // Left-to-right background (mark as read) - only shown for unread
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: notification.isRead
              ? Colors.grey.shade300
              : Colors.amber.shade100,
          child: Icon(
            _getNotificationIcon(notification.type),
            color: notification.isRead ? Colors.grey : Colors.amber.shade700,
          ),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: notification.isRead
                ? FontWeight.normal
                : FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.message),
            const SizedBox(height: 4),
            Text(
              _formatTime(notification.createdAt),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: notification.isRead
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
        onTap: () => _onNotificationTap(notification),
      ),
    );
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'star':
        return Icons.star;
      case 'comment':
        return Icons.comment;
      case 'group_invite':
        return Icons.group_add;
      case 'join_request':
        return Icons.person_add;
      default:
        return Icons.notifications;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'When someone stars your ideas, you\'ll see it here!',
            style: TextStyle(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
