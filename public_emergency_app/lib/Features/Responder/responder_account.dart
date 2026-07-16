import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../Common Widgets/constants.dart';

class ResponderAccountPage extends StatefulWidget {
  const ResponderAccountPage({Key? key}) : super(key: key);

  @override
  State<ResponderAccountPage> createState() => _ResponderAccountPageState();
}

class _ResponderAccountPageState extends State<ResponderAccountPage> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isLoading = true;
  String _userName = '';
  String _email = '';
  String _responderType = '';
  String _phone = '';
  
  // Password update controllers
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app';

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      await Firebase.initializeApp();
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      );
      
      final responderRef = db.ref().child('Responders').child(user!.uid);
      final snapshot = await responderRef.get();
      
      if (snapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        setState(() {
          _userName = data['UserName']?.toString() ?? 'Not Available';
          _email = data['Email']?.toString() ?? user?.email ?? 'Not Available';
          _responderType = data['UserType']?.toString() ?? 'Not Available';
          _phone = data['Phone']?.toString() ?? 'Not Available';
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showPasswordUpdateDialog() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();

    bool isCurrentVisible = false;
    bool isNewVisible = false;
    bool isConfirmVisible = false;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;
    final isSmallPhone = screenHeight < 600;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: isSmallPhone ? 12 : 24,
                vertical: isSmallPhone ? 12 : 24,
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                width: isTablet ? screenWidth * 0.5 : screenWidth * 0.92,
                constraints: BoxConstraints(
                  maxWidth: 500,
                  maxHeight: isSmallPhone ? screenHeight * 0.9 : screenHeight * 0.85,
                  minHeight: isSmallPhone ? 400 : 480,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with icon
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        isSmallPhone ? 12 : 20,
                        20,
                        isSmallPhone ? 8 : 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF0F4C5C),
                                  Color(0xFF0F4C5C),
                                ],
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.lock_outline_rounded,
                              color: Colors.white,
                              size: isSmallPhone ? 24 : 28,
                            ),
                          ),
                          SizedBox(height: isSmallPhone ? 4 : 8),
                          Text(
                            'Update Password',
                            style: TextStyle(
                              fontSize: isSmallPhone ? 18 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: isSmallPhone ? 2 : 4),
                          Text(
                            'Enter your current and new password',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.45),
                              fontSize: isSmallPhone ? 11 : 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Content - Password fields
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: isSmallPhone ? 16 : 20,
                          vertical: isSmallPhone ? 8 : 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Current Password Field
                            TextField(
                              controller: _currentPasswordController,
                              obscureText: !isCurrentVisible,
                              style: TextStyle(
                                fontSize: isSmallPhone ? 13 : 14,
                              ),
                              autofocus: false,
                              decoration: InputDecoration(
                                labelText: 'Current Password',
                                labelStyle: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: isSmallPhone ? 11 : 12,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_outline,
                                  color: const Color(0xFF0F4C5C),
                                  size: isSmallPhone ? 18 : 20,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: isSmallPhone ? 8 : 12,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    isCurrentVisible ? Icons.visibility : Icons.visibility_off,
                                    size: isSmallPhone ? 18 : 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      isCurrentVisible = !isCurrentVisible;
                                    });
                                  },
                                ),
                              ),
                            ),
                            SizedBox(height: isSmallPhone ? 8 : 12),
                            
                            // New Password Field
                            TextField(
                              controller: _newPasswordController,
                              obscureText: !isNewVisible,
                              style: TextStyle(
                                fontSize: isSmallPhone ? 13 : 14,
                              ),
                              decoration: InputDecoration(
                                labelText: 'New Password',
                                labelStyle: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: isSmallPhone ? 11 : 12,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_open,
                                  color: const Color(0xFF0F4C5C),
                                  size: isSmallPhone ? 18 : 20,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: isSmallPhone ? 8 : 12,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    isNewVisible ? Icons.visibility : Icons.visibility_off,
                                    size: isSmallPhone ? 18 : 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      isNewVisible = !isNewVisible;
                                    });
                                  },
                                ),
                              ),
                            ),
                            SizedBox(height: isSmallPhone ? 8 : 12),
                            
                            // Confirm Password Field
                            TextField(
                              controller: _confirmPasswordController,
                              obscureText: !isConfirmVisible,
                              style: TextStyle(
                                fontSize: isSmallPhone ? 13 : 14,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Confirm Password',
                                labelStyle: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: isSmallPhone ? 11 : 12,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_outline,
                                  color: const Color(0xFF0F4C5C),
                                  size: isSmallPhone ? 18 : 20,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: isSmallPhone ? 8 : 12,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    isConfirmVisible ? Icons.visibility : Icons.visibility_off,
                                    size: isSmallPhone ? 18 : 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      isConfirmVisible = !isConfirmVisible;
                                    });
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Actions - Buttons
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        isSmallPhone ? 12 : 20,
                        isSmallPhone ? 8 : 12,
                        isSmallPhone ? 12 : 20,
                        isSmallPhone ? 12 : 20,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: TextButton(
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                Navigator.pop(context);
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.grey.shade200,
                                foregroundColor: Colors.black87,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isSmallPhone ? 12 : 16,
                                  vertical: isSmallPhone ? 6 : 8,
                                ),
                                minimumSize: Size(
                                  isSmallPhone ? 60 : 80,
                                  isSmallPhone ? 30 : 36,
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isSmallPhone ? 12 : 14,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: isSmallPhone ? 4 : 6),
                          Flexible(
                            child: TextButton(
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                Navigator.pop(context);
                                _updatePassword();
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF0F4C5C),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: isSmallPhone ? 12 : 16,
                                  vertical: isSmallPhone ? 6 : 8,
                                ),
                                minimumSize: Size(
                                  isSmallPhone ? 60 : 80,
                                  isSmallPhone ? 30 : 36,
                                ),
                              ),
                              child: Text(
                                'Update',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: isSmallPhone ? 12 : 14,
                                ),
                              ),
                            ),
                          ),
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

  void _updatePassword() async {
    String currentPassword = _currentPasswordController.text.trim();
    String newPassword = _newPasswordController.text.trim();
    String confirmPassword = _confirmPasswordController.text.trim();

    if (currentPassword.isEmpty) {
      Get.snackbar(
        'Error',
        'Please enter your current password',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      return;
    }

    if (newPassword.isEmpty || newPassword.length < 6) {
      Get.snackbar(
        'Error',
        'New password must be at least 6 characters long',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      return;
    }

    if (newPassword == currentPassword) {
      Get.snackbar(
        'Error',
        'New password must be different from current password',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      return;
    }

    if (newPassword != confirmPassword) {
      Get.snackbar(
        'Error',
        'Passwords do not match',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      return;
    }

    FocusScope.of(Get.context!).unfocus();
    
    Get.dialog(
      Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.orange.shade500,
                      Colors.orange.shade700,
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Confirm Password Change?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Are you sure you want to change your password?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        FocusScope.of(Get.context!).unfocus();
                        Get.back();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        FocusScope.of(Get.context!).unfocus();
                        Get.back();
                        await _executePasswordUpdate(currentPassword, newPassword);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4C5C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                      child: const Text(
                        'Yes, Update',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: true,
    );
  }

  Future<void> _executePasswordUpdate(String currentPassword, String newPassword) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      Get.snackbar(
        'Error',
        'You are not logged in. Please log in again.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      return;
    }

    Get.dialog(
      const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F4C5C)),
        ),
      ),
      barrierDismissible: false,
    );

    try {
      AuthCredential credential = EmailAuthProvider.credential(
        email: currentUser.email!,
        password: currentPassword,
      );
      
      await currentUser.reauthenticateWithCredential(credential);
      await currentUser.updatePassword(newPassword);
      
      if (Get.isDialogOpen ?? false) Get.back();
      
      Get.snackbar(
        'Success',
        'Password updated successfully!',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      
    } on FirebaseAuthException catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      
      String errorMessage = '';
      switch (e.code) {
        case 'wrong-password':
          errorMessage = 'Current password is incorrect';
          break;
        case 'requires-recent-login':
          errorMessage = 'Please log out and log in again, then try updating your password.';
          _showLogoutDialog();
          break;
        case 'too-many-requests':
          errorMessage = 'Too many attempts. Please wait and try again later.';
          break;
        case 'weak-password':
          errorMessage = 'New password is too weak. Use at least 6 characters.';
          break;
        case 'user-not-found':
          errorMessage = 'User not found. Please log in again.';
          break;
        case 'user-disabled':
          errorMessage = 'User account is disabled. Contact support.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your internet connection.';
          break;
        default:
          errorMessage = 'Error: ${e.code}';
      }
      
      Get.snackbar(
        'Error',
        errorMessage,
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar(
        'Error',
        'An unexpected error occurred. Please try again.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
    }
  }

  void _showLogoutDialog() {
    Get.dialog(
      AlertDialog(
        title: const Text('Re-login Required'),
        content: const Text(
          'For security, you need to log out and log back in before changing your password. Would you like to log out now?'
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              await FirebaseAuth.instance.signOut();
              Get.offAllNamed('/login');
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final appBarHeight = screenHeight * 0.14;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F4C5C),
        centerTitle: true,
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(24),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(appBarHeight),
          child: Container(
            height: appBarHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/logos/emergencyAppLogo.png',
                  height: screenHeight * 0.07,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 4),
                const Text(
                  'My Account',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F4C5C)),
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  // ============================================================
                  // PROFILE HEADER CARD
                  // ============================================================
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF0F4C5C),
                            const Color(0xFF0F4C5C).withValues(alpha: 0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F4C5C).withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Avatar - stays on the left
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _userName.isNotEmpty && _userName != 'Not Available'
                                      ? _userName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F4C5C),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Username and Responder Type - Centered
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _userName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _responderType,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // ============================================================
                  // PERSONAL INFORMATION CARD - REORGANIZED
                  // Order: Full Name → Responder Type → Email → Phone Number
                  // ============================================================
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.grey.shade100,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F4C5C),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(14),
                                topRight: Radius.circular(14),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.person_pin_rounded,
                                    color: const Color(0xFF0F4C5C),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Personal Information',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Info items - REORGANIZED ORDER: Full Name → Responder Type → Email → Phone
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 1. Full Name
                                _buildInfoItemCompact(
                                  label: 'Full Name',
                                  value: _userName,
                                  icon: Icons.account_circle_rounded,
                                  iconColor: const Color(0xFF0F4C5C),
                                ),
                                _buildDividerCompact(),
                                
                                // 2. Responder Type
                                _buildInfoItemCompact(
                                  label: 'Responder Type',
                                  value: _responderType,
                                  icon: Icons.badge_outlined,
                                  iconColor: const Color(0xFF0F4C5C),
                                ),
                                _buildDividerCompact(),
                                
                                // 3. Email Address
                                _buildInfoItemCompact(
                                  label: 'Email Address',
                                  value: _email,
                                  icon: Icons.email_outlined,
                                  iconColor: const Color(0xFF0F4C5C),
                                ),
                                _buildDividerCompact(),
                                
                                // 4. Phone Number
                                _buildInfoItemCompact(
                                  label: 'Phone Number',
                                  value: _phone,
                                  icon: Icons.phone_outlined,
                                  iconColor: const Color(0xFF0F4C5C),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // ============================================================
                  // UPDATE PASSWORD BUTTON
                  // ============================================================
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showPasswordUpdateDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0F4C5C),
                          elevation: 1,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: const Color(0xFF0F4C5C).withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                        ),
                        icon: Icon(Icons.lock_reset, color: const Color(0xFF0F4C5C), size: 20),
                        label: Text(
                          'Update Password',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F4C5C),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 14),
                  
                  // ============================================================
                  // NOTE SECTION
                  // ============================================================
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 8 + bottomPadding),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F4C5C).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF0F4C5C),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: const Color(0xFF0F4C5C),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'You can only view your information here. To update your details, please contact your administrator.',
                              textAlign: TextAlign.justify,
                              style: TextStyle(
                                fontSize: 10,
                                color: const Color(0xFF0F4C5C),
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // COMPACT INFO ITEM
  // ============================================================
  Widget _buildInfoItemCompact({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DIVIDER
  // ============================================================
  Widget _buildDividerCompact() {
    return Container(
      height: 1,
      color: Colors.grey.shade100,
    );
  }
}