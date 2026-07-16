import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:public_emergency_app/Features/User/Screens/Profile/ServiceHistory/user_emergency_history_page.dart';

class ProfileFormWidget extends StatefulWidget {
  const ProfileFormWidget({Key? key}) : super(key: key);

  @override
  State<ProfileFormWidget> createState() => _ProfileFormWidgetState();
}

class _ProfileFormWidgetState extends State<ProfileFormWidget> {
  late DatabaseReference ref;
  
  // Password update controllers
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  // Location data
  String _address = 'Loading address...';
  bool _isLoadingAddress = true;
  bool _hasFetchedLocation = false;

  // 🔥 Cached user data to show instantly
  Map<String, dynamic>? _cachedUserData;
  bool _dataLoaded = false;
  
  // 🔥 Default values to show immediately
  String _userName = '';
  String _userEmail = '';
  String _userPhone = '';

  @override
  void initState() {
    super.initState();
    ref = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app/',
    ).ref('Users');
    
    // 🔥 Get user immediately from Auth
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userEmail = user.email ?? '';
    }
    
    _loadUserData();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // 🔥 Load user data instantly
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await ref.child(user.uid).get();
      if (snapshot.value != null) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          _cachedUserData = data;
          _dataLoaded = true;
          _userName = data['UserName']?.toString() ?? '';
          _userPhone = data['Phone']?.toString() ?? '';
          _userEmail = data['email']?.toString() ?? user.email ?? '';
          
          // If address exists, show it
          if (data['address'] != null && data['address'].toString().isNotEmpty) {
            _address = data['address'].toString();
            _isLoadingAddress = false;
          }
        });
      }
    } catch (e) {
      // Silent catch
    }

    // Fetch address in background
    _fetchCurrentAddress();
  }

  // Fetch address from location - ONLY ONCE
  Future<void> _fetchCurrentAddress() async {
    if (_hasFetchedLocation) return;
    
    setState(() {
      _isLoadingAddress = true;
    });
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _address = 'Please log in';
        _isLoadingAddress = false;
        _hasFetchedLocation = true;
      });
      return;
    }
    
    try {
      // First, try to get saved address from Firebase (immediate display)
      if (_cachedUserData != null && _cachedUserData!['address'] != null) {
        String savedAddress = _cachedUserData!['address'].toString();
        if (savedAddress.isNotEmpty) {
          setState(() {
            _address = savedAddress;
            _isLoadingAddress = false;
          });
        }
      }
      
      // Now try to get fresh location in background
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          setState(() {
            _isLoadingAddress = false;
            _hasFetchedLocation = true;
          });
          return;
        }

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            setState(() {
              _isLoadingAddress = false;
              _hasFetchedLocation = true;
            });
            return;
          }
        }

        if (permission == LocationPermission.deniedForever) {
          setState(() {
            _isLoadingAddress = false;
            _hasFetchedLocation = true;
          });
          return;
        }

        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks.first;
          String fullAddress = '';
          
          if (place.street != null && place.street!.isNotEmpty) {
            fullAddress += place.street!;
          }
          if (place.subLocality != null && place.subLocality!.isNotEmpty) {
            fullAddress += fullAddress.isNotEmpty ? ', ${place.subLocality}' : place.subLocality!;
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            fullAddress += fullAddress.isNotEmpty ? ', ${place.locality}' : place.locality!;
          }
          if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
            fullAddress += fullAddress.isNotEmpty ? ', ${place.administrativeArea}' : place.administrativeArea!;
          }
          if (place.country != null && place.country!.isNotEmpty) {
            fullAddress += fullAddress.isNotEmpty ? ', ${place.country}' : place.country!;
          }

          setState(() {
            _address = fullAddress.isNotEmpty ? fullAddress : 'Address not available';
            _isLoadingAddress = false;
            _hasFetchedLocation = true;
          });

          await ref.child(user.uid).update({
            'address': fullAddress,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'addressLastUpdated': ServerValue.timestamp,
          });
        } else {
          setState(() {
            _isLoadingAddress = false;
            _hasFetchedLocation = true;
          });
        }
      } catch (e) {
        setState(() {
          _isLoadingAddress = false;
          _hasFetchedLocation = true;
        });
      }
      
    } catch (e) {
      setState(() {
        _address = 'Unable to fetch address';
        _isLoadingAddress = false;
        _hasFetchedLocation = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      return const Center(child: Text('Please log in'));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    // 🔥 Show instantly - no loading state at all
    return _buildProfileContent(isSmallScreen);
  }

  // 🔥 BUILD PROFILE CONTENT - Always shows, no loading
  Widget _buildProfileContent(bool isSmallScreen) {
    final user = FirebaseAuth.instance.currentUser;
    
    // Use cached data if available, otherwise use defaults
    final userName = _userName.isNotEmpty ? _userName : 'Loading...';
    final userEmail = _userEmail.isNotEmpty ? _userEmail : user?.email ?? 'Loading...';
    final userPhone = _userPhone.isNotEmpty ? _userPhone : 'Loading...';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Personal Information Card
        Container(
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
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F4C5C),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                    Flexible(
                      child: Text(
                        'Personal Information',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 17 : 19,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        softWrap: true,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Info items
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildInfoItem(
                      label: 'Full Name',
                      value: userName,
                      icon: Icons.account_circle_rounded,
                      iconColor: const Color(0xFF0F4C5C),
                      isSmallScreen: isSmallScreen,
                    ),
                    _buildDivider(),
                    _buildInfoItem(
                      label: 'Email Address',
                      value: userEmail,
                      icon: Icons.email_outlined,
                      iconColor: const Color(0xFF0F4C5C),
                      isSmallScreen: isSmallScreen,
                    ),
                    _buildDivider(),
                    _buildInfoItem(
                      label: 'Address',
                      value: _isLoadingAddress ? 'Loading...' : _address,
                      icon: Icons.location_on_outlined,
                      iconColor: const Color(0xFF0F4C5C),
                      isSmallScreen: isSmallScreen,
                    ),
                    _buildDivider(),
                    _buildInfoItem(
                      label: 'Phone Number',
                      value: userPhone,
                      icon: Icons.phone_outlined,
                      iconColor: const Color(0xFF0F4C5C),
                      isSmallScreen: isSmallScreen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Update Password Button
        Container(
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
      ],
    );
  }

  Widget _buildInfoItem({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required bool isSmallScreen,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    fontSize: isSmallScreen ? 12 : 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                  maxLines: 5,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      color: Colors.grey.shade100,
    );
  }

  // ============================================================
  // SHOW PASSWORD UPDATE DIALOG
  // ============================================================
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

  // ============================================================
  // UPDATE PASSWORD METHOD
  // ============================================================
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

  // ============================================================
  // EXECUTE PASSWORD UPDATE
  // ============================================================
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
}