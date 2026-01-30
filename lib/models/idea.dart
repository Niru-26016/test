import 'feature.dart';

/// Type of idea - website, mobile app, or both
enum IdeaType { website, mobile, both }

/// Stage of an idea in the development lifecycle
enum IdeaStage { ideation, implementation, completed }

/// Represents an app or website idea
class Idea {
  final String id;
  final String name;
  final String description;
  final IdeaType type;
  final IdeaStage stage;
  final List<Feature> features;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPublic;
  final String? ownerId;
  final String? ownerName;

  Idea({
    required this.id,
    required this.name,
    this.description = '',
    this.type = IdeaType.both,
    this.stage = IdeaStage.ideation,
    this.features = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isPublic = false,
    this.ownerId,
    this.ownerName,
  });

  /// Create an Idea from JSON map
  factory Idea.fromJson(Map<String, dynamic> json) {
    return Idea(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      type: IdeaType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => IdeaType.both,
      ),
      stage: IdeaStage.values.firstWhere(
        (e) => e.name == json['stage'],
        orElse: () => IdeaStage.ideation,
      ),
      features:
          (json['features'] as List<dynamic>?)
              ?.map((f) => Feature.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isPublic: json['isPublic'] as bool? ?? false,
      ownerId: json['ownerId'] as String?,
      ownerName: json['ownerName'] as String?,
    );
  }

  /// Convert Idea to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'stage': stage.name,
      'features': features.map((f) => f.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPublic': isPublic,
      'ownerId': ownerId,
      'ownerName': ownerName,
    };
  }

  /// Create a copy with updated fields
  Idea copyWith({
    String? id,
    String? name,
    String? description,
    IdeaType? type,
    IdeaStage? stage,
    List<Feature>? features,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPublic,
    String? ownerId,
    String? ownerName,
  }) {
    return Idea(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      stage: stage ?? this.stage,
      features: features ?? this.features,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPublic: isPublic ?? this.isPublic,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
    );
  }

  /// Get display name for idea type
  String get typeDisplayName {
    switch (type) {
      case IdeaType.website:
        return 'Website';
      case IdeaType.mobile:
        return 'Mobile App';
      case IdeaType.both:
        return 'Website & Mobile';
    }
  }

  /// Get display name for idea stage
  String get stageDisplayName {
    switch (stage) {
      case IdeaStage.ideation:
        return 'Ideation';
      case IdeaStage.implementation:
        return 'Execution';
      case IdeaStage.completed:
        return 'Completed';
    }
  }
}
