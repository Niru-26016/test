import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/feature.dart';
import '../models/idea.dart';
import 'notifications_service.dart';

/// Service for managing ideas persistence using Firestore
class IdeasService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;
  String? get _userName =>
      _auth.currentUser?.displayName ??
      _auth.currentUser?.email?.split('@').first;

  /// User's private ideas collection
  CollectionReference<Map<String, dynamic>>? get _ideasCollection {
    final uid = _userId;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('ideas');
  }

  /// Public ideas collection (shared across all users)
  CollectionReference<Map<String, dynamic>> get _publicIdeasCollection {
    return _firestore.collection('public_ideas');
  }

  /// Get all ideas for current user
  Future<List<Idea>> getIdeas() async {
    final collection = _ideasCollection;
    if (collection == null) return [];

    try {
      final snapshot = await collection
          .orderBy('updatedAt', descending: true)
          .get();
      return snapshot.docs.map((doc) => Idea.fromJson(doc.data())).toList();
    } catch (e) {
      return [];
    }
  }

  /// Filtered stream of user's ideas
  /// Note: Stage filtering is done in-memory to avoid requiring Firestore composite indexes
  Stream<List<Idea>> streamMyIdeas(String userId, IdeaStage? stage) {
    // Fetch all ideas for this user and filter by stage in-memory
    // This avoids the need for a composite index on (stage, updatedAt)
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('ideas')
        .snapshots()
        .map((snapshot) {
          List<Idea> ideas = snapshot.docs
              .map((doc) => Idea.fromJson(doc.data()))
              .toList();

          // Filter by stage in-memory if specified
          if (stage != null) {
            ideas = ideas.where((idea) => idea.stage == stage).toList();
          }

          // Sort by updatedAt descending in-memory
          ideas.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

          return ideas;
        });
  }

  /// Get all public ideas from the community
  Future<List<Idea>> getPublicIdeas() async {
    try {
      final snapshot = await _publicIdeasCollection
          .orderBy('updatedAt', descending: true)
          .limit(100)
          .get();
      return snapshot.docs.map((doc) => Idea.fromJson(doc.data())).toList();
    } catch (e) {
      return [];
    }
  }

  /// Add or update an idea
  Future<void> saveIdea(Idea idea) async {
    final collection = _ideasCollection;
    if (collection == null) return;

    // Add owner info if not present
    final ideaWithOwner = idea.copyWith(
      ownerId: idea.ownerId ?? _userId,
      ownerName: idea.ownerName ?? _userName,
    );

    // Save to user's collection
    await collection.doc(idea.id).set(ideaWithOwner.toJson());

    // Sync with public collection based on isPublic flag
    // Wrapped in try-catch to prevent permission errors from blocking the save
    try {
      if (ideaWithOwner.isPublic) {
        await _publicIdeasCollection.doc(idea.id).set(ideaWithOwner.toJson());
      } else {
        // Remove from public if it was previously public
        await _publicIdeasCollection.doc(idea.id).delete();
      }
    } catch (e) {
      // Public collection sync failed - this is non-critical
      // The idea is still saved to user's private collection
      debugPrint('Public collection sync failed: $e');
    }
  }

  /// Update a single feature's status within an idea
  /// Used for Kanban-style feature management in Implementation stage
  Future<void> updateFeatureStatus({
    required String ideaId,
    required String featureId,
    required FeatureStatus status,
  }) async {
    final idea = await getIdeaById(ideaId);
    if (idea == null) return;

    // Find and update the feature
    final updatedFeatures = idea.features.map((f) {
      if (f.id == featureId) {
        return f.copyWith(status: status);
      }
      return f;
    }).toList();

    // Save updated idea
    final updatedIdea = idea.copyWith(
      features: updatedFeatures,
      updatedAt: DateTime.now(),
    );
    await saveIdea(updatedIdea);
  }

  /// Delete an idea by ID
  Future<void> deleteIdea(String id) async {
    final collection = _ideasCollection;
    if (collection == null) return;

    await collection.doc(id).delete();
    // Also remove from public collection if it was public
    // Wrapped in try-catch to prevent permission errors from blocking delete
    try {
      await _publicIdeasCollection.doc(id).delete();
    } catch (e) {
      // Public collection delete failed - non-critical
      debugPrint('Failed to delete from public collection: $e');
    }
  }

  /// Toggle idea visibility between public and private
  Future<void> toggleIdeaVisibility(String ideaId, bool isPublic) async {
    final idea = await getIdeaById(ideaId);
    if (idea == null) return;

    final updatedIdea = idea.copyWith(
      isPublic: isPublic,
      updatedAt: DateTime.now(),
    );
    await saveIdea(updatedIdea);
  }

  /// Update idea stage (Ideation → Implementation → Completed)
  /// Uses direct Firestore update for efficiency
  Future<void> updateIdeaStage({
    required String ideaId,
    required IdeaStage stage,
  }) async {
    final collection = _ideasCollection;
    if (collection == null) return;

    await collection.doc(ideaId).update({
      'stage': stage.name,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    // Also update in public collection if the idea is public
    try {
      final doc = await _publicIdeasCollection.doc(ideaId).get();
      if (doc.exists) {
        await _publicIdeasCollection.doc(ideaId).update({
          'stage': stage.name,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Public collection stage update failed: $e');
    }
  }

  /// Get a single idea by ID
  Future<Idea?> getIdeaById(String id) async {
    final collection = _ideasCollection;
    if (collection == null) return null;

    try {
      final doc = await collection.doc(id).get();
      if (doc.exists && doc.data() != null) {
        return Idea.fromJson(doc.data()!);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Stream a single idea by ID
  Stream<Idea?> streamIdea(String id) {
    // Try user's collection first
    final userColl = _ideasCollection;
    if (userColl == null) return Stream.value(null);

    return userColl.doc(id).snapshots().asyncMap((doc) async {
      if (doc.exists && doc.data() != null) {
        return Idea.fromJson(doc.data()!);
      }

      // If not found in user collection, try public collection
      final publicDoc = await _publicIdeasCollection.doc(id).get();
      if (publicDoc.exists && publicDoc.data() != null) {
        return Idea.fromJson(publicDoc.data()!);
      }

      return null;
    });
  }

  // ===== STARRED IDEAS =====

  /// User's starred ideas collection
  CollectionReference<Map<String, dynamic>>? get _starredCollection {
    final uid = _userId;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('starred_ideas');
  }

  /// Star a public idea (bookmark it) and notify owner
  Future<void> starIdea(Idea idea) async {
    final collection = _starredCollection;
    if (collection == null) return;

    await collection.doc(idea.id).set({
      'ideaId': idea.id,
      'ideaData': idea.toJson(),
      'starredAt': DateTime.now().toIso8601String(),
    });

    // Send notification to idea owner
    if (idea.ownerId != null && idea.ownerId != _userId) {
      final notificationsService = NotificationsService();
      await notificationsService.sendNotification(
        toUserId: idea.ownerId!,
        type: 'star',
        title: 'Someone starred your idea! ⭐',
        message: '$_userName starred "${idea.name}"',
        ideaId: idea.id,
        ideaName: idea.name,
      );
    }
  }

  /// Unstar an idea
  Future<void> unstarIdea(String ideaId) async {
    final collection = _starredCollection;
    if (collection == null) return;

    await collection.doc(ideaId).delete();
  }

  /// Check if an idea is starred
  Future<bool> isIdeaStarred(String ideaId) async {
    final collection = _starredCollection;
    if (collection == null) return false;

    try {
      final doc = await collection.doc(ideaId).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Get all starred ideas
  Future<List<Idea>> getStarredIdeas() async {
    final collection = _starredCollection;
    if (collection == null) return [];

    try {
      final snapshot = await collection
          .orderBy('starredAt', descending: true)
          .get();
      return snapshot.docs
          .map(
            (doc) =>
                Idea.fromJson(doc.data()['ideaData'] as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get all public ideas stream
  Stream<List<Idea>> streamPublicIdeas() {
    return _publicIdeasCollection
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Idea.fromJson(doc.data())).toList(),
        );
  }

  /// Get starred idea IDs stream
  Stream<Set<String>> streamStarredIdeaIds() {
    final collection = _starredCollection;
    if (collection == null) return Stream.value({});

    return collection.snapshots().map(
      (snapshot) => snapshot.docs.map((doc) => doc.id).toSet(),
    );
  }
}
