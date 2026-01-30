import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/comment.dart';
import '../models/reply.dart';
import 'notifications_service.dart';

/// Service for managing comments on public ideas
class CommentsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;
  String? get _userName =>
      _auth.currentUser?.displayName ??
      _auth.currentUser?.email?.split('@').first;

  /// Get comments collection for a specific idea
  CollectionReference<Map<String, dynamic>> _commentsCollection(String ideaId) {
    return _firestore
        .collection('public_ideas')
        .doc(ideaId)
        .collection('comments');
  }

  /// Get replies collection for a specific comment
  CollectionReference<Map<String, dynamic>> _repliesCollection(
    String ideaId,
    String commentId,
  ) {
    return _commentsCollection(ideaId).doc(commentId).collection('replies');
  }

  /// Get all comments for an idea
  Future<List<Comment>> getComments(String ideaId) async {
    try {
      final snapshot = await _commentsCollection(
        ideaId,
      ).orderBy('createdAt', descending: true).limit(100).get();
      return snapshot.docs.map((doc) => Comment.fromJson(doc.data())).toList();
    } catch (e) {
      return [];
    }
  }

  /// Stream all comments for an idea (real-time updates)
  Stream<List<Comment>> streamComments(String ideaId) {
    return _commentsCollection(ideaId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Comment.fromJson(doc.data())).toList(),
        );
  }

  /// Get comment count for an idea
  Future<int> getCommentCount(String ideaId) async {
    try {
      final snapshot = await _commentsCollection(ideaId).count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Add a comment to an idea and notify the owner
  Future<bool> addComment({
    required String ideaId,
    required String ideaName,
    required String ideaOwnerId,
    required CommentType type,
    required String content,
  }) async {
    final userId = _userId;
    final userName = _userName;
    if (userId == null) return false;

    try {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final comment = Comment(
        id: id,
        ideaId: ideaId,
        authorId: userId,
        authorName: userName ?? 'Anonymous',
        type: type,
        content: content,
        createdAt: DateTime.now(),
      );

      await _commentsCollection(ideaId).doc(id).set(comment.toJson());

      // Send notification to idea owner
      if (ideaOwnerId != userId) {
        final notificationsService = NotificationsService();
        String notifTitle;
        String notifMessage;

        switch (type) {
          case CommentType.comment:
            notifTitle = 'New comment on your idea! 💬';
            notifMessage = '$userName commented on "$ideaName"';
            break;
          case CommentType.suggestion:
            notifTitle = 'New suggestion for your idea! 💡';
            notifMessage = '$userName made a suggestion on "$ideaName"';
            break;
          case CommentType.question:
            notifTitle = 'Someone has a question! ❓';
            notifMessage = '$userName asked a question about "$ideaName"';
            break;
        }

        await notificationsService.sendNotification(
          toUserId: ideaOwnerId,
          type: type.name,
          title: notifTitle,
          message: notifMessage,
          ideaId: ideaId,
          ideaName: ideaName,
        );
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete a comment (only author can delete)
  Future<bool> deleteComment(String ideaId, String commentId) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final doc = await _commentsCollection(ideaId).doc(commentId).get();
      if (!doc.exists) return false;

      final comment = Comment.fromJson(doc.data()!);
      if (comment.authorId != userId) return false;

      await _commentsCollection(ideaId).doc(commentId).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  // ============= REPLY METHODS =============

  /// Stream all replies for a comment (real-time updates)
  Stream<List<Reply>> streamReplies(String ideaId, String commentId) {
    return _repliesCollection(ideaId, commentId)
        .orderBy('createdAt', descending: false)
        .limit(50)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Reply.fromJson(doc.data())).toList(),
        );
  }

  /// Add a reply to a comment and notify the comment author
  Future<bool> addReply({
    required String ideaId,
    required String commentId,
    required String commentAuthorId,
    required String ideaOwnerId,
    required String ideaName,
    required String content,
  }) async {
    final userId = _userId;
    final userName = _userName;
    if (userId == null) {
      print('addReply: No user logged in');
      return false;
    }

    try {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final reply = Reply(
        id: id,
        commentId: commentId,
        authorId: userId,
        authorName: userName ?? 'Anonymous',
        content: content,
        createdAt: DateTime.now(),
      );

      print('addReply: Adding reply to ideaId=$ideaId, commentId=$commentId');

      // Add reply to subcollection - THIS IS THE MAIN ACTION
      await _repliesCollection(ideaId, commentId).doc(id).set(reply.toJson());
      print('addReply: Reply saved successfully');

      // Try to increment reply count (but don't fail if it doesn't work)
      try {
        await _commentsCollection(
          ideaId,
        ).doc(commentId).update({'replyCount': FieldValue.increment(1)});
        print('addReply: replyCount incremented');
      } catch (e) {
        print('addReply: replyCount update failed (non-critical): $e');
        // Ignore - reply is still saved
      }

      // Try to send notifications (but don't fail if they don't work)
      try {
        if (commentAuthorId != userId) {
          final notificationsService = NotificationsService();
          await notificationsService.sendNotification(
            toUserId: commentAuthorId,
            type: 'comment_reply',
            title: 'Someone replied to your comment! 💬',
            message: '$userName replied to your comment on "$ideaName"',
            ideaId: ideaId,
            ideaName: ideaName,
          );
        }

        if (ideaOwnerId != userId && ideaOwnerId != commentAuthorId) {
          final notificationsService = NotificationsService();
          await notificationsService.sendNotification(
            toUserId: ideaOwnerId,
            type: 'comment_reply',
            title: 'New activity on your idea! 💬',
            message: '$userName replied to a comment on "$ideaName"',
            ideaId: ideaId,
            ideaName: ideaName,
          );
        }
      } catch (e) {
        print('addReply: Notification failed (non-critical): $e');
        // Ignore - reply is still saved
      }

      print('addReply: SUCCESS');
      return true; // Reply was saved successfully!
    } catch (e) {
      print('addReply: FAILED with error: $e');
      return false;
    }
  }

  /// Delete a reply (only author can delete)
  Future<bool> deleteReply(
    String ideaId,
    String commentId,
    String replyId,
  ) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final doc = await _repliesCollection(
        ideaId,
        commentId,
      ).doc(replyId).get();
      if (!doc.exists) return false;

      final reply = Reply.fromJson(doc.data()!);
      if (reply.authorId != userId) return false;

      await _repliesCollection(ideaId, commentId).doc(replyId).delete();

      // Decrement reply count on parent comment
      await _commentsCollection(
        ideaId,
      ).doc(commentId).update({'replyCount': FieldValue.increment(-1)});

      return true;
    } catch (e) {
      return false;
    }
  }
}
