import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Features/User/Controllers/session_controller.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';
import 'package:public_emergency_app/Features/Splash/splash_screen.dart';
import '../Screens/SignUp/verify_email_page.dart';
import 'package:public_emergency_app/Features/Admin/admin_panel.dart';
import 'package:public_emergency_app/Features/Doctor/doctor_dashboard.dart';
import 'package:public_emergency_app/Features/Responder/responder_dashboard.dart';
import 'package:public_emergency_app/Features/User/Screens/bottom_nav.dart';

class LoginController extends GetxController {
  static LoginController get instance => Get.find();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final RxBool isAdminLogging = false.obs;
  final RxBool isLoading = false.obs;

  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app/';

  // ✅ List of authorized admin emails
  final List<String> adminEmails = [
    'finalyearproject102332@gmail.com',  
    // Add more admin emails if needed
  ];

  DateTime? _parseBanDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> _checkBanStatus(
      DatabaseReference userRef, Map<dynamic, dynamic> data) async {
    final banned = data['banned'] ?? 'none';
    if (banned == 'none') return null;

    if (banned == 'permanent') {
      final reason = data['banReason'] ?? '';
      return reason.isNotEmpty
          ? 'Your account has been permanently banned.\nReason: $reason'
          : 'Your account has been permanently banned.';
    }

    if (banned == 'temporary') {
      final banUntilStr = data['banUntil'] ?? '';
      final banUntil = _parseBanDate(banUntilStr);
      if (banUntil == null) return null;

      if (DateTime.now().isAfter(banUntil)) {
        await userRef.update({
          'banned': 'none',
          'banReason': '',
          'banUntil': '',
        });
        return null;
      }

      final reason = data['banReason'] ?? '';
      return reason.isNotEmpty
          ? 'Your account is temporarily banned until $banUntilStr.\nReason: $reason'
          : 'Your account is temporarily banned until $banUntilStr.';
    }

    return null;
  }

  void _showBannedDialog(String message) {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block_rounded,
                    color: Colors.redAccent, size: 36),
              ),
              const SizedBox(height: 18),
              const Text('Account Banned',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.black54, fontSize: 14, height: 1.5)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Get.back(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('OK',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  void _showDeletedDialog() {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_off_rounded,
                    color: Colors.redAccent, size: 36),
              ),
              const SizedBox(height: 18),
              const Text('Account Removed',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 12),
              const Text(
                'This account has been removed by the admin.\nPlease contact support if you think this is a mistake.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.black54, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Get.back(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: const Text('OK',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  // ✅ Check if user is admin and create admin node if needed
  Future<bool> _checkAndCreateAdmin(String uid, String email) async {
    final db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: firebaseDatabaseUrl,
    );

    // Check if admin node already exists
    final adminSnap = await db.ref('Admins').child(uid).get();
    
    if (!adminSnap.exists) {
      // ✅ Create admin node in Firebase
      await db.ref('Admins').child(uid).set({
        'email': email,
        'role': 'admin',
        'createdAt': DateTime.now().toString(),
      });
      
      // Also update the Users node with admin role
      final userRef = db.ref('Users').child(uid);
      final userSnap = await userRef.get();
      if (userSnap.exists) {
        await userRef.update({
          'role': 'admin',
          'isAdmin': true,
        });
      }
    }

    return true;
  }

  void _navigateBasedOnRole(String uid) async {
    final db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: firebaseDatabaseUrl,
    );

    // ✅ FIRST: Check if user is admin
    final adminSnap = await db.ref('Admins').child(uid).get();
    if (adminSnap.exists) {
      isLoading.value = false;
      Get.offAll(() => const AdminPanel());
      Get.snackbar('Success', 'Welcome Admin!',
          backgroundColor: Colors.green, colorText: Colors.white);
      return;
    }

    // ✅ Doctor → DoctorDashboard
    final doctorSnap = await db.ref('Doctors').child(uid).get();
    if (doctorSnap.exists) {
      await Future.delayed(const Duration(milliseconds: 300));
      isLoading.value = false;
      Get.offAll(() => const DoctorDashboard());
      Get.snackbar('Success', 'Welcome Doctor!',
          backgroundColor: Colors.green, colorText: Colors.white);
      return;
    }

    // ✅ Responder → ResponderDashboard
    final responderSnap = await db.ref('Responders').child(uid).get();
    if (responderSnap.exists) {
      final data = Map<String, dynamic>.from(responderSnap.value as Map);
      final userType = data['UserType']?.toString() ?? 'Responder';
      
      isLoading.value = false;
      Get.offAll(() => ResponderDashboard(userType: userType));
      return;
    }

    // ✅ User → NavBar
    await Future.delayed(const Duration(milliseconds: 300));
    isLoading.value = false;
    Get.offAll(() => const NavBar());
    Get.snackbar('Success', 'Welcome!',
        backgroundColor: Colors.green, colorText: Colors.white);
  }

  void loginUser(String email, String password) async {
    // ✅ Check if admin email first
    if (adminEmails.contains(email)) {
      isAdminLogging.value = true;  // Show "Authenticating..."
      isLoading.value = true;
      
      try {
        // Authenticate with Firebase
        UserCredential cred = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        
        SessionController().userid = cred.user!.uid;
        final String uid = cred.user!.uid;
        
        // Check if account is deleted
        final db = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: firebaseDatabaseUrl,
        );
        
        final deletedSnap = await db.ref('DeletedAccounts').child(uid).get();
        if (deletedSnap.exists) {
          await FirebaseAuth.instance.signOut();
          SessionController().userid = '';
          isAdminLogging.value = false;
          isLoading.value = false;
          _showDeletedDialog();
          return;  // ✅ EXIT HERE
        }

        // Check and create admin
        final isAdmin = await _checkAndCreateAdmin(uid, email);
        
        if (isAdmin) {
          isAdminLogging.value = false;
          isLoading.value = false;
          Get.offAll(() => const AdminPanel());
          Get.snackbar('Success', 'Welcome Admin!',
              backgroundColor: Colors.green, colorText: Colors.white);
          return;  // ✅ EXIT HERE - THIS IS THE FIX!
        }
        
        // If somehow not admin, fall through to regular flow
        // (This shouldn't happen since email is in adminEmails)
        isAdminLogging.value = false;
        isLoading.value = false;
        Get.snackbar('Error', 'Admin role not assigned');
        return;  // ✅ EXIT HERE
        
      } catch (error) {
        isAdminLogging.value = false;
        isLoading.value = false;
        emailController.clear();
        passwordController.clear();
        
        // Handle admin login error
        final msg = error.toString();
        if (msg.contains('user-not-found')) {
          Get.snackbar('Error', 'Admin account not found');
        } else if (msg.contains('wrong-password')) {
          Get.snackbar('Error', 'Wrong password');
        } else if (msg.contains('invalid-email')) {
          Get.snackbar('Error', 'Invalid email');
        } else if (msg.contains('network-request-failed')) {
          Get.snackbar('Error', 'Network error');
        } else if (msg.contains('too-many-requests')) {
          Get.snackbar('Error', 'Too many requests');
        } else {
          Get.snackbar('Error', 'Admin login failed: $msg');
        }
        return;  // ✅ EXIT HERE
      }
    }

    // ✅ Regular user login flow (ONLY reaches here if NOT admin)
    isLoading.value = true;

    try {
      UserCredential cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      SessionController().userid = cred.user!.uid;
      final String uid = cred.user!.uid;

      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      );

      // Check if account is deleted
      final deletedSnap = await db.ref('DeletedAccounts').child(uid).get();
      if (deletedSnap.exists) {
        await FirebaseAuth.instance.signOut();
        SessionController().userid = '';
        isLoading.value = false;
        _showDeletedDialog();
        return;
      }

      // Check user data and ban status
      final userRef = db.ref('Users').child(uid);
      final userSnap = await userRef.get();

      if (userSnap.exists) {
        final data = Map<dynamic, dynamic>.from(userSnap.value as Map);
        final banMessage = await _checkBanStatus(userRef, data);
        if (banMessage != null) {
          await FirebaseAuth.instance.signOut();
          SessionController().userid = '';
          isLoading.value = false;
          _showBannedDialog(banMessage);
          return;
        }
      }

      // Navigate with loading still showing
      await Future.delayed(const Duration(milliseconds: 500));
      _navigateBasedOnRole(uid);

    } catch (error) {
      isLoading.value = false;
      isAdminLogging.value = false;
      emailController.clear();
      passwordController.clear();

      final msg = error.toString();
      if (msg.contains('user-not-found')) {
        Get.snackbar('Error', 'User Not Found');
      } else if (msg.contains('wrong-password')) {
        Get.snackbar('Error', 'Wrong Password');
      } else if (msg.contains('invalid-email')) {
        Get.snackbar('Error', 'Invalid Email');
      } else if (msg.contains('network-request-failed')) {
        Get.snackbar('Error', 'Network Error');
      } else if (msg.contains('too-many-requests')) {
        Get.snackbar('Error', 'Too Many Requests');
      } else if (msg.contains('invalid-credential')) {
        Get.snackbar('Error', 'Invalid Credential');
      } else {
        Get.snackbar('Error', msg);
      }
    }
  }
}