import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import '../models/user.dart';
import '../models/idea.dart';
import '../services/auth_service.dart';
import '../services/ideas_service.dart';
import '../main.dart' show themeNotifier;
import 'login_screen.dart';
import 'starred_ideas_screen.dart';

/// Profile screen for viewing and editing user profile
class ProfileScreen extends StatefulWidget {
  final VoidCallback? onSwitchToIdeas;
  final bool isVisible;

  const ProfileScreen({
    super.key,
    this.onSwitchToIdeas,
    this.isVisible = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _ideasService = IdeasService();
  Stream<User?>? _userStream;

  // Showcase keys
  final GlobalKey _themeShowcaseKey = GlobalKey();
  final GlobalKey _editProfileShowcaseKey = GlobalKey();
  final GlobalKey _starredShowcaseKey = GlobalKey();
  bool _showcaseTriggered = false;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _userStream = _authService.streamUserProfile(uid);
      // Optional: Check repair silently
      _authService.repairUserProfile().catchError((_) {});
    }
  }

  Future<void> _triggerShowcaseIfNeeded(BuildContext showcaseContext) async {
    if (!widget.isVisible || _showcaseTriggered) return;
    _showcaseTriggered = true;

    final prefs = await SharedPreferences.getInstance();
    final isFirstVisit = prefs.getBool('first_profile_visit') ?? true;
    if (isFirstVisit && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShowCaseWidget.of(showcaseContext).startShowCase([
          _themeShowcaseKey,
          _editProfileShowcaseKey,
          _starredShowcaseKey,
        ]);
      });
      await prefs.setBool('first_profile_visit', false);
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authService.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  void _showEditProfileDialog(User user) {
    showDialog(
      context: context,
      builder: (context) => _EditProfileDialog(
        user: user,
        authService: _authService,
        onSaved: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Profile updated!')));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_userStream == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('Not logged in')),
      );
    }

    return StreamBuilder<User?>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Profile')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Profile')),
            body: const Center(child: Text('User not found')),
          );
        }

        final avatarColor = Color(user.avatarColorValue);

        return ShowCaseWidget(
          builder: (showcaseContext) {
            if (widget.isVisible) {
              _triggerShowcaseIfNeeded(showcaseContext);
            }

            return Scaffold(
              appBar: AppBar(
                title: const Text('Profile'),
                actions: [
                  // Theme toggle button with Showcase
                  Showcase(
                    key: _themeShowcaseKey,
                    description: 'Switch between light and dark themes',
                    targetPadding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: Icon(
                        themeNotifier.themeMode == ThemeMode.dark
                            ? Icons.dark_mode
                            : Icons.light_mode,
                      ),
                      onPressed: () {
                        if (themeNotifier.themeMode == ThemeMode.dark) {
                          themeNotifier.setThemeMode(ThemeMode.light);
                        } else {
                          themeNotifier.setThemeMode(ThemeMode.dark);
                        }
                      },
                      tooltip: 'Toggle theme',
                    ),
                  ),
                  Showcase(
                    key: _editProfileShowcaseKey,
                    description: 'Update your name and profile details',
                    targetPadding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showEditProfileDialog(user),
                      tooltip: 'Edit Profile',
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    // Profile header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            avatarColor.withValues(alpha: 0.2),
                            avatarColor.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: avatarColor,
                            child: Text(
                              user.initials,
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Display name
                          Text(
                            user.displayName,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          // Username
                          Text(
                            '@${user.username}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Profile details
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionHeader('Account'),
                          const SizedBox(height: 4),
                          // Email card
                          _buildInfoCard(
                            icon: Icons.email_outlined,
                            title: 'Email',
                            subtitle: user.email,
                          ),
                          // Member since card
                          _buildInfoCard(
                            icon: Icons.calendar_today_outlined,
                            title: 'Member Since',
                            subtitle:
                                '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}',
                          ),

                          const SizedBox(height: 24),
                          _buildSectionHeader('Activity'),
                          const SizedBox(height: 4),
                          // Ideas count card
                          StreamBuilder<List<Idea>>(
                            stream: _ideasService.streamMyIdeas(user.id, null),
                            builder: (context, snapshot) {
                              final count = snapshot.data?.length ?? 0;
                              return _buildInfoCard(
                                icon: Icons.lightbulb_outline,
                                title: 'Ideas Created',
                                subtitle:
                                    '$count ${count == 1 ? 'idea' : 'ideas'}',
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  widget.onSwitchToIdeas?.call();
                                },
                                trailing: widget.onSwitchToIdeas != null
                                    ? const Icon(Icons.chevron_right, size: 18)
                                    : null,
                              );
                            },
                          ),

                          // Starred ideas card
                          Showcase(
                            key: _starredShowcaseKey,
                            description: 'View ideas you\'ve starred',
                            child: _buildInfoCard(
                              icon: Icons.star_outline,
                              title: 'Starred Ideas',
                              subtitle: 'View your bookmarked ideas',
                              iconColor: Colors.amber,
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 18,
                              ),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const StarredIdeasScreen(),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 32),
                          // Logout button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticFeedback.heavyImpact();
                                _handleLogout();
                              },
                              icon: const Icon(Icons.logout, size: 20),
                              label: const Text('Logout'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(
                                  color: Colors.red,
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withOpacity(0.1)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (iconColor ?? Theme.of(context).colorScheme.primary)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor ?? Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Stateful dialog for editing profile with username validation
class _EditProfileDialog extends StatefulWidget {
  final User user;
  final AuthService authService;
  final VoidCallback onSaved;

  const _EditProfileDialog({
    required this.user,
    required this.authService,
    required this.onSaved,
  });

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late TextEditingController _displayNameController;
  late TextEditingController _usernameController;

  Timer? _usernameCheckTimer;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameValidationError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.user.displayName,
    );
    _usernameController = TextEditingController(text: widget.user.username);
    _usernameController.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameCheckTimer?.cancel();
    _displayNameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    setState(() {
      _isUsernameAvailable = null;
      _usernameValidationError = null;
    });

    _usernameCheckTimer?.cancel();

    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty) return;

    // Skip check if unchanged
    if (username == widget.user.username) {
      setState(() => _isUsernameAvailable = true);
      return;
    }

    // Format validation: 4+ chars, lowercase, numbers, ., _
    final validFormat = RegExp(r'^[a-z0-9._]{4,}$');
    if (!validFormat.hasMatch(username)) {
      setState(() {
        _usernameValidationError =
            'Must be 4+ chars, lowercase, numbers, . or _';
      });
      return;
    }

    // Debounce DB check
    _usernameCheckTimer = Timer(const Duration(milliseconds: 500), () {
      _checkUsernameAvailability(username);
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
    setState(() => _isCheckingUsername = true);

    final isAvailable = await widget.authService.checkUsernameAvailability(
      username,
    );

    if (mounted) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = isAvailable;
        if (!isAvailable) {
          _usernameValidationError = 'Username is already taken';
        }
      });
    }
  }

  bool get _canSave {
    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty || _displayNameController.text.trim().isEmpty)
      return false;
    if (_isCheckingUsername || _isSaving) return false;
    if (_usernameValidationError != null) return false;
    if (username != widget.user.username && _isUsernameAvailable != true)
      return false;
    return true;
  }

  Future<void> _handleSave() async {
    if (!_canSave) return;

    setState(() => _isSaving = true);

    final updatedUser = widget.user.copyWith(
      displayName: _displayNameController.text.trim(),
      username: _usernameController.text.trim().toLowerCase(),
    );

    await widget.authService.updateProfile(updatedUser);

    if (mounted) {
      Navigator.pop(context);
      widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Profile'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              border: const OutlineInputBorder(),
              prefixText: '@',
              suffixIcon: _buildUsernameSuffix(),
              errorText: _usernameValidationError,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSave ? _handleSave : null,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget? _buildUsernameSuffix() {
    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty || username == widget.user.username) return null;

    if (_isCheckingUsername) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_usernameValidationError != null) {
      return const Icon(Icons.error, color: Colors.red);
    }

    if (_isUsernameAvailable == true) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }

    return null;
  }
}
