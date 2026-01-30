/// Represents a reply to a comment
class Reply {
  final String id;
  final String commentId;
  final String authorId;
  final String authorName;
  final String content;
  final DateTime createdAt;

  Reply({
    required this.id,
    required this.commentId,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.createdAt,
  });

  /// Create a Reply from JSON map
  factory Reply.fromJson(Map<String, dynamic> json) {
    return Reply(
      id: json['id'] as String,
      commentId: json['commentId'] as String,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String? ?? 'Anonymous',
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// Convert Reply to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'commentId': commentId,
      'authorId': authorId,
      'authorName': authorName,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
