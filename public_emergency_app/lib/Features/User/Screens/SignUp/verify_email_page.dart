import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../Login/login_screen.dart';
import '../../../Responder/responder_dashboard.dart';
import '../../Controllers/session_controller.dart';
import '../bottom_nav.dart';
import '../../../Doctor/doctor_dashboard.dart';
import '../../../Admin/admin_panel.dart';  // ✅ ADD THIS

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({Key? key}) : super(key: key);

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool isEmailVerified = false;
  bool isVerificationSkipped = false;
  Timer? timer;
  bool canResendEmail = true;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  Widget screen = const NavBar();

  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app/';

  // List of admin emails (same as in LoginController)
  final List<String> adminEmails = [
    'finalyearproject102332@gmail.com',
  ];

  Future<void> screenAccordingToUser() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final email = FirebaseAuth.instance.currentUser!.email;
    final db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: firebaseDatabaseUrl,
    );

    // ✅ CHECK ADMIN FIRST
    if (adminEmails.contains(email)) {
      setState(() {
        screen = const AdminPanel();
        isVerificationSkipped = true;  // Skip verification for admin
      });
      return;
    }

    // Check Admins node (in case admin was added via database)
    final adminSnap = await db.ref('Admins').child(uid).get();
    if (adminSnap.exists) {
      setState(() {
        screen = const AdminPanel();
        isVerificationSkipped = true;  // Skip verification for admin
      });
      return;
    }

    // Check Responders/
    final responderSnap = await db.ref('Responders').child(uid).get();
    if (responderSnap.exists) {
      setState(() {
        screen = const ResponderDashboard();
        isVerificationSkipped = true;
      });
      return;
    }

    // Check Doctors/
    final doctorSnap = await db.ref('Doctors').child(uid).get();
    if (doctorSnap.exists) {
      setState(() {
        screen = const DoctorDashboard();
        isVerificationSkipped = true;
      });
      return;
    }

    // Default regular user - needs verification
    setState(() {
      screen = const NavBar();
      isVerificationSkipped = false;
    });
  }

  @override
  void initState() {
    super.initState();
    isEmailVerified = FirebaseAuth.instance.currentUser!.emailVerified;
    
    screenAccordingToUser().then((_) {
      // If user is admin, doctor, or responder, navigate immediately
      if (isVerificationSkipped) {
        timer?.cancel();
        Get.offAll(() => screen);
        return;
      }
      
      // Only regular users need verification
      if (!isEmailVerified) {
        sendVerificationEmail();
        timer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => checkEmailVerified(),
        );
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> checkEmailVerified() async {
    await FirebaseAuth.instance.currentUser!.reload();
    setState(() {
      isEmailVerified = FirebaseAuth.instance.currentUser!.emailVerified;
    });
    if (isEmailVerified) {
      timer?.cancel();
      Get.offAll(() => const NavBar());
    }
  }

  Future<void> sendVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await user.sendEmailVerification();
      _startCooldown(60);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('too-many-requests')) {
        Get.snackbar(
          'Slow down',
          'Too many attempts. Please wait a minute.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
        _startCooldown(60);
      } else {
        Get.snackbar('Error', msg,
            backgroundColor: Colors.red,
            colorText: Colors.white,
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  void _startCooldown(int seconds) {
    setState(() {
      canResendEmail = false;
      _cooldownSeconds = seconds;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _cooldownSeconds--);
      if (_cooldownSeconds <= 0) {
        t.cancel();
        setState(() => canResendEmail = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // If verification is skipped (admin/doctor/responder), show their dashboard
    if (isVerificationSkipped) {
      return screen;
    }

    // If email is verified, show user dashboard
    if (isEmailVerified) {
      return const NavBar();
    }

    // Otherwise show verification screen
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F4C5C),
        centerTitle: true,
        automaticallyImplyLeading: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110.0),
          child: Container(
            padding: const EdgeInsets.only(bottom: 15),
            child: const Column(
              children: [
                Text(
                  'Verify Email',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F4C5C).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_unread_rounded,
                size: 60,
                color: Color(0xFF0F4C5C),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'A verification email has been sent\nto your email address.',
              style: TextStyle(fontSize: 16, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF0F4C5C),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.email_rounded, size: 22),
              label: Text(
                canResendEmail
                    ? 'Resend Email'
                    : 'Resend in ${_cooldownSeconds}s',
                style: const TextStyle(
                    color: Colors.white, fontSize: 15),
              ),
              onPressed: canResendEmail ? sendVerificationEmail : null,
            ),
            const SizedBox(height: 12),
            TextButton(
              style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(20)),
              onPressed: () {
                FirebaseAuth.instance.signOut().then((_) {
                  SessionController().userid = '';
                  Get.offAll(() => const LoginScreen());
                });
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                    color: Color(0xFF0F4C5C),
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}