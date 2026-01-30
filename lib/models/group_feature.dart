/// Status for a group feature workflow
enum FeatureStatus { pending, approved, implementing, completed, rejected }

/// Represents a feature suggestion in a group idea
class GroupFeature {
  final String id;
  final String name;
  final String description;
  final String authorId;
  final String authorName;
  final FeatureStatus status;
  final Map<String, int> ratings; // userId -> rating (1-5)
  final DateTime createdAt;

  GroupFeature({
    required this.id,
    required this.name,
    this.description = '',
    required this.authorId,
    required this.authorName,
    this.status = FeatureStatus.pending,
    this.ratings = const {},
    required this.createdAt,
  });

  factory GroupFeature.fromJson(Map<String, dynamic> json) {
    return GroupFeature(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String? ?? 'Unknown',
      status: FeatureStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => FeatureStatus.pending,
      ),
      ratings: Map<String, int>.from(json['ratings'] ?? {}),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'authorId': authorId,
      'authorName': authorName,
      'status': status.name,
      'ratings': ratings,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Average rating of the feature
  double get averageRating {
    if (ratings.isEmpty) return 0;
    return ratings.values.reduce((a, b) => a + b) / ratings.length;
  }

  /// Total number of ratings
  int get ratingCount => ratings.length;

  /// Check if user has rated
  bool hasUserRated(String userId) => ratings.containsKey(userId);

  /// Get user's rating
  int? getUserRating(String userId) => ratings[userId];

  /// Create copy with updated status
  GroupFeature copyWithStatus(FeatureStatus newStatus) {
    return GroupFeature(
      id: id,
      name: name,
      description: description,
      authorId: authorId,
      authorName: authorName,
      status: newStatus,
      ratings: ratings,
      createdAt: createdAt,
    );
  }

  /// Create copy with updated ratings
  GroupFeature copyWithRating(String userId, int rating) {
    final newRatings = Map<String, int>.from(ratings);
    newRatings[userId] = rating;
    return GroupFeature(
      id: id,
      name: name,
      description: description,
      authorId: authorId,
      authorName: authorName,
      status: status,
      ratings: newRatings,
      createdAt: createdAt,
    );
  }
}
