import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/group.dart';
import 'auth_service.dart';
import 'notifications_service.dart';

/// Service for managing groups
class GroupsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;
  String? get currentUserId => _auth.currentUser?.uid;
  String? get _userName =>
      _auth.currentUser?.displayName ??
      _auth.currentUser?.email?.split('@').first;

  CollectionReference<Map<String, dynamic>> get _groupsCollection =>
      _firestore.collection('groups');

  /// Create a new group
  Future<({Group? group, String? error})> createGroup({
    required String name,
    String description = '',
  }) async {
    final userId = _userId;
    // Ensure we use a valid username even if auth profile is incomplete
    final userName = _userName ?? 'User';
    if (userId == null) {
      return (group: null, error: 'You must be logged in to create a group');
    }

    Future<Group?> attemptCreation() async {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final inviteCode = Group.generateInviteCode();

      print(
        'createGroup: Creating group with id=$id, ownerId=$userId, ownerName=$userName',
      );

      final group = Group(
        id: id,
        name: name,
        description: description,
        ownerId: userId,
        ownerName: userName,
        inviteCode: inviteCode,
        createdAt: DateTime.now(),
        memberCount: 1,
        memberIds: [
          userId,
        ], // Include creator in memberIds for efficient querying
      );

      // Save group
      await _groupsCollection.doc(id).set(group.toJson());
      print('createGroup: Group document created');

      // Add owner as first member
      final ownerMember = GroupMember(
        userId: userId,
        userName: userName,
        role: GroupRole.owner,
        joinedAt: DateTime.now(),
      );
      await _groupsCollection
          .doc(id)
          .collection('members')
          .doc(userId)
          .set(ownerMember.toJson());
      print(
        'createGroup: Owner added to members subcollection with docId=$userId',
      );

      // FORCE TRIGGER: Update the group doc to trigger stream listener
      await _groupsCollection.doc(id).update({
        'updatedAt': DateTime.now().toIso8601String(),
      });
      print('createGroup: Group doc updated to trigger stream');

      return group;
    }

    try {
      final group = await attemptCreation();
      return (group: group, error: null);
    } catch (e) {
      final errorMsg = e.toString().toLowerCase();
      // Auto-repair if permission denied
      if (errorMsg.contains('permission-denied') ||
          errorMsg.contains('permission denied')) {
        try {
          print(
            'Create group failed with permission error. Attempting auto-repair...',
          );
          final authService =
              AuthService(); // Assuming AuthService is accessible or imported
          await authService.repairUserProfile();
          // Retry once
          final group = await attemptCreation();
          return (group: group, error: null);
        } catch (retryError) {
          return (
            group: null,
            error:
                'Permission denied. Please verify your internet connection or try re-logging in. ($retryError)',
          );
        }
      }
      return (group: null, error: 'Failed to create group: $e');
    }
  }

  /// Get all groups the user is a member of
  Future<List<Group>> getMyGroups() async {
    final userId = _userId;
    if (userId == null) return [];

    try {
      // Query all groups where user is a member
      final groupsSnapshot = await _groupsCollection.get();
      final List<Group> userGroups = [];

      for (final doc in groupsSnapshot.docs) {
        final memberDoc = await doc.reference
            .collection('members')
            .doc(userId)
            .get();
        if (memberDoc.exists) {
          userGroups.add(Group.fromJson(doc.data()));
        }
      }

      return userGroups;
    } catch (e) {
      return [];
    }
  }

  /// Stream of groups the user is a member of (real-time updates)
  Stream<List<Group>> streamMyGroups() {
    final userId = _auth.currentUser?.uid;
    print('streamMyGroups: userId = $userId');

    if (userId == null) {
      print('streamMyGroups: No user logged in, returning empty stream');
      return Stream.value(<Group>[]);
    }

    // Use memberIds array for efficient querying
    return _groupsCollection
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          print(
            'streamMyGroups: Query returned ${snapshot.docs.length} groups',
          );
          final groups = <Group>[];
          for (final doc in snapshot.docs) {
            try {
              print(
                'streamMyGroups: Parsing group ${doc.id}, data: ${doc.data()}',
              );
              groups.add(Group.fromJson(doc.data()));
              print('streamMyGroups: Successfully parsed group ${doc.id}');
            } catch (e) {
              print('streamMyGroups: ERROR parsing group ${doc.id}: $e');
            }
          }
          return groups;
        })
        .handleError((error) {
          print('streamMyGroups: Stream error: $error');
          return <Group>[];
        });
  }

  /// Stream a single group by ID (real-time updates)
  Stream<Group?> streamGroupById(String groupId) {
    return _groupsCollection.doc(groupId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return Group.fromJson(doc.data()!);
      }
      return null;
    });
  }

  /// Stream group members (real-time updates)
  Stream<List<GroupMember>> streamGroupMembers(String groupId) {
    return _groupsCollection
        .doc(groupId)
        .collection('members')
        .orderBy('joinedAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => GroupMember.fromJson(doc.data()))
              .toList(),
        );
  }

  /// Stream user's role in a group (real-time updates)
  Stream<GroupRole?> streamUserRole(String groupId) {
    final userId = _userId;
    if (userId == null) return Stream.value(null);

    return _groupsCollection
        .doc(groupId)
        .collection('members')
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (doc.exists && doc.data() != null) {
            return GroupMember.fromJson(doc.data()!).role;
          }
          return null;
        });
  }

  /// Stream pending join requests (real-time updates)
  Stream<List<Map<String, dynamic>>> streamJoinRequests(String groupId) {
    return _groupsCollection
        .doc(groupId)
        .collection('join_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  /// Stream pending group invites for the current user
  Stream<List<Map<String, dynamic>>> streamMyGroupInvites() {
    final userId = _userId;
    if (userId == null) return Stream.value([]);

    return _firestore
        .collection('group_invites')
        .where('invitedUserId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList(),
        );
  }

  /// Get a single group by ID
  Future<Group?> getGroupById(String groupId) async {
    try {
      final doc = await _groupsCollection.doc(groupId).get();
      if (doc.exists && doc.data() != null) {
        return Group.fromJson(doc.data()!);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Get group members
  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    try {
      final snapshot = await _groupsCollection
          .doc(groupId)
          .collection('members')
          .orderBy('joinedAt')
          .get();
      return snapshot.docs
          .map((doc) => GroupMember.fromJson(doc.data()))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Get user's role in a group
  Future<GroupRole?> getUserRole(String groupId) async {
    final userId = _userId;
    if (userId == null) return null;

    try {
      final doc = await _groupsCollection
          .doc(groupId)
          .collection('members')
          .doc(userId)
          .get();
      if (doc.exists && doc.data() != null) {
        return GroupMember.fromJson(doc.data()!).role;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  /// Request to join a group using invite code (requires owner approval)
  Future<String?> requestToJoin(String code) async {
    final userId = _userId;
    final userName = _userName;
    if (userId == null) return 'Not logged in';

    try {
      // Find group with this invite code
      final snapshot = await _groupsCollection
          .where('inviteCode', isEqualTo: code.toUpperCase())
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return 'Invalid invite code';
      }

      final groupDoc = snapshot.docs.first;
      final group = Group.fromJson(groupDoc.data());

      // Check if already a member
      final memberDoc = await groupDoc.reference
          .collection('members')
          .doc(userId)
          .get();
      if (memberDoc.exists) {
        return 'Already a member of this group';
      }

      // Check if already requested
      final requestDoc = await groupDoc.reference
          .collection('join_requests')
          .doc(userId)
          .get();
      if (requestDoc.exists) {
        return 'Already requested to join this group';
      }

      // Check member limit
      if (!group.canAddMembers) {
        return 'Group is full (max ${Group.maxMembers} members)';
      }

      // Create join request
      await groupDoc.reference.collection('join_requests').doc(userId).set({
        'userId': userId,
        'userName': userName ?? 'Unknown',
        'requestedAt': DateTime.now().toIso8601String(),
        'status': 'pending',
      });

      // Notify owner
      final notificationsService = NotificationsService();
      await notificationsService.sendNotification(
        toUserId: group.ownerId,
        type: 'join_request',
        title: 'Join Request',
        message: '$userName wants to join "${group.name}"',
        ideaId: group.id,
        ideaName: group.name,
      );

      return null; // Success - request sent
    } catch (e) {
      return 'Failed to request to join';
    }
  }

  /// Get pending join requests for a group
  Future<List<Map<String, dynamic>>> getJoinRequests(String groupId) async {
    try {
      final snapshot = await _groupsCollection
          .doc(groupId)
          .collection('join_requests')
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt')
          .get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      return [];
    }
  }

  /// Approve a join request
  Future<bool> approveJoinRequest(String groupId, String userId) async {
    final currentUserId = _userId;
    if (currentUserId == null) return false;

    try {
      // Check if current user is owner or admin
      final userRole = await getUserRole(groupId);
      if (userRole != GroupRole.owner && userRole != GroupRole.admin) {
        return false;
      }

      final group = await getGroupById(groupId);
      if (group == null || !group.canAddMembers) return false;

      // Get request data
      final requestDoc = await _groupsCollection
          .doc(groupId)
          .collection('join_requests')
          .doc(userId)
          .get();
      if (!requestDoc.exists) return false;

      final requestData = requestDoc.data()!;

      // Add as member
      final newMember = GroupMember(
        userId: userId,
        userName: requestData['userName'] ?? 'Unknown',
        role: GroupRole.member,
        joinedAt: DateTime.now(),
      );
      await _groupsCollection
          .doc(groupId)
          .collection('members')
          .doc(userId)
          .set(newMember.toJson());

      // Update member count and memberIds array
      await _groupsCollection.doc(groupId).update({
        'memberIds': FieldValue.arrayUnion([
          userId,
        ]), // Add to memberIds for querying
        'memberCount': FieldValue.increment(1),
      });

      // Delete the request
      await requestDoc.reference.delete();

      // Notify the user
      final notificationsService = NotificationsService();
      await notificationsService.sendNotification(
        toUserId: userId,
        type: 'join_approved',
        title: 'Request Approved!',
        message: 'You are now a member of "${group.name}"',
        ideaId: groupId,
        ideaName: group.name,
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Reject a join request
  Future<bool> rejectJoinRequest(String groupId, String userId) async {
    final currentUserId = _userId;
    if (currentUserId == null) return false;

    try {
      // Check if current user is owner or admin
      final userRole = await getUserRole(groupId);
      if (userRole != GroupRole.owner && userRole != GroupRole.admin) {
        return false;
      }

      final group = await getGroupById(groupId);

      // Delete the request
      await _groupsCollection
          .doc(groupId)
          .collection('join_requests')
          .doc(userId)
          .delete();

      // Notify the user
      final notificationsService = NotificationsService();
      await notificationsService.sendNotification(
        toUserId: userId,
        type: 'join_rejected',
        title: 'Request Declined',
        message: 'Your request to join "${group?.name}" was declined',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Invite a user by username/email
  /// Returns: 'success', 'not_found', 'self_invite', 'already_member', 'error'
  Future<String> inviteByUsername(String groupId, String username) async {
    final userId = _userId;
    final userName = _userName;
    if (userId == null) return 'error';

    try {
      String? targetUserId;
      String? targetUserName;

      // Try to find user by email in users collection
      var usersSnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: username.toLowerCase())
          .limit(1)
          .get();

      if (usersSnapshot.docs.isEmpty) {
        // Try searching by displayName
        usersSnapshot = await _firestore
            .collection('users')
            .where('displayName', isEqualTo: username)
            .limit(1)
            .get();
      }

      if (usersSnapshot.docs.isEmpty) {
        // Try searching by username field
        usersSnapshot = await _firestore
            .collection('users')
            .where('username', isEqualTo: username)
            .limit(1)
            .get();
      }

      if (usersSnapshot.docs.isNotEmpty) {
        targetUserId = usersSnapshot.docs.first.id;
        final userData = usersSnapshot.docs.first.data();
        targetUserName =
            userData['displayName'] ?? userData['email'] ?? username;
      }

      // If still not found, check if the username looks like a userId
      if (targetUserId == null && username.length > 10) {
        final userDoc = await _firestore
            .collection('users')
            .doc(username)
            .get();
        if (userDoc.exists) {
          targetUserId = username;
          final userData = userDoc.data();
          targetUserName =
              userData?['displayName'] ?? userData?['email'] ?? username;
        }
      }

      if (targetUserId == null) {
        print('Invite failed: User not found for "$username"');
        return 'not_found';
      }

      // Prevent inviting yourself
      if (targetUserId == userId) {
        print('Invite failed: Cannot invite yourself');
        return 'self_invite';
      }

      // Get group info
      final group = await getGroupById(groupId);
      if (group == null) {
        print('Invite failed: Group not found');
        return 'error';
      }

      // Check if user is already a member
      final memberDoc = await _groupsCollection
          .doc(groupId)
          .collection('members')
          .doc(targetUserId)
          .get();
      if (memberDoc.exists) {
        print('Invite failed: User is already a member');
        return 'already_member';
      }

      // Send notification/invite
      final notificationsService = NotificationsService();
      await notificationsService.sendNotification(
        toUserId: targetUserId,
        type: 'group_invite',
        title: 'Group Invitation!',
        message: '$userName invited you to join "${group.name}"',
        ideaId: groupId,
        ideaName: group.name,
      );

      // Store pending invite
      await _firestore
          .collection('group_invites')
          .doc('${groupId}_$targetUserId')
          .set({
            'groupId': groupId,
            'groupName': group.name,
            'invitedUserId': targetUserId,
            'invitedUserName': targetUserName,
            'invitedBy': userId,
            'invitedByName': userName,
            'createdAt': DateTime.now().toIso8601String(),
            'status': 'pending',
          });

      print('Invite success: Sent invite to $targetUserName');
      return 'success';
    } catch (e) {
      print('Invite failed with error: $e');
      return 'error';
    }
  }

  /// Accept a group invite and join the group
  Future<bool> acceptGroupInvite(String groupId) async {
    final userId = _userId;
    final userName = _userName;
    print(
      'acceptGroupInvite: Starting for groupId=$groupId, userId=$userId, userName=$userName',
    );

    if (userId == null) {
      print('acceptGroupInvite: userId is null, returning false');
      return false;
    }

    try {
      // Check if already a member
      final existingMember = await _groupsCollection
          .doc(groupId)
          .collection('members')
          .doc(userId)
          .get();
      if (existingMember.exists) {
        print('acceptGroupInvite: Already a member of this group');
        return true; // Already a member, consider it successful
      }

      // Get group info for validation
      final group = await getGroupById(groupId);
      if (group == null) {
        print('acceptGroupInvite: Group not found');
        return false;
      }
      print('acceptGroupInvite: Found group "${group.name}"');

      // Add user as a member to subcollection
      print('acceptGroupInvite: Adding user to members subcollection...');
      await _groupsCollection
          .doc(groupId)
          .collection('members')
          .doc(userId)
          .set({
            'userId': userId,
            'userName': userName ?? 'Unknown',
            'role': 'member',
            'joinedAt': DateTime.now().toIso8601String(),
          });
      print('acceptGroupInvite: User added to members subcollection');

      // Delete the pending invite
      print('acceptGroupInvite: Deleting pending invite...');
      await _firestore
          .collection('group_invites')
          .doc('${groupId}_$userId')
          .delete();
      print('acceptGroupInvite: Pending invite deleted');

      // Update the group doc with memberIds and memberCount
      print('acceptGroupInvite: Updating group doc with memberIds=$userId...');
      await _groupsCollection.doc(groupId).update({
        'memberIds': FieldValue.arrayUnion([userId]),
        'memberCount': FieldValue.increment(1),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      print('acceptGroupInvite: Group doc updated successfully!');

      print('acceptGroupInvite: Successfully joined group: ${group.name}');
      return true;
    } catch (e, stackTrace) {
      print('acceptGroupInvite: ERROR: $e');
      print('acceptGroupInvite: StackTrace: $stackTrace');
      return false;
    }
  }

  /// Decline a group invite
  Future<void> declineGroupInvite(String inviteId) async {
    try {
      await _firestore.collection('group_invites').doc(inviteId).delete();
      print('Declined invite: $inviteId');
    } catch (e) {
      print('Decline invite failed: $e');
    }
  }

  /// Leave a group
  Future<bool> leaveGroup(String groupId) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final group = await getGroupById(groupId);
      if (group == null) return false;

      // Owner cannot leave, must delete or transfer
      if (group.ownerId == userId) {
        return false;
      }

      // Remove from members
      await _groupsCollection
          .doc(groupId)
          .collection('members')
          .doc(userId)
          .delete();

      // Update member count and memberIds array
      await _groupsCollection.doc(groupId).update({
        'memberIds': FieldValue.arrayRemove([userId]), // Remove from memberIds
        'memberCount': FieldValue.increment(-1),
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Remove a member (kick)
  Future<bool> removeMember(String groupId, String memberId) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      // Check if current user has permission
      final userRole = await getUserRole(groupId);
      if (userRole == null ||
          !GroupMember(
            userId: userId,
            userName: '',
            role: userRole,
            joinedAt: DateTime.now(),
          ).canKick) {
        return false;
      }

      // Get target member's role
      final targetDoc = await _groupsCollection
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .get();
      if (!targetDoc.exists) return false;

      final targetMember = GroupMember.fromJson(targetDoc.data()!);

      // Admin cannot kick other admins or owner
      if (userRole == GroupRole.admin &&
          targetMember.role != GroupRole.member) {
        return false;
      }

      // Remove member
      await _groupsCollection
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .delete();

      // Update count and memberIds array
      await _groupsCollection.doc(groupId).update({
        'memberIds': FieldValue.arrayRemove([
          memberId,
        ]), // Remove from memberIds
        'memberCount': FieldValue.increment(-1),
      });

      // Notify kicked member
      final group = await getGroupById(groupId);
      final notificationsService = NotificationsService();
      await notificationsService.sendNotification(
        toUserId: memberId,
        type: 'group_kick',
        title: 'Removed from group',
        message: 'You were removed from "${group?.name ?? 'a group'}"',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Update member role
  Future<bool> updateMemberRole(
    String groupId,
    String memberId,
    GroupRole newRole,
  ) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      // Only owner can change roles
      final userRole = await getUserRole(groupId);
      if (userRole != GroupRole.owner) return false;

      // Cannot change owner's role
      final group = await getGroupById(groupId);
      if (group?.ownerId == memberId) return false;

      await _groupsCollection
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .update({'role': newRole.name});

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Regenerate invite code
  Future<String?> regenerateInviteCode(String groupId) async {
    final userId = _userId;
    if (userId == null) return null;

    try {
      final userRole = await getUserRole(groupId);
      if (userRole != GroupRole.owner && userRole != GroupRole.admin) {
        return null;
      }

      final newCode = Group.generateInviteCode();
      await _groupsCollection.doc(groupId).update({'inviteCode': newCode});
      return newCode;
    } catch (e) {
      return null;
    }
  }

  /// Delete a group (owner only)
  Future<bool> deleteGroup(String groupId) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final group = await getGroupById(groupId);
      if (group?.ownerId != userId) return false;

      // Delete all members
      final membersSnapshot = await _groupsCollection
          .doc(groupId)
          .collection('members')
          .get();
      for (final doc in membersSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete all ideas (with votes)
      final ideasSnapshot = await _groupsCollection
          .doc(groupId)
          .collection('ideas')
          .get();
      for (final doc in ideasSnapshot.docs) {
        final votesSnapshot = await doc.reference.collection('votes').get();
        for (final voteDoc in votesSnapshot.docs) {
          await voteDoc.reference.delete();
        }
        await doc.reference.delete();
      }

      // Delete group
      await _groupsCollection.doc(groupId).delete();

      return true;
    } catch (e) {
      return false;
    }
  }
}
