import 'dart:async';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sliding_switch/sliding_switch.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';
import 'package:public_emergency_app/Features/User/Controllers/session_controller.dart';
import 'package:public_emergency_app/Features/Login/login_screen.dart';
import 'package:public_emergency_app/Services/doctor_service.dart';
import 'doctor_detail_page.dart';
import 'completed_doctor_page.dart';
import 'doctor_account.dart';
import 'package:public_emergency_app/Features/User/Controllers/call_controller.dart';
import 'package:public_emergency_app/Features/User/Screens/VoicenVideoCall/keys.dart';

class DoctorDashboard extends StatefulWidget {
  const DoctorDashboard({Key? key}) : super(key: key);

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard> {
  // ============================================================
  // FIREBASE & DATABASE REFERENCES
  // ============================================================
  final user = FirebaseAuth.instance.currentUser;
  DatabaseReference? assignedRef;
  DatabaseReference? doctorsRef;
  DatabaseReference? myDoctorRef;
  DatabaseReference? usersRef;
  DatabaseReference? doctorDoneRef;

  // ============================================================
  // STATE VARIABLES
  // ============================================================
  bool _switchValue = false;
  String status = '';
  bool _isLoading = true;
  bool _isInitialized = false;
  Timer? _statusCheckTimer;
  bool _isProcessingRemoval = false;
  bool _isToggling = false;

  String _dashboardTitle = 'Doctor Dashboard';

  int _currentIndex = 0;

  final Map<String, Map<String, String>> _userCache = {};

  String? _processingRequestKey;
  bool _isProcessing = false;

  Timer? _presenceTimer;

  // ============================================================
  // HELPER: Format duration
  // ============================================================
  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h ${duration.inMinutes % 60}m';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m ${duration.inSeconds % 60}s';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    return '$hour:$minute:$second $day/$month/$year';
  }

  // ============================================================
  // LIFECYCLE
  // ============================================================
  @override
  void initState() {
    super.initState();

    _dashboardTitle = 'Doctor Dashboard';

    _clearSavedPreferences();
    
    if (user != null) {
      _initializeFirebaseOnce();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _statusCheckTimer?.cancel();
    _updatePresence(false);
    super.dispose();
  }

  // ============================================================
  // 🔥 INITIALIZE ZEGO FOR RECEIVING CALLS
  // ============================================================
  Future<void> _initializeZegoForReceiving() async {
    try {
      final CallController callController = Get.find<CallController>();
      
      if (user != null) {
        // 🔥 FIX: Fetch fresh name from Firebase every time
        String doctorName = '';
        try {
          final snapshot = await FirebaseDatabase.instance
              .ref('Doctors')
              .child(user!.uid)
              .get();
          if (snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
            doctorName = data['UserName']?.toString() ?? '';
          }
        } catch (e) {
          print("❌ Error fetching doctor name: $e");
        }
        
        // Fallback if not found
        if (doctorName.isEmpty) {
          doctorName = user?.email?.split('@').first ?? 'Doctor';
        }
        
        // 🔥 Update Keys with fresh name
        Keys.currentUserName = doctorName;
        Keys.userId = user!.uid;
        
        // 🔥 Always uninitialize and reinitialize with fresh name
        callController.uninitializeZego();
        await Future.delayed(const Duration(milliseconds: 300));
        await callController.initializeZego(user!.uid, Keys.currentUserName);
        
        print("📞 ZEGO initialized with name: ${Keys.currentUserName}");
      }
    } catch (e) {
      print("❌ Failed to initialize ZEGO on Doctor Dashboard: $e");
    }
  }

  // ============================================================
  // STATUS CHECK
  // ============================================================
  void _startStatusCheck() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (user == null || _isProcessingRemoval || myDoctorRef == null || assignedRef == null) return;
      
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _isProcessingRemoval = true;
        try {
          final snapshot = await assignedRef!.get();
          if (snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
            for (var requestKey in data.keys) {
              await assignedRef!.child(requestKey.toString()).remove();
            }
          }
        } catch (e) {
          print("❌ Error removing requests: $e");
        }
        _isProcessingRemoval = false;
        timer.cancel();
        return;
      }
      
      try {
        final snapshot = await myDoctorRef!.get();
        if (!snapshot.exists) return;
        
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final status = data['status']?.toString() ?? '';
        final isActive = data['isActive'] ?? false;
        final isOnline = data['isOnline'] ?? false;
        final currentRequestId = data['currentRequestId']?.toString() ?? '';
        
        bool isInactive = false;
        if (status == 'inactive' || status == 'Inactive') {
          isInactive = true;
        } else if (!isActive || !isOnline) {
          if (status != 'busy') {
            isInactive = true;
          }
        }
        
        if (isInactive && currentRequestId.isNotEmpty) {
          print("⚠️ Doctor is inactive with request: $currentRequestId - removing");
          _isProcessingRemoval = true;
          
          await assignedRef!.child(currentRequestId).remove();
          
          await myDoctorRef!.update({
            'currentRequestId': null,
            'status': 'inactive',
            'isActive': false,
            'isAvailable': false,
            'isOnline': false,
            'lastActive': 0,
          });
          
          _isProcessingRemoval = false;
          
          _showToggleOffSnackbar('Request removed - You went offline');
          
          if (mounted) setState(() {});
        }
        
      } catch (e) {
        print("❌ Error checking status: $e");
        _isProcessingRemoval = false;
      }
    });
  }

  // ============================================================
  // SHOW TOGGLE OFF SNACKBAR (NO CLOSE BUTTON)
  // ============================================================
  void _showToggleOffSnackbar(String message) {
    Get.snackbar(
      '',
      '',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.transparent,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      borderRadius: 16,
      padding: EdgeInsets.zero,
      barBlur: 0,
      overlayBlur: 0,
      isDismissible: true,
      snackStyle: SnackStyle.FLOATING,
      titleText: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF9800),
              Color(0xFFE65100),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.warning_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      messageText: const SizedBox.shrink(),
    );
  }

  // ============================================================
  // TOGGLE MANAGEMENT
  // ============================================================
 Future<void> _loadSwitchValue() async {
    if (myDoctorRef == null) return;
    try {
        final snapshot = await myDoctorRef!.get();
        if (snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
            final statusValue = data['status']?.toString()?.toLowerCase() ?? 'inactive';
            final isActive = data['isActive'] ?? false;
            final isOnline = data['isOnline'] ?? false;
            
            if (mounted) {
                setState(() {
                    _switchValue = (statusValue == 'active' && isActive && isOnline);
                    status = _switchValue ? 'Active' : 'Inactive';
                });
            }
        }
    } catch (e) {
        debugPrint('❌ Error in _loadSwitchValue: $e');
    }
}

  Future<void> _saveSwitchValue(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('switchValue', value);
    } catch (e) {
      // Silent catch
    }
  }

  // ============================================================
  // SET DOCTOR STATUS
  // ============================================================
  Future<void> _setDoctorActive() async {
    if (user == null || !_isInitialized || myDoctorRef == null) return;
    try {
      // Clear any stale request when turning ON
      if (assignedRef != null) {
        try {
          final snapshot = await assignedRef!.get();
          if (snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
            for (var requestKey in data.keys) {
              await assignedRef!.child(requestKey.toString()).remove();
            }
          }
        } catch (e) {
          debugPrint('❌ Error clearing stale request on toggle ON: $e');
        }
      }

      final updates = <String, dynamic>{
        'isActive': true,
        'isAvailable': true,
        'status': 'active',
        'currentRequestId': null,
        'isOnline': true,
        'lastActive': DateTime.now().millisecondsSinceEpoch,
      };

      await myDoctorRef!.update(updates);
      
      if (_presenceTimer == null || !_presenceTimer!.isActive) {
        _startPresenceTracking();
      }
    } catch (e) {
      debugPrint('❌ Error setting doctor active: $e');
    }
  }

  Future<void> _setDoctorInactive() async {
    if (!_isInitialized || myDoctorRef == null) return;
    try {
      bool hadRequest = false;
      
      // Remove any assigned request when toggling OFF
      if (assignedRef != null) {
        try {
          final snapshot = await assignedRef!.get();
          if (snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
            if (data.isNotEmpty) {
              hadRequest = true;
            }
            for (var requestKey in data.keys) {
              await assignedRef!.child(requestKey.toString()).remove();
            }
          }
        } catch (e) {
          debugPrint('❌ Error removing request on toggle OFF: $e');
        }
      }
      
      await myDoctorRef!.update({
        'isActive': false,
        'isAvailable': false,
        'status': 'inactive',
        'isOnline': false,
        'lastActive': 0,
        'currentRequestId': null,
      });
      
      _presenceTimer?.cancel();
      _presenceTimer = null;
      
      // Show snackbar if request was removed
      if (hadRequest) {
        _showToggleOffSnackbar('Request removed - You turned OFF');
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ Error setting doctor inactive: $e');
    }
  }

  Future<void> setDoctorBusy(String requestId) async {
    if (!_isInitialized || myDoctorRef == null) return;
    try {
      await myDoctorRef!.update({
        'status': 'busy',
        'currentRequestId': requestId,
        'lastAssignedAt': ServerValue.timestamp,
        'isActive': false,
        'isAvailable': false,
      });
    } catch (e) {
      // Silent catch
    }
  }

  Future<void> setDoctorActiveAfterRequest() async {
    if (!_isInitialized || myDoctorRef == null) return;
    try {
      await myDoctorRef!.update({
        'status': 'active',
        'currentRequestId': null,
        'isActive': true,
        'isAvailable': true,
      });
    } catch (e) {
      // Silent catch
    }
  }

  // ============================================================
  // FIREBASE INITIALIZATION - FIXED: ZEGO initializes FIRST
  // ============================================================
  Future<void> _initializeFirebaseOnce() async {
    if (_isInitialized) return;
    
    try {
      // 🔥 FIX: Initialize ZEGO FIRST
      await _initializeZegoForReceiving();
      
      final db = FirebaseDatabase.instance.ref();
      doctorsRef = db.child('Doctors');
      myDoctorRef = db.child('Doctors').child(user!.uid);
      assignedRef = db.child('assigned_doctors').child(user!.uid);
      usersRef = db.child('Users');
      doctorDoneRef = db.child('Doctor_Done');
      
      await _syncFirebaseState();
      await _loadSwitchValue();
      
      _isInitialized = true;
      _isLoading = false;
      
      _startPresenceTracking();
      _startStatusCheck();
      
    } catch (e) {
      debugPrint('❌ Error initializing Firebase: $e');
      _isLoading = false;
    }
  }

  Future<void> _syncFirebaseState() async {
    if (user == null || myDoctorRef == null) return;
    
    try {
      final snapshot = await myDoctorRef!.get();
      if (snapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        final currentStatus = data['status']?.toString() ?? 'inactive';
        
        if (currentStatus == 'inactive' || currentStatus == 'Inactive') {
          await myDoctorRef!.update({
            'isActive': false,
            'isAvailable': false,
            'status': 'inactive',
            'currentRequestId': null,
          });
        }
      } else {
        await myDoctorRef!.set({
          'isActive': false,
          'isAvailable': false,
          'status': 'inactive',
          'UserId': user!.uid,
          'Email': user!.email ?? '',
          'currentRequestId': null,
        });
      }
    } catch (e) {
      debugPrint('❌ Error syncing Firebase state: $e');
    }
  }

  Future<void> _clearSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('switchValue');
    } catch (e) {
      debugPrint('❌ Error clearing preferences: $e');
    }
  }

  // ============================================================
  // PRESENCE TRACKING
  // ============================================================
  void _startPresenceTracking() {
    if (!_switchValue) {
      _updatePresence(false);
      return;
    }
    
    _presenceTimer?.cancel();
    
    _presenceTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_switchValue) {
        _updatePresence(true);
      } else {
        _presenceTimer?.cancel();
        _presenceTimer = null;
        _updatePresence(false);
      }
    });
    _updatePresence(true);
  }

  Future<void> _updatePresence(bool isOnline) async {
    if (user == null || myDoctorRef == null) return;
    
    if (isOnline && !_switchValue) {
      return;
    }
    
    try {
      await myDoctorRef!.update({
        'lastActive': isOnline ? DateTime.now().millisecondsSinceEpoch : 0,
        'isOnline': isOnline,
      });
    } catch (e) {
      debugPrint('❌ Error updating presence: $e');
    }
  }

  // ============================================================
  // FETCH USER DETAILS
  // ============================================================
  Future<Map<String, Map<String, String>>> _fetchAllUserDetails(List<String> userIds) async {
    final Map<String, Map<String, String>> result = {};
    
    final uniqueIds = userIds.where((id) => id.isNotEmpty && !_userCache.containsKey(id)).toSet().toList();
    
    if (uniqueIds.isEmpty) {
      return _userCache;
    }
    
    try {
      for (String userId in uniqueIds) {
        if (!_userCache.containsKey(userId) && userId.isNotEmpty) {
          if (usersRef == null) continue;
          final userRef = usersRef!.child(userId);
          final userSnapshot = await userRef.get();
          String name = 'Unknown User';
          String phone = '';
          if (userSnapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(userSnapshot.value as Map);
            name = data['UserName']?.toString() ?? 'Unknown User';
            phone = data['Phone']?.toString() ?? '';
          }
          _userCache[userId] = {'name': name, 'phone': phone};
        }
      }
    } catch (e) {
      // Silent catch
    }
    
    return _userCache;
  }

  // ============================================================
  // LOGOUT
  // ============================================================
  void _showLogoutDialog() {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.red.shade500,
                      Colors.red.shade700,
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Logout?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Are you sure you want to log out? Any active requests will be reassigned.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Get.back(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Get.back();
                        _performLogout();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4C5C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        'Yes, Logout',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
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
      barrierDismissible: false,
    );
  }

  void _performLogout() async {
    try {
      final CallController callController = Get.find<CallController>();
      callController.uninitializeZego();
      print("✅ ZEGO uninitialized on logout");
    } catch (e) {
      print("⚠️ Could not uninitialize ZEGO: $e");
    }

    _presenceTimer?.cancel();
    _statusCheckTimer?.cancel();
    
    if (assignedRef != null) {
      try {
        final snapshot = await assignedRef!.get();
        if (snapshot.value != null) {
          final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
          for (var requestKey in data.keys) {
            await assignedRef!.child(requestKey.toString()).remove();
          }
        }
      } catch (e) {
        print("❌ Error removing requests on logout: $e");
      }
    }
    
    if (myDoctorRef != null) {
      try {
        await myDoctorRef!.update({
          'isActive': false,
          'isAvailable': false,
          'status': 'inactive',
          'isOnline': false,
          'lastActive': 0,
        });
      } catch (e) {
        print("❌ Error updating doctor status: $e");
      }
    }
    
    try {
      await FirebaseAuth.instance.signOut();
      SessionController().userid = '';
      Get.offAll(() => const LoginScreen());
    } catch (e) {
      Get.offAll(() => const LoginScreen());
    }
  }

  // ============================================================
  // MARK REQUEST AS DONE
  // ============================================================
Future<bool> _markRequestAsDone(String requestId, Map requestData) async {
  try {
    if (myDoctorRef == null || usersRef == null || doctorDoneRef == null || assignedRef == null) {
      _showPremiumErrorSnackbar('Database not initialized');
      return false;
    }

    await Future.delayed(const Duration(milliseconds: 500));
    
    final refreshSnapshot = await myDoctorRef!.get();
    if (!refreshSnapshot.exists) {
      _showPremiumErrorSnackbar('Doctor data not found');
      return false;
    }
    
    final doctorSnapshot = await myDoctorRef!.get();
    Map<String, dynamic> doctorData = {};
    String doctorName = 'Unknown Doctor';
    
    if (doctorSnapshot.value != null) {
      doctorData = Map<String, dynamic>.from(doctorSnapshot.value as Map);
      doctorName = doctorData['UserName']?.toString() ?? 'Unknown Doctor';
    }
    
    final userId = requestData['userId']?.toString() ?? '';
    String userName = requestData['userName']?.toString() ?? 'Unknown User';
    String userPhone = requestData['userPhone']?.toString() ?? '';
    String userEmail = requestData['userEmail']?.toString() ?? '';
    
    if (userId.isNotEmpty) {
      final userSnapshot = await usersRef!.child(userId).get();
      if (userSnapshot.value != null) {
        final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
        userName = userData['UserName']?.toString() ?? userName;
        userPhone = userData['Phone']?.toString() ?? userPhone;
        userEmail = userData['Email']?.toString() ?? userEmail;
      }
    }
    
    int requestTimeMs = requestData['assignedAt'] as int? ?? 0;
    String requestTimeFormatted = 'Unknown';
    if (requestTimeMs > 0) {
      final requestDateTime = DateTime.fromMillisecondsSinceEpoch(requestTimeMs);
      requestTimeFormatted = _formatDateTime(requestDateTime);
    }
    
    String sessionTime = 'N/A';
    int sessionTimeMs = 0;
    if (requestTimeMs > 0) {
      final now = DateTime.now();
      final completedAtMs = now.millisecondsSinceEpoch;
      sessionTimeMs = completedAtMs - requestTimeMs;
      sessionTime = _formatDuration(Duration(milliseconds: sessionTimeMs));
    }
    
    User? currentUser = FirebaseAuth.instance.currentUser;
    String currentUserEmail = currentUser?.email ?? '';
    String currentUserUid = currentUser?.uid ?? '';
    
    // ✅ requestId is already passed as parameter - use it directly
    final completedData = {
      'requestId': requestId,
      'currentRequestId': requestId, // ✅ Just pass the requestId parameter
      'userInfo': {
        'uid': userId,
        'name': userName,
        'phone': userPhone,
        'email': userEmail,
        'timestamp': ServerValue.timestamp,
      },
      'completedBy': {
        'uid': currentUserUid,
        'name': doctorName,
        'email': currentUserEmail,
        'type': 'Doctor',
      },
      'completedAt': DateTime.now().toIso8601String(),
      'timestamp': ServerValue.timestamp,
      'status': 'completed',
      'requestTime': requestTimeMs,
      'requestTimeFormatted': requestTimeFormatted,
      'sessionTime': sessionTime,
      'sessionTimeMs': sessionTimeMs,
    };
    
    await doctorDoneRef!.child(requestId).set(completedData);
    await assignedRef!.child(requestId).remove();
    
    if (userId.isNotEmpty) {
      await FirebaseDatabase.instance
          .ref('Users')
          .child(userId)
          .child('activeDoctor')
          .remove();
    }
    
    await setDoctorActiveAfterRequest();
    
    _showPremiumCompleteSnackbar(
      requestId: requestId,
      requestData: requestData,
      completedData: completedData,
    );
    
    return true;
  } catch (e) {
    _showPremiumErrorSnackbar('Failed to complete request');
    return false;
  }
}
  // ============================================================
  // UNDO COMPLETE REQUEST
  // ============================================================
  Future<bool> _undoCompleteRequest(
    String requestId,
    Map requestData,
    Map completedData,
  ) async {
    try {
      if (doctorDoneRef == null || assignedRef == null || myDoctorRef == null) {
        _showPremiumErrorSnackbar('Database not initialized');
        return false;
      }
      
      await doctorDoneRef!.child(requestId).remove();
      await assignedRef!.child(requestId).set(requestData);
      
      await myDoctorRef!.update({
        'status': 'busy',
        'currentRequestId': requestId,
        'isActive': false,
        'isAvailable': false,
      });
      
      _showRestoredSnackbar();
      return true;
    } catch (e) {
      _showPremiumErrorSnackbar('Failed to restore');
      return false;
    }
  }

  // ============================================================
  // RESTORED SNACKBAR (NO CLOSE BUTTON)
  // ============================================================
  void _showRestoredSnackbar() {
    Get.snackbar(
      '',
      '',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.transparent,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      borderRadius: 16,
      padding: EdgeInsets.zero,
      barBlur: 0,
      overlayBlur: 0,
      isDismissible: true,
      snackStyle: SnackStyle.FLOATING,
      titleText: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF9800),
              Color(0xFFE65100),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.restore_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Restored',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
      messageText: const SizedBox.shrink(),
    );
  }

  // ============================================================
  // SNACKBARS (NO CLOSE BUTTON)
  // ============================================================
  void _showPremiumCompleteSnackbar({
    required String requestId,
    required Map requestData,
    required Map completedData,
  }) {
    Get.snackbar(
      '',
      '',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.transparent,
      colorText: Colors.white,
      duration: const Duration(seconds: 5),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      borderRadius: 16,
      padding: EdgeInsets.zero,
      barBlur: 0,
      overlayBlur: 0,
      isDismissible: true,
      snackStyle: SnackStyle.FLOATING,
      titleText: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF43A047),
              Color(0xFF2E7D32),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Completed',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                await _undoCompleteRequest(requestId, requestData, completedData);
                Get.closeCurrentSnackbar();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.undo_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Undo',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      messageText: const SizedBox.shrink(),
    );
  }

  void _showPremiumErrorSnackbar(String message) {
    Get.snackbar(
      '',
      '',
      snackPosition: SnackPosition.TOP,
      backgroundColor: Colors.transparent,
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      borderRadius: 16,
      padding: EdgeInsets.zero,
      barBlur: 0,
      overlayBlur: 0,
      isDismissible: true,
      snackStyle: SnackStyle.FLOATING,
      titleText: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE53935),
              Color(0xFFC62828),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
      messageText: const SizedBox.shrink(),
    );
  }

  // ============================================================
  // CONTACT VERIFICATION DIALOG
  // ============================================================
  Future<bool?> _showContactVerificationDialog(Map requestData) async {
    String userName = requestData['userName']?.toString() ?? 'the patient';
    
    return await Get.dialog<bool>(
      Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0F4C5C),
                      Color(0xFF1A7A8C),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.medical_services_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Consultation Complete?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F4C5C),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'Have you successfully completed the consultation with "'),
                    TextSpan(
                      text: userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F4C5C),
                        fontSize: 16,
                      ),
                    ),
                    const TextSpan(text: '"?'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF0F4C5C).withValues(alpha: 0.08),
                      const Color(0xFF0F4C5C).withValues(alpha: 0.04),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF0F4C5C).withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.info_outline,
                        color: const Color(0xFF0F4C5C).withValues(alpha: 0.6),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'This confirms you have provided medical consultation to this patient.',
                        textAlign: TextAlign.justify,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Get.back(result: false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: const Text(
                        'Not Yet',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Get.back(result: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: const Text(
                        'Yes',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
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
      barrierDismissible: false,
    );
  }

  void _navigateToCompleted() {
    final doctorId = user?.uid ?? '';
    if (doctorId.isEmpty) {
      Get.snackbar(
        'Error',
        'Unable to load completed requests',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      return;
    }
    
    Get.to(() => CompletedDoctorPage(
          doctorId: doctorId,
        ));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 60,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          const Text(
            'No active requests assigned',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _navigateToCompleted,
            icon: const Icon(Icons.history),
            label: const Text('View history'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0F4C5C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    if (user == null) {
      return const Center(child: Text('No user logged in'));
    }
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F4C5C),
        centerTitle: true,
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(Get.height * 0.22),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 0),
                      child: Image.asset('assets/logos/emergencyAppLogo.png',
                          height: Get.height * 0.07),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _dashboardTitle,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    SlidingSwitch(
                      value: _switchValue,
                      width: 100,
                      height: 40,
                      textOff: 'OFF',
                      textOn: 'ON',
                      colorOn: Colors.green,
                      colorOff: Colors.red,
                     onChanged: (value) async {
    if (_isToggling) return;
    _isToggling = true;
    
    setState(() {
        _switchValue = value;
        status = value ? 'Active' : 'Inactive';
    });
    
    if (value) {
        await _setDoctorActive();
    } else {
        await _setDoctorInactive();
    }
    
    await _saveSwitchValue(value);
    _isToggling = false;
},
                      onTap: () {},
                      onDoubleTap: () {},
                      onSwipe: () {},
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                top: 6,
                child: GestureDetector(
                  onTap: _showLogoutDialog,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.red,
                          Colors.redAccent,
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          if (assignedRef != null)
            Dismissible(
              key: const Key('completion_badge'),
              direction: DismissDirection.endToStart,
              onDismissed: (direction) {
                setState(() {});
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Dismiss',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                      size: 24,
                    ),
                  ],
                ),
              ),
              child: StreamBuilder<DatabaseEvent>(
                stream: assignedRef!.onValue,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox.shrink();
                  }
                  final rawData = snapshot.data?.snapshot.value;
                  if (rawData == null) {
                    return const SizedBox.shrink();
                  }
                  final data = Map<dynamic, dynamic>.from(rawData as Map);
                  final entries = data.entries.toList();
                  if (entries.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _buildCompletionBadge();
                },
              ),
            ),
          
          const SizedBox(height: 8),
          
          Expanded(
            child: assignedRef != null
                ? StreamBuilder<DatabaseEvent>(
                  stream: assignedRef!.onValue,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting ||
                        !snapshot.hasData) {
                      return _buildEmptyState();
                    }
                    final rawData = snapshot.data!.snapshot.value;
                    if (rawData == null) {
                      return _buildEmptyState();
                    }

                    final data = Map<dynamic, dynamic>.from(rawData as Map);
                    final List<MapEntry<dynamic, dynamic>> entries = data.entries.toList();
                    
                    entries.sort((a, b) => b.key.toString().compareTo(a.key.toString()));

                    if (entries.isEmpty) {
                      return _buildEmptyState();
                    }

                    final userIds = entries
                        .map((e) => e.value['userId']?.toString() ?? '')
                        .where((id) => id.isNotEmpty)
                        .toList();

                    if (userIds.isEmpty) {
                      return _buildRequestList(entries, {});
                    }

                    return FutureBuilder<Map<String, Map<String, String>>>(
                      future: _fetchAllUserDetails(userIds),
                      builder: (context, userDataSnapshot) {
                        if (userDataSnapshot.connectionState == ConnectionState.waiting && 
                            _userCache.isEmpty) {
                          return _buildEmptyState();
                        }

                        final userData = userDataSnapshot.data ?? _userCache;
                        return _buildRequestList(entries, userData);
                      },
                    );
                  },
                )
                : _buildEmptyState(),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionBadge() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F4C5C).withValues(alpha: 0.08),
            const Color(0xFF0F4C5C).withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF0F4C5C).withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: const Color(0xFF0F4C5C).withValues(alpha: 0.6),
            size: 18,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Swipe right on a request to mark it as completed after consultation',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
                height: 1.3,
              ),
            ),
          ),
          GestureDetector(
            onTap: _navigateToCompleted,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0F4C5C),
                    Color(0xFF1A7A8C),
                  ],
                ),
                borderRadius: BorderRadius.all(Radius.circular(10)),
              ),
              child: const Text(
                'View',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestList(
    List<MapEntry<dynamic, dynamic>> entries,
    Map<String, Map<String, String>> userData,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final requestKey = entry.key;
        final Map list = Map<dynamic, dynamic>.from(entry.value);
        
        String requestTime = '';
        if (list['assignedAt'] != null) {
          try {
            final timestamp = list['assignedAt'];
            if (timestamp is int) {
              final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
              requestTime = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} ${dateTime.day}/${dateTime.month}/${dateTime.year}';
            }
          } catch (e) {
            requestTime = 'Unknown time';
          }
        }

        if (requestTime.isEmpty) {
          requestTime = 'Unknown time';
        }
        
        final userId = list['userId']?.toString() ?? '';
        
        String userName = list['userName']?.toString() ?? 'Unknown User';
        String userPhone = list['userPhone']?.toString() ?? '';
        
        if (userName == 'Unknown User' && userId.isNotEmpty) {
          if (userData.containsKey(userId)) {
            userName = userData[userId]?['name'] ?? 'Unknown User';
          } else if (_userCache.containsKey(userId)) {
            userName = _userCache[userId]?['name'] ?? 'Unknown User';
          }
        }
        
        if (userPhone.isEmpty && userId.isNotEmpty) {
          if (userData.containsKey(userId)) {
            userPhone = userData[userId]?['phone'] ?? '';
          } else if (_userCache.containsKey(userId)) {
            userPhone = _userCache[userId]?['phone'] ?? '';
          }
        }

        final bool isProcessing = _processingRequestKey == requestKey || _isProcessing;

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          child: Dismissible(
            key: Key(requestKey),
            direction: DismissDirection.startToEnd,
            
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                if (isProcessing) {
                  return false;
                }
                
                bool? confirmed = await _showContactVerificationDialog(list);
                
                if (confirmed == true) {
                  _isProcessing = true;
                  _processingRequestKey = requestKey;
                  
                  final String key = requestKey;
                  final Map data = Map.from(list);
                  
                  bool success = await _markRequestAsDone(key, data);
                  
                  _isProcessing = false;
                  _processingRequestKey = null;
                  
                  if (!success && mounted) {
                    setState(() {});
                    return false;
                  }
                  
                  return true;
                } else {
                  return false;
                }
              }
              
              return false;
            },
            
            onDismissed: (direction) {
              // Work is already done in confirmDismiss
            },
            
            background: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xFF4CAF50),
                    Color(0xFFC8E6C9),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mark as Done',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Swipe to complete this request',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            child: GestureDetector(
  onTap: () {
    Get.to(() => DoctorDetailPage(
          requestData: list,
          requestId: requestKey,
          userName: userName,
          userPhone: userPhone,
          requestTime: requestTime,
        ));
  },
  child: Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0F4C5C),
          Color(0xFF1A7A8C),
        ],
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Name
                Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Phone with icon
                Row(
                  children: [
                    const Icon(
                      Icons.phone_rounded,
                      color: Colors.white70,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      userPhone.isNotEmpty ? userPhone : 'No Phone',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Time with icon
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      color: Colors.white70,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      requestTime,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.green.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  color: Colors.green,
                  size: 6,
                ),
                SizedBox(width: 4),
                Text(
                  'Active',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
),
          ),
        );
      },
    );
  }

  // ============================================================
  // MAIN BUILD METHOD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeContent(),
          const DoctorAccountPage(),
        ],
      ),
      bottomNavigationBar: AnimatedBottomNavigationBar(
        icons: const [
          Icons.home_rounded,
          Icons.person_rounded,
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