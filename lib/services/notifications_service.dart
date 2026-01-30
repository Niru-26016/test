import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import '../main.dart'; // For navigatorKey
import '../screens/group_detail_screen.dart';
import '../screens/group_idea_detail_screen.dart';
import '../screens/idea_detail_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `Firebase.initializeApp()` before using them.
  print("Handling a background message: ${message.messageId}");
}

/// Model for a notification
class AppNotification {
  final String id;
  final String userId; // User who receives the notification
  final String type; // 'star', 'comment', etc.
  final String title;
  final String message;
  final String? ideaId;
  final String? ideaName;
  final String? fromUserId;
  final String? fromUserName;
  final DateTime createdAt;
  final bool isRead;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.ideaId,
    this.ideaName,
    this.fromUserId,
    this.fromUserName,
    required this.createdAt,
    this.isRead = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      ideaId: json['ideaId'],
      ideaName: json['ideaName'],
      fromUserId: json['fromUserId'],
      fromUserName: json['fromUserName'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      isRead: json['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'type': type,
      'title': title,
      'message': message,
      'ideaId': ideaId,
      'ideaName': ideaName,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'createdAt': createdAt.toIso8601String(),
      'isRead': isRead,
    };
  }
}

/// Service for managing notifications
class NotificationsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'idex_notifications';
  static const String _channelName = 'Idex Notifications';
  static const String _channelDesc = 'Notifications for ideas, comments, etc.';

  /// Initialize notifications
  Future<void> initialize() async {
    // Request permissions
    await requestPermissions();

    // Initialize local notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          final data = jsonDecode(details.payload!);
          _handleNotificationTap(data);
        }
      },
    );

    // Setup Android channel
    if (Platform.isAndroid) {
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.max,
          ),
        );
      }
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showLocalNotification(message);
    });

    // Handle background click (when app is opened from notification)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message.data);
    });

    // Save/Update token if user is logged in
    await updateFcmToken();

    // Check if app was opened from a terminated state via notification
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage.data);
    }
  }

  /// Handle navigation when notification is tapped
  void _handleNotificationTap(Map<String, dynamic> data) {
    print('Handling notification tap with data: $data');
    final String? type = data['type'];
    final String? groupId = data['groupId'];
    final String? ideaId = data['ideaId'];

    final context = navigatorKey.currentContext;
    if (context == null) return;

    // Group-related notifications (require groupId)
    if (groupId != null && groupId.isNotEmpty) {
      if (type == 'new_group_idea' ||
          type == 'idea_vote' ||
          type == 'idea_approved' ||
          type == 'feature_status') {
        if (ideaId != null && ideaId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  GroupIdeaDetailScreen(groupId: groupId, ideaId: ideaId),
            ),
          );
        }
      } else if (type == 'join_request' ||
          type == 'member_added' ||
          type == 'group_invite' ||
          type == 'member_joined') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupDetailScreen(groupId: groupId),
          ),
        );
      }
    }
    // Personal idea notifications (star, comment, reply)
    else if (ideaId != null && ideaId.isNotEmpty) {
      if (type == 'star' || type == 'comment' || type == 'reply') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => IdeaDetailScreen(ideaId: ideaId),
          ),
        );
      }
    }
  }

  /// Request permissions for notifications
  Future<void> requestPermissions() async {
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
    } else {
      print('User declined or has not accepted permission');
    }
  }

  /// Update FCM token in Firestore
  Future<void> updateFcmToken() async {
    final uid = _userId;
    if (uid == null) return;

    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _firestore.collection('users').doc(uid).set({
          'fcmToken': token,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }

  /// Show a local notification for foreground messages
  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            icon: android.smallIcon,
          ),
        ),
      );
    }
  }

  String? get _userId => _auth.currentUser?.uid;
  String? get _userName =>
      _auth.currentUser?.displayName ??
      _auth.currentUser?.email?.split('@').first;

  /// Get notifications collection for a specific user
  CollectionReference<Map<String, dynamic>> _notificationsCollection(
    String userId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notifications');
  }

  /// Get current user's notifications
  Future<List<AppNotification>> getNotifications() async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      final snapshot = await _notificationsCollection(
        uid,
      ).orderBy('createdAt', descending: true).limit(50).get();
      return snapshot.docs
          .map((doc) => AppNotification.fromJson(doc.data()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get unread notifications count
  Future<int> getUnreadCount() async {
    final uid = _userId;
    if (uid == null) return 0;

    try {
      final snapshot = await _notificationsCollection(
        uid,
      ).where('isRead', isEqualTo: false).count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Stream current user's notifications (real-time updates)
  Stream<List<AppNotification>> streamNotifications() {
    final uid = _userId;
    if (uid == null) return Stream.value([]);

    return _notificationsCollection(uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AppNotification.fromJson(doc.data()))
              .toList(),
        );
  }

  /// Stream unread notifications count (real-time updates)
  Stream<int> streamUnreadCount() {
    final uid = _userId;
    if (uid == null) return Stream.value(0);

    return _notificationsCollection(uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Send a notification to a user
  Future<void> sendNotification({
    required String toUserId,
    required String type,
    required String title,
    required String message,
    String? ideaId,
    String? ideaName,
  }) async {
    final fromUserId = _userId;
    if (fromUserId == null || toUserId == fromUserId)
      return; // Don't notify self

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final notification = AppNotification(
      id: id,
      userId: toUserId,
      type: type,
      title: title,
      message: message,
      ideaId: ideaId,
      ideaName: ideaName,
      fromUserId: fromUserId,
      fromUserName: _userName,
      createdAt: DateTime.now(),
    );

    await _notificationsCollection(toUserId).doc(id).set(notification.toJson());
  }

  /// Mark a notification as read
  Future<bool> markAsRead(String notificationId) async {
    final uid = _userId;
    if (uid == null) return false;

    try {
      await _notificationsCollection(
        uid,
      ).doc(notificationId).update({'isRead': true});
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    final uid = _userId;
    if (uid == null) return;

    final batch = _firestore.batch();
    final snapshot = await _notificationsCollection(
      uid,
    ).where('isRead', isEqualTo: false).get();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    final uid = _userId;
    if (uid == null) return;

    await _notificationsCollection(uid).doc(notificationId).delete();
  }

  /// Delete all notifications for the current user
  Future<void> deleteAllNotifications() async {
    final uid = _userId;
    if (uid == null) return;

    final batch = _firestore.batch();
    final snapshot = await _notificationsCollection(uid).get();

    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
