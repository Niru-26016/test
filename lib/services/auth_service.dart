import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart';
import 'notifications_service.dart';

/// Service for user authentication and profile management using Firebase
class AuthService {
  final auth.FirebaseAuth _firebaseAuth = auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  static const String _usersCollection = 'users';

  /// List of colors for user avatars
  static const List<int> avatarColors = [
    0xFF6750A4, // Purple
    0xFF3F51B5, // Indigo
    0xFF2196F3, // Blue
    0xFF00BCD4, // Cyan
    0xFF009688, // Teal
    0xFF4CAF50, // Green
    0xFFFF9800, // Orange
    0xFFE91E63, // Pink
    0xFF9C27B0, // Deep Purple
    0xFF795548, // Brown
  ];

  /// Check if username is available
  Future<bool> checkUsernameAvailability(String username) async {
    try {
      final userDocs = await _firestore
          .collection(_usersCollection)
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (userDocs.docs.isNotEmpty) return false;

      final pendingDocs = await _firestore
          .collection('pending_signups')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      return pendingDocs.docs.isEmpty;
    } catch (e) {
      // If permission denied (common for unauthenticated users),
      // we can't verify availability dynamically.
      // Return true to allow the user to try submitting.
      return true;
    }
  }

  /// Sign up a new user
  Future<({bool success, String? error, User? user})> signup({
    required String username,
    required String email,
    required String displayName,
    required String password,
  }) async {
    try {
      // Create user in Firebase Auth
      final userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final authUser = userCredential.user;
      if (authUser == null) {
        return (success: false, error: 'Failed to create user', user: null);
      }

      // Update the display name in Firebase Auth (so we can retrieve it on login)
      await authUser.updateDisplayName(displayName);

      // Check for username uniqueness
      // We do this after auth creation so we have permission to read Firestore
      final userDocs = await _firestore
          .collection(_usersCollection)
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      final pendingDocs = await _firestore
          .collection('pending_signups')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (userDocs.docs.isNotEmpty || pendingDocs.docs.isNotEmpty) {
        // Username taken - rollback (delete the auth user)
        await authUser.delete();
        return (success: false, error: 'Username already taken', user: null);
      }

      // Send email verification with app deep link
      final actionCodeSettings = auth.ActionCodeSettings(
        url: 'https://idex-01.web.app',
        handleCodeInApp: true,
        androidPackageName: 'com.niranjan.idex',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );
      await authUser.sendEmailVerification(actionCodeSettings);

      // Store username in a pending collection for later use after verification
      await _firestore.collection('pending_signups').doc(authUser.uid).set({
        'username': username,
        'email': email,
        'displayName': displayName,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Sign out after signup - user needs to verify email first
      await _firebaseAuth.signOut();

      return (success: true, error: null, user: null);
    } on auth.FirebaseAuthException catch (e) {
      return (success: false, error: e.message ?? 'Signup failed', user: null);
    } catch (e) {
      return (success: false, error: e.toString(), user: null);
    }
  }

  /// Login user
  Future<({bool success, String? error, User? user})> login({
    required String email,
    required String password,
  }) async {
    try {
      // Sign in with Firebase Auth
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final authUser = userCredential.user;
      if (authUser == null) {
        return (success: false, error: 'Login failed', user: null);
      }

      // Check if email is verified
      if (!authUser.emailVerified) {
        // Sign out since email is not verified
        await _firebaseAuth.signOut();
        return (
          success: false,
          error:
              'Please verify your email first. Check your inbox for the verification link.',
          user: null,
        );
      }

      // Fetch user profile from Firestore
      User? user = await _getUserProfile(authUser.uid);

      // If profile doesn't exist, create it from pending_signups data
      if (user == null) {
        // Get pending signup data
        final pendingDoc = await _firestore
            .collection('pending_signups')
            .doc(authUser.uid)
            .get();

        String username;
        String displayName;
        DateTime createdAt = DateTime.now();

        if (pendingDoc.exists && pendingDoc.data() != null) {
          final pendingData = pendingDoc.data()!;
          username =
              pendingData['username'] ??
              authUser.email?.split('@').first ??
              'user';
          displayName =
              pendingData['displayName'] ?? authUser.displayName ?? username;
          if (pendingData['createdAt'] != null) {
            createdAt = DateTime.parse(pendingData['createdAt']);
          }
        } else {
          username = authUser.email?.split('@').first ?? 'user';
          displayName = authUser.displayName ?? username;
        }

        // Create new user profile in main users collection
        user = User(
          id: authUser.uid,
          username: username,
          email: authUser.email ?? email,
          displayName: displayName,
          avatarColorValue: avatarColors[Random().nextInt(avatarColors.length)],
          createdAt: createdAt,
        );

        // Save to Firestore
        await _firestore.collection(_usersCollection).doc(user.id).set({
          'id': user.id,
          'uid': user.id,
          'username': user.username,
          'email': user.email,
          'displayName': user.displayName,
          'avatarColorValue': user.avatarColorValue,
          'createdAt': user.createdAt.toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
          'emailVerified': true,
          'createdGroups': [],
        }, SetOptions(merge: true));

        // Delete pending signup data
        await _firestore
            .collection('pending_signups')
            .doc(authUser.uid)
            .delete();
      }

      // Update FCM token
      await NotificationsService().updateFcmToken();

      return (success: true, error: null, user: user);
    } on auth.FirebaseAuthException catch (e) {
      // Provide user-friendly error messages
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'Email not found';
          break;
        case 'invalid-credential':
        case 'wrong-password':
          errorMessage = 'Invalid email or password. Please try again.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email format.';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed attempts. Please try again later.';
          break;
        default:
          errorMessage = e.message ?? 'Login failed';
      }
      return (success: false, error: errorMessage, user: null);
    } catch (e) {
      return (success: false, error: e.toString(), user: null);
    }
  }

  /// Send password reset email
  Future<({bool success, String? error})> sendPasswordResetEmail({
    required String email,
  }) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
      return (success: true, error: null);
    } on auth.FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email format.';
          break;
        default:
          errorMessage = e.message ?? 'Failed to send reset email';
      }
      return (success: false, error: errorMessage);
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  /// Resend verification email
  /// Returns true if email was sent successfully
  Future<({bool success, String? error})> resendVerificationEmail({
    required String email,
    required String password,
  }) async {
    try {
      // Sign in temporarily to resend verification
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final authUser = userCredential.user;
      if (authUser == null) {
        return (success: false, error: 'Could not find account');
      }

      if (authUser.emailVerified) {
        await _firebaseAuth.signOut();
        return (
          success: false,
          error: 'Email is already verified. You can now log in.',
        );
      }

      final actionCodeSettings = auth.ActionCodeSettings(
        url: 'https://idex-01.web.app',
        handleCodeInApp: true,
        androidPackageName: 'com.niranjan.idex',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );
      await authUser.sendEmailVerification(actionCodeSettings);
      await _firebaseAuth.signOut();

      return (success: true, error: null);
    } on auth.FirebaseAuthException catch (e) {
      return (
        success: false,
        error: e.message ?? 'Failed to send verification email',
      );
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  /// Sign in with Google
  Future<({bool success, String? error, User? user})> signInWithGoogle() async {
    try {
      // Trigger Google Sign-In flow (v6.x API)
      final GoogleSignInAccount? googleUser;
      try {
        googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          return (success: false, error: 'Sign-in cancelled', user: null);
        }
      } catch (e) {
        // User cancelled the sign-in or other error
        return (
          success: false,
          error: 'Sign-in cancelled or failed: ${e.toString()}',
          user: null,
        );
      }

      // Get authentication tokens (v6.x API)
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create credential for Firebase
      final credential = auth.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with Google credential
      final userCredential = await _firebaseAuth.signInWithCredential(
        credential,
      );

      final authUser = userCredential.user;
      if (authUser == null) {
        return (success: false, error: 'Google sign-in failed', user: null);
      }

      // Check if user profile exists in Firestore
      User? user = await _getUserProfile(authUser.uid);

      // If not, create a new profile
      if (user == null) {
        user = User(
          id: authUser.uid,
          username: authUser.email?.split('@').first ?? 'user',
          email: authUser.email ?? '',
          displayName:
              authUser.displayName ??
              authUser.email?.split('@').first ??
              'User',
          avatarColorValue: avatarColors[Random().nextInt(avatarColors.length)],
          createdAt: DateTime.now(),
        );

        // Ensure we save with merge: true to avoid overwriting if it partially exists,
        // and explicitly include all fields that might be missing
        await _firestore.collection(_usersCollection).doc(user.id).set({
          'id': user.id, // Explicitly save ID
          'uid': user.id, // Save as 'uid' too just in case rules check that
          'username': user.username,
          'email': user.email,
          'displayName': user.displayName,
          'avatarColorValue': user.avatarColorValue,
          'createdAt': user.createdAt.toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdGroups': [], // Initialize empty lists
        }, SetOptions(merge: true));
      }

      // Update FCM token
      await NotificationsService().updateFcmToken();

      return (success: true, error: null, user: user);
    } on auth.FirebaseAuthException catch (e) {
      return (
        success: false,
        error: e.message ?? 'Google sign-in failed',
        user: null,
      );
    } catch (e) {
      return (success: false, error: e.toString(), user: null);
    }
  }

  /// Get current logged in user
  Future<User?> getCurrentUser() async {
    final authUser = _firebaseAuth.currentUser;
    print('AuthService.getCurrentUser: authUser = $authUser');
    if (authUser == null) {
      print('AuthService.getCurrentUser: No Firebase Auth user found!');
      return null;
    }
    print('AuthService.getCurrentUser: authUser.uid = ${authUser.uid}');
    return await _getUserProfile(authUser.uid);
  }

  /// Stream user profile from Firestore
  Stream<User?> streamUserProfile(String uid) {
    return _firestore.collection(_usersCollection).doc(uid).snapshots().map((
      doc,
    ) {
      if (doc.exists && doc.data() != null) {
        return User.fromJson(doc.data()!);
      }
      return null;
    });
  }

  /// Fetch user profile from Firestore
  Future<User?> _getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection(_usersCollection).doc(uid).get();
      if (doc.exists && doc.data() != null) {
        print('AuthService: Found user document for $uid');
        print('AuthService: Document data: ${doc.data()}');
        return User.fromJson(doc.data()!);
      } else {
        print('AuthService: No user document found for uid: $uid');
      }
    } catch (e, stackTrace) {
      // Log the error for debugging
      print('AuthService: Error fetching user profile for $uid: $e');
      print('AuthService: Stack trace: $stackTrace');
    }
    return null;
  }

  /// Repair user profile checks if critical fields are missing and fixes them
  Future<void> repairUserProfile() async {
    final authUser = _firebaseAuth.currentUser;
    if (authUser == null) return;

    try {
      // Explicitly set all critical fields
      await _firestore.collection(_usersCollection).doc(authUser.uid).set({
        'id': authUser.uid,
        'uid': authUser.uid,
        'email': authUser.email,
        'username':
            authUser.displayName ??
            authUser.email?.split('@').first ??
            'user_${authUser.uid.substring(0, 5)}',
        'displayName':
            authUser.displayName ?? authUser.email?.split('@').first ?? 'User',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error repairing profile: $e');
    }
  }

  /// Update user profile
  Future<User?> updateProfile(User updatedUser) async {
    try {
      await _firestore
          .collection(_usersCollection)
          .doc(updatedUser.id)
          .update(updatedUser.toJson());
      return updatedUser;
    } catch (e) {
      return null;
    }
  }

  /// Logout current user
  Future<void> logout() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  /// Check if user is logged in
  /// Waits for Firebase Auth to restore the session on cold start
  Future<bool> isLoggedIn() async {
    // Wait for the first auth state change to ensure session is restored
    final user = await _firebaseAuth.authStateChanges().first;
    return user != null;
  }

  // ===== EMAIL LINK (PASSWORDLESS) SIGN-IN =====

  /// Send sign-in link to email
  Future<({bool success, String? error})> sendSignInLinkToEmail({
    required String email,
  }) async {
    try {
      // Configure the action code settings
      final actionCodeSettings = auth.ActionCodeSettings(
        // URL to redirect to after sign-in
        url: 'https://ideasstorage-1.web.app/signin',
        handleCodeInApp: true,
        iOSBundleId: 'com.example.flutterApplication1',
        androidPackageName: 'com.example.flutter_application_1',
        androidInstallApp: true,
        androidMinimumVersion: '21',
      );

      await _firebaseAuth.sendSignInLinkToEmail(
        email: email,
        actionCodeSettings: actionCodeSettings,
      );

      return (success: true, error: null);
    } on auth.FirebaseAuthException catch (e) {
      return (success: false, error: e.message ?? 'Failed to send link');
    } catch (e) {
      return (success: false, error: e.toString());
    }
  }

  /// Check if a link is a sign-in link
  bool isSignInWithEmailLink(String link) {
    return _firebaseAuth.isSignInWithEmailLink(link);
  }

  /// Sign in with email link
  Future<({bool success, String? error, User? user})> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) async {
    try {
      final userCredential = await _firebaseAuth.signInWithEmailLink(
        email: email,
        emailLink: emailLink,
      );

      final authUser = userCredential.user;
      if (authUser == null) {
        return (success: false, error: 'Sign-in failed', user: null);
      }

      // Check if user profile exists
      User? user = await _getUserProfile(authUser.uid);

      // If not, create a new profile
      if (user == null) {
        user = User(
          id: authUser.uid,
          username: authUser.email?.split('@').first ?? 'user',
          email: authUser.email ?? email,
          displayName: authUser.email?.split('@').first ?? 'User',
          avatarColorValue: avatarColors[Random().nextInt(avatarColors.length)],
          createdAt: DateTime.now(),
        );

        // Ensure we save with merge: true to avoid overwriting if it partially exists,
        // and explicitly include all fields that might be missing
        await _firestore.collection(_usersCollection).doc(user.id).set({
          'id': user.id, // Explicitly save ID
          'uid': user.id, // Save as 'uid' too just in case rules check that
          'username': user.username,
          'email': user.email,
          'displayName': user.displayName,
          'avatarColorValue': user.avatarColorValue,
          'createdAt': user.createdAt.toIso8601String(),
          'updatedAt': FieldValue.serverTimestamp(),
          'createdGroups': [], // Initialize empty lists
        }, SetOptions(merge: true));
      }

      return (success: true, error: null, user: user);
    } on auth.FirebaseAuthException catch (e) {
      return (success: false, error: e.message ?? 'Sign-in failed', user: null);
    } catch (e) {
      return (success: false, error: e.toString(), user: null);
    }
  }
}
