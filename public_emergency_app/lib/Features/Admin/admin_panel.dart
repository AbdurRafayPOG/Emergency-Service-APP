import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';
import 'package:public_emergency_app/Features/Admin/admin_dashboard.dart';
import 'staff_screen.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({Key? key}) : super(key: key);

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  // ✅ Tracks which bottom nav tab is active
  int _currentIndex = 0;

  // ✅ Two tabs: Home (emergencies) and Staff (manage responders/doctors)
  final List<Widget> _screens = const [
    EmergenciesScreen(),
    StaffScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: AnimatedBottomNavigationBar(
        icons: const [
          Icons.home_rounded,
          Icons.groups_rounded,
        ],
        activeIndex: _currentIndex,
        gapLocation: GapLocation.none,
        notchSmoothness: NotchSmoothness.defaultEdge,
        leftCornerRadius: 24,
        rightCornerRadius: 24,
        activeColor: Colors.white,
        inactiveColor: Colors.white70,
        backgroundColor: const Color(0xFF0F4C5C),
        iconSize: 24,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}