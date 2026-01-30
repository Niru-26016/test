/// Represents a user in the application
class User {
  final String id;
  final String username;
  final String email;
  final String displayName;
  final int avatarColorValue;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    required this.avatarColorValue,
    required this.createdAt,
  });

  /// Create a User from JSON map
  factory User.fromJson(Map<String, dynamic> json) {
    // Parse createdAt - handle both String and Timestamp formats
    DateTime createdAt;
    final createdAtValue = json['createdAt'];
    if (createdAtValue is String) {
      createdAt = DateTime.tryParse(createdAtValue) ?? DateTime.now();
    } else if (createdAtValue != null &&
        createdAtValue.runtimeType.toString().contains('Timestamp')) {
      // Handle Firestore Timestamp
      createdAt = (createdAtValue as dynamic).toDate();
    } else {
      createdAt = DateTime.now();
    }

    return User(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'User',
      avatarColorValue: json['avatarColorValue'] as int? ?? 0xFF6750A4,
      createdAt: createdAt,
    );
  }

  /// Convert User to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'displayName': displayName,
      'avatarColorValue': avatarColorValue,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  User copyWith({
    String? id,
    String? username,
    String? email,
    String? displayName,
    int? avatarColorValue,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      avatarColorValue: avatarColorValue ?? this.avatarColorValue,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Get initials for avatar
  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (displayName.isNotEmpty) {
      return displayName[0].toUpperCase();
    } else if (username.isNotEmpty) {
      return username[0].toUpperCase();
    }
    return '?';
  }
}
