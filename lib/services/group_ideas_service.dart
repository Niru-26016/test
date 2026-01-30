import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group_idea.dart';
import '../models/feature.dart';
import '../models/idea.dart';
import 'notifications_service.dart';

/// Service for managing ideas within groups
class GroupIdeasService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;
  String? get userId => _userId;
  String? get _userName =>
      _auth.currentUser?.displayName ??
      _auth.currentUser?.email?.split('@').first;

  CollectionReference<Map<String, dynamic>> _ideasCollection(String groupId) {
    return _firestore.collection('groups').doc(groupId).collection('ideas');
  }

  CollectionReference<Map<String, dynamic>> _votesCollection(
    String groupId,
    String ideaId,
  ) {
    return _ideasCollection(groupId).doc(ideaId).collection('votes');
  }

  /// Create a new idea in a group
  Future<GroupIdea?> createGroupIdea({
    required String groupId,
    required String name,
    String description = '',
    List<Map<String, dynamic>> features = const [],
  }) async {
    final userId = _userId;
    final userName = _userName;
    if (userId == null) return null;

    try {
      final id = DateTime.now().millisecondsSinceEpoch.toString();

      // Build idea JSON with features
      final ideaData = {
        'id': id,
        'groupId': groupId,
        'name': name,
        'description': description,
        'authorId': userId,
        'authorName': userName ?? 'Unknown',
        'createdAt': DateTime.now().toIso8601String(),
        'features': features,
      };

      await _ideasCollection(groupId).doc(id).set(ideaData);

      // Notify group members
      await _notifyGroupMembers(
        groupId: groupId,
        excludeUserId: userId,
        type: 'new_group_idea',
        title: 'New idea in your group!',
        message: '$userName added "$name"',
        ideaId: id,
        ideaName: name,
      );

      return GroupIdea.fromJson(ideaData);
    } catch (e) {
      return null;
    }
  }

  /// Share an existing idea (personal or public) to a group
  Future<GroupIdea?> shareIdeaToGroup({
    required String groupId,
    required Idea sourceIdea,
    required String sourceType, // 'personal' or 'public'
  }) async {
    final userId = _userId;
    final userName = _userName;
    if (userId == null) return null;

    try {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final idea = GroupIdea(
        id: id,
        groupId: groupId,
        name: sourceIdea.name,
        description: sourceIdea.description,
        authorId: userId,
        authorName: userName ?? 'Unknown',
        sharedFromIdeaId: sourceIdea.id,
        sharedFromType: sourceType,
        createdAt: DateTime.now(),
      );

      await _ideasCollection(groupId).doc(id).set(idea.toJson());

      // Notify group members
      await _notifyGroupMembers(
        groupId: groupId,
        excludeUserId: userId,
        type: 'shared_idea',
        title: 'Idea shared to group! 🔗',
        message: '$userName shared "${sourceIdea.name}"',
        ideaId: id,
        ideaName: sourceIdea.name,
      );

      return idea;
    } catch (e) {
      return null;
    }
  }

  /// Get all ideas in a group
  Future<List<GroupIdea>> getGroupIdeas(String groupId) async {
    try {
      final snapshot = await _ideasCollection(
        groupId,
      ).orderBy('createdAt', descending: true).get();

      final ideas = <GroupIdea>[];
      for (final doc in snapshot.docs) {
        final idea = GroupIdea.fromJson(doc.data());
        // Fetch votes for this idea
        final votes = await getVotes(groupId, idea.id);
        ideas.add(idea.copyWithVotes(votes));
      }
      return ideas;
    } catch (e) {
      return [];
    }
  }

  /// Stream all ideas in a group (real-time updates)
  /// Stream all ideas in a group (real-time)
  Stream<List<GroupIdea>> streamGroupIdeas(String groupId) {
    return _ideasCollection(
      groupId,
    ).orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => GroupIdea.fromJson(doc.data()))
          .toList();
    });
  }

  /// Stream a single idea (real-time updates)
  Stream<GroupIdea?> streamGroupIdeaById(String groupId, String ideaId) {
    final controller = StreamController<GroupIdea?>();
    GroupIdea? currentIdea;
    List<Vote>? currentVotes;

    void emitIfReady() {
      if (currentIdea != null && currentVotes != null) {
        controller.add(currentIdea!.copyWithVotes(currentVotes!));
      }
    }

    final ideaSub = _ideasCollection(groupId).doc(ideaId).snapshots().listen((
      doc,
    ) {
      if (!doc.exists || doc.data() == null) {
        controller.add(null);
        return;
      }
      try {
        currentIdea = GroupIdea.fromJson(doc.data()!);
        emitIfReady();
      } catch (e) {
        print('streamGroupIdeaById idea error: $e');
      }
    }, onError: (e) => controller.addError(e));

    final voteSub = _votesCollection(groupId, ideaId).snapshots().listen((
      snapshot,
    ) {
      try {
        currentVotes = snapshot.docs
            .map((doc) => Vote.fromJson(doc.data()))
            .toList();
        emitIfReady();
      } catch (e) {
        print('streamGroupIdeaById votes error: $e');
      }
    }, onError: (e) => controller.addError(e));

    controller.onCancel = () {
      ideaSub.cancel();
      voteSub.cancel();
    };

    return controller.stream;
  }

  /// Get a single idea with votes
  Future<GroupIdea?> getGroupIdeaById(String groupId, String ideaId) async {
    try {
      final doc = await _ideasCollection(groupId).doc(ideaId).get();
      if (doc.exists && doc.data() != null) {
        final idea = GroupIdea.fromJson(doc.data()!);
        final votes = await getVotes(groupId, ideaId);
        return idea.copyWithVotes(votes);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Get votes for an idea
  Future<List<Vote>> getVotes(String groupId, String ideaId) async {
    try {
      final snapshot = await _votesCollection(
        groupId,
        ideaId,
      ).orderBy('createdAt', descending: true).get();
      return snapshot.docs.map((doc) => Vote.fromJson(doc.data())).toList();
    } catch (e) {
      return [];
    }
  }

  /// Add or update a vote
  Future<bool> addVote({
    required String groupId,
    required String ideaId,
    required int rating,
  }) async {
    final userId = _userId;
    final userName = _userName;
    if (userId == null) return false;

    try {
      final vote = Vote(
        userId: userId,
        userName: userName ?? 'Unknown',
        rating: rating.clamp(1, 5),
        createdAt: DateTime.now(),
      );

      await _votesCollection(groupId, ideaId).doc(userId).set(vote.toJson());
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Remove a vote
  Future<bool> removeVote(String groupId, String ideaId) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      await _votesCollection(groupId, ideaId).doc(userId).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete an idea (author or admin/owner only)
  Future<bool> deleteGroupIdea(String groupId, String ideaId) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final idea = await getGroupIdeaById(groupId, ideaId);
      if (idea == null) return false;

      // Check if user is author
      if (idea.authorId != userId) {
        // Check if user is admin/owner
        final memberDoc = await _firestore
            .collection('groups')
            .doc(groupId)
            .collection('members')
            .doc(userId)
            .get();
        if (!memberDoc.exists) return false;
        final role = memberDoc.data()?['role'];
        if (role != 'owner' && role != 'admin') return false;
      }

      // Delete votes
      final votesSnapshot = await _votesCollection(groupId, ideaId).get();
      for (final doc in votesSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete idea
      await _ideasCollection(groupId).doc(ideaId).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Approve an idea (admin/owner only)
  Future<bool> approveIdea(String groupId, String ideaId) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      // Check if user is admin/owner
      final memberDoc = await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(userId)
          .get();
      if (!memberDoc.exists) return false;
      final role = memberDoc.data()?['role'];
      if (role != 'owner' && role != 'admin') return false;

      await _ideasCollection(groupId).doc(ideaId).update({'isApproved': true});
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==================== FEATURE METHODS ====================

  /// Add a new feature
  Future<Feature?> addFeature({
    required String groupId,
    required String ideaId,
    required String name,
    String description = '',
  }) async {
    final userId = this.userId;
    if (userId == null) return null;

    try {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final feature = Feature(
        id: id,
        name: name,
        description: description,
        priority: Priority.medium,
        status: FeatureStatus.backlog,
        votes: [],
      );

      await _ideasCollection(groupId).doc(ideaId).update({
        'features': FieldValue.arrayUnion([feature.toJson()]),
      });

      print('addFeature: Success adding $name');
      return feature;
    } catch (e) {
      print('addFeature ERROR: $e');
      return null;
    }
  }

  /// Update feature status
  Future<bool> updateFeatureStatus({
    required String groupId,
    required String ideaId,
    required String featureId,
    required FeatureStatus status,
  }) async {
    try {
      final ideaDoc = await _ideasCollection(groupId).doc(ideaId).get();
      if (!ideaDoc.exists) return false;

      final data = ideaDoc.data()!;
      final List<dynamic> featuresRaw = data['features'] ?? [];

      final updatedFeatures = featuresRaw.map((f) {
        final featureMap = Map<String, dynamic>.from(f as Map);
        if (featureMap['id'] == featureId) {
          featureMap['status'] = status.name;
        }
        return featureMap;
      }).toList();

      await _ideasCollection(
        groupId,
      ).doc(ideaId).update({'features': updatedFeatures});
      return true;
    } catch (e) {
      print('updateFeatureStatus ERROR: $e');
      return false;
    }
  }

  /// Helper to notify all group members
  Future<void> _notifyGroupMembers({
    required String groupId,
    required String excludeUserId,
    required String type,
    required String title,
    required String message,
    String? ideaId,
    String? ideaName,
  }) async {
    try {
      final membersSnapshot = await _firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .get();

      final notificationsService = NotificationsService();
      for (final doc in membersSnapshot.docs) {
        if (doc.id != excludeUserId) {
          await notificationsService.sendNotification(
            toUserId: doc.id,
            type: type,
            title: title,
            message: message,
            ideaId: ideaId,
            ideaName: ideaName,
          );
        }
      }
    } catch (e) {
      // Silently fail notifications
    }
  }

  // ==================== UPVOTE METHODS ====================

  /// Toggle upvote for an idea (add if not voted, remove if already voted)
  Future<void> toggleVote(String groupId, String ideaId) async {
    final userId = _userId;
    if (userId == null) return;

    try {
      final voteDoc = _votesCollection(groupId, ideaId).doc(userId);
      final snapshot = await voteDoc.get();

      if (snapshot.exists) {
        // User has voted - remove vote
        await voteDoc.delete();
        print('toggleVote: Removed vote from $ideaId');
      } else {
        // Get user name for the vote
        final userName = _userName ?? 'Unknown';
        // User hasn't voted - add vote
        final vote = Vote(
          userId: userId,
          userName: userName,
          rating: 5, // Default for upvote
          createdAt: DateTime.now(),
        );
        await voteDoc.set(vote.toJson());
        print('toggleVote: Added vote to $ideaId');
      }
    } catch (e) {
      // Fail silently
    }
  }

  /// Stream the total vote count for an idea (real-time)
  Stream<int> streamVoteCount(String groupId, String ideaId) {
    return _votesCollection(
      groupId,
      ideaId,
    ).snapshots().map((snapshot) => snapshot.docs.length);
  }

  /// Stream to check if current user has voted for an idea (real-time)
  Stream<bool> streamUserVoteStatus(String groupId, String ideaId) {
    final userId = _userId;
    if (userId == null) {
      return Stream.value(false);
    }

    return _votesCollection(
      groupId,
      ideaId,
    ).doc(userId).snapshots().map((snapshot) => snapshot.exists);
  }

  /// Toggle upvote for a feature (updates feature's votes array in idea document)
  Future<void> toggleFeatureVote({
    required String groupId,
    required String ideaId,
    required String featureId,
  }) async {
    final userId = _userId;
    if (userId == null) return;

    try {
      final ideaDoc = await _ideasCollection(groupId).doc(ideaId).get();
      if (!ideaDoc.exists) {
        print('toggleFeatureVote: Idea not found');
        return;
      }

      final data = ideaDoc.data()!;
      final List<dynamic> features = data['features'] ?? [];
      print('toggleFeatureVote: Found ${features.length} features');

      final updatedFeatures = features.map((f) {
        final featureMap = Map<String, dynamic>.from(f as Map);
        if (featureMap['id'] == featureId) {
          final List<String> votes = List<String>.from(
            (featureMap['votes'] as List<dynamic>?) ?? [],
          );
          if (votes.contains(userId)) {
            votes.remove(userId);
            print('toggleFeatureVote: Removed vote from feature $featureId');
          } else {
            votes.add(userId);
            print('toggleFeatureVote: Added vote to feature $featureId');
          }
          featureMap['votes'] = votes;
        }
        return featureMap;
      }).toList();

      await _ideasCollection(
        groupId,
      ).doc(ideaId).update({'features': updatedFeatures});
      print('toggleFeatureVote: Update complete');
    } catch (e) {
      print('toggleFeatureVote ERROR: $e');
    }
  }
}
