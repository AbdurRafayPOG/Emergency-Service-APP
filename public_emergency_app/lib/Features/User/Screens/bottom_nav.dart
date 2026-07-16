import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:public_emergency_app/Features/User/Screens/User%20DashBoard/user_dashboard.dart';
import 'package:public_emergency_app/Features/User/Screens/VoicenVideoCall/sos_page.dart';
import 'package:public_emergency_app/Features/User/Screens/Profile/profile_screen.dart';
import '../../../Common Widgets/constants.dart';

class NavBar extends StatefulWidget {
  const NavBar({Key? key}) : super(key: key);

  @override
  State<NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<NavBar> {
  int currentIndex = 1;
  
  // ✅ Use the class directly - VideonVideocall is exported from sos_page.dart
  final List<Widget> screens = [
    const ProfileScreen(),
    const UserDashboard(),
    const LiveStreamUser(),  // ← This class exists in sos_page.dart
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[currentIndex],
      bottomNavigationBar: AnimatedBottomNavigationBar(
        icons: const [
          Icons.person,
          Icons.emergency,
          FontAwesomeIcons.kitMedical,
        ],
        activeIndex: currentIndex,
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
            currentIndex = index;
          });
        },
      ),
    );
  }
}