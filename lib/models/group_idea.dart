import 'feature.dart';

/// Represents a vote on a group idea
class Vote {
  final String userId;
  final String userName;
  final int rating; // 1-5 stars
  final DateTime createdAt;

  Vote({
    required this.userId,
    required this.userName,
    required this.rating,
    required this.createdAt,
  });

  factory Vote.fromJson(Map<String, dynamic> json) {
    return Vote(
      userId: (json['userId'] ?? json['oderId'] ?? '').toString(),
      userName: (json['userName'] ?? 'Unknown').toString(),
      rating: json['rating'] as int? ?? 3,
      createdAt: json['createdAt'] != null
          ? (json['createdAt'] is String
                ? DateTime.parse(json['createdAt'] as String)
                : (json['createdAt'] as dynamic).toDate())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

/// Represents an idea within a group (with features like regular ideas)
class GroupIdea {
  final String id;
  final String groupId;
  final String name;
  final String description;
  final String authorId;
  final String authorName;
  final String? sharedFromIdeaId; // If shared from personal/public
  final String? sharedFromType; // 'personal' or 'public'
  final DateTime createdAt;
  final List<Vote> votes;
  final List<Feature> features; // Features like regular ideas
  final bool isApproved; // Whether the idea has been approved by admin

  GroupIdea({
    required this.id,
    required this.groupId,
    required this.name,
    this.description = '',
    required this.authorId,
    required this.authorName,
    this.sharedFromIdeaId,
    this.sharedFromType,
    required this.createdAt,
    this.votes = const [],
    this.features = const [],
    this.isApproved = false,
  });

  factory GroupIdea.fromJson(Map<String, dynamic> json) {
    try {
      return GroupIdea(
        id: (json['id'] ?? '').toString(),
        groupId: (json['groupId'] ?? '').toString(),
        name: (json['name'] ?? 'Untitled').toString(),
        description: (json['description'] ?? '').toString(),
        authorId: (json['authorId'] ?? '').toString(),
        authorName: (json['authorName'] ?? 'Unknown').toString(),
        sharedFromIdeaId: json['sharedFromIdeaId']?.toString(),
        sharedFromType: json['sharedFromType']?.toString(),
        createdAt: json['createdAt'] != null
            ? (json['createdAt'] is String
                  ? DateTime.parse(json['createdAt'] as String)
                  : (json['createdAt'] as dynamic).toDate())
            : DateTime.now(),
        votes:
            (json['votes'] as List<dynamic>?)
                ?.map((v) => Vote.fromJson(v as Map<String, dynamic>))
                .toList() ??
            [],
        features:
            (json['features'] as List<dynamic>?)
                ?.map((f) => Feature.fromJson(f as Map<String, dynamic>))
                .toList() ??
            [],
        isApproved: json['isApproved'] as bool? ?? false,
      );
    } catch (e) {
      print('GroupIdea.fromJson ERROR: $e');
      print('JSON: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'name': name,
      'description': description,
      'authorId': authorId,
      'authorName': authorName,
      'sharedFromIdeaId': sharedFromIdeaId,
      'sharedFromType': sharedFromType,
      'createdAt': createdAt.toIso8601String(),
      'features': features.map((f) => f.toJson()).toList(),
      'isApproved': isApproved,
      // Votes stored in subcollection, not here
    };
  }

  /// Calculate average rating
  double get averageRating {
    if (votes.isEmpty) return 0;
    return votes.map((v) => v.rating).reduce((a, b) => a + b) / votes.length;
  }

  /// Get total vote count
  int get voteCount => votes.length;

  /// Check if a user has voted
  bool hasUserVoted(String userId) {
    return votes.any((v) => v.userId == userId);
  }

  /// Get user's vote
  Vote? getUserVote(String userId) {
    try {
      return votes.firstWhere((v) => v.userId == userId);
    } catch (_) {
      return null;
    }
  }

  /// Check if this idea was shared from somewhere
  bool get isShared => sharedFromIdeaId != null;

  /// Create copy with votes
  GroupIdea copyWithVotes(List<Vote> newVotes) {
    return GroupIdea(
      id: id,
      groupId: groupId,
      name: name,
      description: description,
      authorId: authorId,
      authorName: authorName,
      sharedFromIdeaId: sharedFromIdeaId,
      sharedFromType: sharedFromType,
      createdAt: createdAt,
      votes: newVotes,
      features: features,
      isApproved: isApproved,
    );
  }

  /// Create copy with updated features
  GroupIdea copyWithFeatures(List<Feature> newFeatures) {
    return GroupIdea(
      id: id,
      groupId: groupId,
      name: name,
      description: description,
      authorId: authorId,
      authorName: authorName,
      sharedFromIdeaId: sharedFromIdeaId,
      sharedFromType: sharedFromType,
      createdAt: createdAt,
      votes: votes,
      features: newFeatures,
      isApproved: isApproved,
    );
  }
}
