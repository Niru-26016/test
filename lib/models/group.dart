import 'dart:math';

/// Role of a member in a group
enum GroupRole { owner, admin, member }

/// Represents a member in a group
class GroupMember {
  final String userId;
  final String userName;
  final GroupRole role;
  final DateTime joinedAt;

  GroupMember({
    required this.userId,
    required this.userName,
    required this.role,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['userId'] as String,
      userName: json['userName'] as String? ?? 'Unknown',
      role: GroupRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => GroupRole.member,
      ),
      joinedAt: DateTime.parse(json['joinedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'role': role.name,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }

  /// Check if member can kick other members
  bool get canKick => role == GroupRole.owner || role == GroupRole.admin;

  /// Check if member can change roles
  bool get canManageRoles => role == GroupRole.owner;

  /// Check if member can delete the group
  bool get canDeleteGroup => role == GroupRole.owner;

  /// Display name for role
  String get roleDisplayName {
    switch (role) {
      case GroupRole.owner:
        return 'Owner';
      case GroupRole.admin:
        return 'Admin';
      case GroupRole.member:
        return 'Member';
    }
  }
}

/// Represents a collaboration group
class Group {
  final String id;
  final String name;
  final String description;
  final String ownerId;
  final String ownerName;
  final String inviteCode;
  final DateTime createdAt;
  final int memberCount;
  final List<String> memberIds; // Array for efficient querying
  static const int maxMembers = 10;

  Group({
    required this.id,
    required this.name,
    this.description = '',
    required this.ownerId,
    required this.ownerName,
    required this.inviteCode,
    required this.createdAt,
    this.memberCount = 1,
    this.memberIds = const [],
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      ownerId: json['ownerId'] as String,
      ownerName: json['ownerName'] as String? ?? 'Unknown',
      inviteCode: json['inviteCode'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      memberCount: json['memberCount'] as int? ?? 1,
      memberIds: (json['memberIds'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'inviteCode': inviteCode,
      'createdAt': createdAt.toIso8601String(),
      'memberCount': memberCount,
      'memberIds': memberIds,
    };
  }

  /// Generate a random 9-character invite code (e.g., "ABCD-A3X9")
  static String generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();

    // Generate 4-char prefix
    final prefix = List.generate(
      4,
      (_) => chars[random.nextInt(chars.length)],
    ).join();

    // Generate 4-char suffix
    final suffix = List.generate(
      4,
      (_) => chars[random.nextInt(chars.length)],
    ).join();

    return '$prefix-$suffix';
  }

  /// Check if group can accept more members
  bool get canAddMembers => memberCount < maxMembers;

  /// Get remaining member slots
  int get remainingSlots => maxMembers - memberCount;

  /// Create a copy with updated fields
  Group copyWith({
    String? id,
    String? name,
    String? description,
    String? ownerId,
    String? ownerName,
    String? inviteCode,
    DateTime? createdAt,
    int? memberCount,
    List<String>? memberIds,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ownerId: ownerId ?? this.ownerId,
      ownerName: ownerName ?? this.ownerName,
      inviteCode: inviteCode ?? this.inviteCode,
      createdAt: createdAt ?? this.createdAt,
      memberCount: memberCount ?? this.memberCount,
      memberIds: memberIds ?? this.memberIds,
    );
  }
}
