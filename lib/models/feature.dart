/// Priority level for a feature
enum Priority { low, medium, high }

/// Status of a feature in the development lifecycle
enum FeatureStatus { backlog, inProgress, done }

/// Represents a feature of an app/website idea
class Feature {
  final String id;
  final String name;
  final String description;
  final Priority priority;
  final FeatureStatus status;
  final List<String> votes; // User IDs who upvoted

  Feature({
    required this.id,
    required this.name,
    this.description = '',
    this.priority = Priority.medium,
    this.status = FeatureStatus.backlog,
    this.votes = const [],
  });

  /// Create a Feature from JSON map
  factory Feature.fromJson(Map<String, dynamic> json) {
    return Feature(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'New Feature').toString(),
      description: (json['description'] ?? '').toString(),
      priority: Priority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => Priority.medium,
      ),
      status: FeatureStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => FeatureStatus.backlog,
      ),
      votes:
          (json['votes'] as List<dynamic>?)
              ?.map((v) => v.toString())
              .toList() ??
          [],
    );
  }

  /// Convert Feature to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'priority': priority.name,
      'status': status.name,
      'votes': votes,
    };
  }

  /// Get vote count
  int get voteCount => votes.length;

  /// Check if user has voted
  bool hasVoted(String userId) => votes.contains(userId);

  /// Create a copy with updated fields
  Feature copyWith({
    String? id,
    String? name,
    String? description,
    Priority? priority,
    FeatureStatus? status,
    List<String>? votes,
  }) {
    return Feature(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      votes: votes ?? this.votes,
    );
  }

  /// Get display name for status
  String get statusDisplayName {
    switch (status) {
      case FeatureStatus.backlog:
        return 'Backlog';
      case FeatureStatus.inProgress:
        return 'In Progress';
      case FeatureStatus.done:
        return 'Done';
    }
  }
}
