import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home_screen.dart';
import 'discovery_screen.dart';
import 'groups_list_screen.dart';
import 'profile_screen.dart';

/// Main screen with bottom navigation
class MainScreen extends StatefulWidget {
  final int initialIndex;

  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onTabSelected(int index) {
    if (index != _currentIndex) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Build screens with isVisible flag
    final screens = [
      HomeScreen(isVisible: _currentIndex == 0),
      DiscoveryScreen(isVisible: _currentIndex == 1),
      GroupsListScreen(isVisible: _currentIndex == 2),
      ProfileScreen(
        isVisible: _currentIndex == 3,
        onSwitchToIdeas: () => _onTabSelected(0),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabSelected,
        destinations: [
          _buildNavDestination(
            index: 0,
            icon: Icons.lightbulb_outline,
            selectedIcon: Icons.lightbulb,
            label: 'Ideas',
          ),
          _buildNavDestination(
            index: 1,
            icon: Icons.explore_outlined,
            selectedIcon: Icons.explore,
            label: 'Discover',
          ),
          _buildNavDestination(
            index: 2,
            icon: Icons.groups_outlined,
            selectedIcon: Icons.groups,
            label: 'Groups',
          ),
          _buildNavDestination(
            index: 3,
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  NavigationDestination _buildNavDestination({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    return NavigationDestination(
      icon: AnimatedScale(
        scale: isSelected ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Icon(icon),
      ),
      selectedIcon: AnimatedScale(
        scale: 1.15,
        duration: const Duration(milliseconds: 150),
        child: Icon(selectedIcon),
      ),
      label: label,
    );
  }
}
