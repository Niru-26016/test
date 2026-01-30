import 'package:flutter/material.dart';

/// Type of comment - regular comment, suggestion, or question
enum CommentType { comment, suggestion, question }

/// Represents a comment on a public idea
class Comment {
  final String id;
  final String ideaId;
  final String authorId;
  final String authorName;
  final CommentType type;
  final String content;
  final DateTime createdAt;
  final int replyCount;

  Comment({
    required this.id,
    required this.ideaId,
    required this.authorId,
    required this.authorName,
    required this.type,
    required this.content,
    required this.createdAt,
    this.replyCount = 0,
  });

  /// Create a Comment from JSON map
  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as String,
      ideaId: json['ideaId'] as String,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String? ?? 'Anonymous',
      type: CommentType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => CommentType.comment,
      ),
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      replyCount: json['replyCount'] as int? ?? 0,
    );
  }

  /// Convert Comment to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ideaId': ideaId,
      'authorId': authorId,
      'authorName': authorName,
      'type': type.name,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'replyCount': replyCount,
    };
  }

  /// Get display name for comment type
  String get typeDisplayName {
    switch (type) {
      case CommentType.comment:
        return 'Comment';
      case CommentType.suggestion:
        return 'Suggestion';
      case CommentType.question:
        return 'Question';
    }
  }

  /// Get icon for comment type
  IconData get typeIcon {
    switch (type) {
      case CommentType.comment:
        return Icons.chat_bubble_outline;
      case CommentType.suggestion:
        return Icons.lightbulb_outline;
      case CommentType.question:
        return Icons.help_outline;
    }
  }
}
