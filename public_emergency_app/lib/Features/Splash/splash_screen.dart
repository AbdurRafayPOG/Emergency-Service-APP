import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Features/Responder/responder_dashboard.dart';
import 'package:public_emergency_app/Features/User/Screens/bottom_nav.dart';
import 'package:public_emergency_app/Features/Login/login_screen.dart';
import 'package:public_emergency_app/Features/Splash/loading_indicator.dart';
import 'package:public_emergency_app/Features/User/Controllers/call_controller.dart';
import 'package:public_emergency_app/Features/User/Screens/VoicenVideoCall/keys.dart';
import 'package:public_emergency_app/Features/Doctor/doctor_dashboard.dart';
import 'package:public_emergency_app/Features/Admin/admin_panel.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Admin emails list (same as LoginController)
  final List<String> adminEmails = [
    'finalyearproject102332@gmail.com',
  ];

  @override
  void initState() {
    super.initState();
    _checkUserTypeAndNavigate();
  }

  Future<void> _initializeUserData(User user, String userType) async {
    try {
      final DatabaseReference database = FirebaseDatabase.instance.ref();
      
      String node;
      if (userType == 'responder') {
        node = 'Responders';
      } else if (userType == 'doctor') {
        node = 'Doctors';
      } else {
        node = 'Users';
      }
      
      try {
        final snapshot = await database.child(node).child(user.uid).get();
        
        if (snapshot.value != null) {
          final data = Map<String, dynamic>.from(snapshot.value as Map);
          
          String userName = data['name']?.toString() ?? 
                            data['Name']?.toString() ?? 
                            data['UserName']?.toString() ?? 
                            data['displayName']?.toString() ??
                            data['DisplayName']?.toString() ??
                            data['fullName']?.toString() ??
                            data['FullName']?.toString() ??
                            data['username']?.toString() ??
                            data['userName']?.toString() ??
                            user.displayName ??
                            user.email?.split('@').first ??
                            (userType == 'responder' ? 'Responder' : 
                             userType == 'doctor' ? 'Doctor' : 'User');
          
          String userTypeValue = data['UserType']?.toString() ?? '';
          
          Keys.currentUserId = user.uid;
          Keys.currentUserName = userName;
          Keys.userId = user.uid;
          Keys.userName = userName;
          
          if (userType == 'responder') {
            Keys.responderName = userName;
            Keys.responderType = userTypeValue;
          } else if (userType == 'doctor') {
            Keys.doctorName = userName;
            Keys.responderType = 'Doctor';
          }
          
          print("✅ User data loaded for $userType: $userName");
        } else {
          String fallbackName = user.displayName ?? 
                                user.email?.split('@').first ?? 
                                (userType == 'responder' ? 'Responder' : 
                                 userType == 'doctor' ? 'Doctor' : 'User');
          
          Keys.currentUserId = user.uid;
          Keys.currentUserName = fallbackName;
          Keys.userId = user.uid;
          Keys.userName = fallbackName;
          
          print("⚠️ No data found, using fallback: $fallbackName");
        }
      } catch (e) {
        String fallbackName = user.displayName ?? 
                              user.email?.split('@').first ?? 
                              (userType == 'responder' ? 'Responder' : 
                               userType == 'doctor' ? 'Doctor' : 'User');
        
        Keys.currentUserId = user.uid;
        Keys.currentUserName = fallbackName;
        Keys.userId = user.uid;
        Keys.userName = fallbackName;
        
        print("⚠️ Error loading data, using fallback: $fallbackName");
      }
    } catch (e) {
      print("❌ Error initializing user data: $e");
    }
  }

  Future<void> _checkUserTypeAndNavigate() async {
    await Future.delayed(const Duration(milliseconds: 1500));

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // ✅ No user logged in → Go to Login
      Get.offAll(() => const LoginScreen());
      return;
    }

    try {
      final db = FirebaseDatabase.instance;
      
      // ✅ CHECK ADMIN FIRST
      final email = user.email;
      if (adminEmails.contains(email)) {
        print("✅ Admin detected: $email");
        await _initializeUserData(user, 'admin');
        Get.offAll(() => const AdminPanel());
        return;
      }

      // ✅ CHECK ADMINS NODE
      final adminCheckRef = db.ref().child('Admins').child(user.uid);
      final adminSnapshot = await adminCheckRef.get();
      if (adminSnapshot.value != null) {
        print("✅ Admin found in Admins node");
        await _initializeUserData(user, 'admin');
        Get.offAll(() => const AdminPanel());
        return;
      }

      final userRef = db.ref().child('Users').child(user.uid);
      final responderRef = db.ref().child('Responders').child(user.uid);
      final doctorRef = db.ref().child('Doctors').child(user.uid);

      // Check Doctor
      final doctorSnapshot = await doctorRef.get();
      if (doctorSnapshot.value != null) {
        await _initializeUserData(user, 'doctor');
        Get.offAll(() => const DoctorDashboard());
        return;
      }

      // Check Responder
      final responderSnapshot = await responderRef.get();
      if (responderSnapshot.value != null) {
        final data = Map<String, dynamic>.from(responderSnapshot.value as Map);
        final userType = data['UserType']?.toString() ?? 'Responder';
        
        await _initializeUserData(user, 'responder');
        Get.offAll(() => ResponderDashboard(userType: userType));
        return;
      }

      // Check Regular User
      final userSnapshot = await userRef.get();
      if (userSnapshot.value != null) {
        await _initializeUserData(user, 'user');
        Get.offAll(() => const NavBar());
        return;
      }

      // ✅ No user data found → Go to Login
      Get.offAll(() => const LoginScreen());
    } catch (e) {
      print("❌ Navigation error: $e");
      Get.offAll(() => const LoginScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F4C5C),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logos/emergencyAppLogo.png',
              height: 120,
              width: 120,
            ),
            const SizedBox(height: 30),
            const Text(
              'Emergency Service',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'One Tap. Every Emergency.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 50),
            const PremiumLoadingIndicator(),
            const SizedBox(height: 30),
            const Text(
              'Loading...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}