import 'dart:io';
import 'dart:math';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';
import 'package:public_emergency_app/Features/User/Screens/Profile/profile_screen.dart';
import 'package:public_emergency_app/Features/User/Screens/VoicenVideoCall/videoncall.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sliding_switch/sliding_switch.dart';
import 'package:url_launcher/url_launcher.dart';
import '../User/Controllers/message_sending.dart';
import '../Login/login_screen.dart';
import '../User/Controllers/session_controller.dart';
import 'emergency_detail_page.dart';
import 'completed_emergencies_page.dart';
import 'responder_account.dart';
import 'dart:async';
import 'package:public_emergency_app/Services/emergency_assignment_service.dart';
import 'package:public_emergency_app/Features/User/Controllers/call_controller.dart';
import 'package:public_emergency_app/Features/User/Screens/VoicenVideoCall/keys.dart';

class ResponderDashboard extends StatefulWidget {
  final String userType;
  const ResponderDashboard({Key? key, this.userType = 'Responder'}) : super(key: key);
  @override
  State<ResponderDashboard> createState() => _ResponderDashboardState();
}

class _ResponderDashboardState extends State<ResponderDashboard> {
  // ============================================================
  // FIREBASE & DATABASE REFERENCES
  // ============================================================
  final user = FirebaseAuth.instance.currentUser;
  final locationController = Get.put(MessageController());
  DatabaseReference? assignedRef;
  DatabaseReference? respondersRef;
  DatabaseReference? myResponderRef;
  DatabaseReference? usersRef;
  DatabaseReference? sosDoneRef;
  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app';
  
  // ============================================================
  // STATE VARIABLES
  // ============================================================
  bool _switchValue = false;
  String status = '';
  String userType = '';
  
  bool _isInitialized = false;
  Timer? _responderStatusCheckTimer;
  bool _isProcessingRemoval = false;

  String _dashboardTitle = 'Responder Dashboard';

  int _currentIndex = 0;

  final Map<String, Map<String, String>> _userCache = {};

  Map<dynamic, dynamic>? _cachedEmergencyData;
  String? _cachedEmergencyKey;

  String? _processingEmergencyKey;
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
  // LIFECYCLE METHODS
  // ============================================================
  @override
  void initState() {
    super.initState();

    _dashboardTitle = '${widget.userType} Dashboard';
    
    _clearSavedPreferences();
    
    if (user != null) {
      _initializeFirebaseOnce();
    }
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    _responderStatusCheckTimer?.cancel();
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
        callController.uninitializeZego();
        await Future.delayed(const Duration(milliseconds: 300));
        
        String responderName = '';
        try {
          final snapshot = await FirebaseDatabase.instance
              .ref('Responders')
              .child(user!.uid)
              .get();
          if (snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
            responderName = data['UserName']?.toString() ?? '';
          }
        } catch (e) {
          print("❌ Error fetching responder name: $e");
        }
        
        if (responderName.isEmpty) {
          responderName = user?.email?.split('@').first ?? 'Responder';
        }
        
        Keys.currentUserName = responderName;
        Keys.userId = user!.uid;
        
        await callController.initializeZego(user!.uid, Keys.currentUserName);
        
        print("📞 ZEGO initialized with name: ${Keys.currentUserName}");
      }
    } catch (e) {
      print("❌ Failed to initialize ZEGO: $e");
    }
  }

  // ============================================================
  // RESPONDER STATUS CHECK - FIXED AUTO-DELETE
  // ============================================================
  void _startResponderStatusCheck() {
    _responderStatusCheckTimer?.cancel();
    _responderStatusCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (user == null || _isProcessingRemoval || myResponderRef == null || assignedRef == null) return;
      
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _isProcessingRemoval = true;
        
        try {
          final snapshot = await assignedRef!.get();
          if (snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
            for (var emergencyKey in data.keys) {
              final emergencySnapshot = await assignedRef!.child(emergencyKey.toString()).get();
              Map emergencyData = {};
              if (emergencySnapshot.exists) {
                emergencyData = Map<String, dynamic>.from(emergencySnapshot.value as Map);
              }
              
              await assignedRef!.child(emergencyKey.toString()).remove();
              
              if (emergencyData.isNotEmpty) {
                final userId = emergencyData['userID']?.toString() ?? '';
                
                if (userId.isNotEmpty) {
                  await FirebaseDatabase.instance
                      .ref('Users')
                      .child(userId)
                      .child('activeEmergency')
                      .remove();
                      
                  await FirebaseDatabase.instance
                      .ref('assigned_emergencies')
                      .child(userId)
                      .child(emergencyKey.toString())
                      .remove();
                }
              }
            }
          }
        } catch (e) {
          print("❌ Error removing emergency on logout: $e");
        }
        
        _isProcessingRemoval = false;
        
        Get.snackbar(
          'Notice',
          'You logged out.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
          margin: const EdgeInsets.all(16),
          borderRadius: 12,
        );
        
        if (mounted) {
          setState(() {});
        }
        
        timer.cancel();
        return;
      }
      
      try {
        final snapshot = await myResponderRef!.get();
        if (!snapshot.exists) return;
        
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final status = data['status']?.toString() ?? '';
        final isActive = data['isActive'] ?? false;
        final isOnline = data['isOnline'] ?? false;
        final currentEmergencyId = data['currentEmergencyId']?.toString() ?? '';
        
        bool isInactive = false;
        
        if (status == 'inactive' || status == 'Inactive') {
          if (currentEmergencyId.isEmpty) {
            isInactive = true;
          } else {
            print("🟡 Responder is inactive but has emergency - keeping it");
          }
        } else if (!isActive || !isOnline) {
          if (status != 'busy' && currentEmergencyId.isEmpty) {
            isInactive = true;
          }
        }
        
        if (isInactive && currentEmergencyId.isNotEmpty) {
          print("⚠️ Responder is inactive with emergency: $currentEmergencyId - removing");
          _isProcessingRemoval = true;
          
          final emergencySnapshot = await assignedRef!.child(currentEmergencyId).get();
          Map emergencyData = {};
          if (emergencySnapshot.exists) {
            emergencyData = Map<String, dynamic>.from(emergencySnapshot.value as Map);
          }
          
          await assignedRef!.child(currentEmergencyId).remove();
          
          await myResponderRef!.update({
            'currentEmergencyId': null,
            'currentEmergency': null,
            'status': 'inactive',
            'isActive': false,
            'isAvailable': false,
            'isOnline': false,
            'lastActive': 0,
          });
          
          if (emergencyData.isNotEmpty) {
            final userId = emergencyData['userID']?.toString() ?? '';
            
            if (userId.isNotEmpty) {
              await FirebaseDatabase.instance
                  .ref('Users')
                  .child(userId)
                  .child('activeEmergency')
                  .remove();
                  
              await FirebaseDatabase.instance
                  .ref('assigned_emergencies')
                  .child(userId)
                  .child(currentEmergencyId)
                  .remove();
            }
          }
          
          _isProcessingRemoval = false;
          
          _showToggleOffSnackbar('Emergency removed - You went offline');
          
          if (mounted) {
            setState(() {});
          }
        }
        
      } catch (e) {
        print("❌ Error checking responder status: $e");
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
  // SWITCH VALUE MANAGEMENT
  // ============================================================
  Future<void> _loadSwitchValue() async {
    if (myResponderRef == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      
      bool firebaseActive = false;
      try {
        final responderSnapshot = await myResponderRef!.get();
        if (responderSnapshot.value != null) {
          final data = Map<dynamic, dynamic>.from(responderSnapshot.value as Map);
          final statusValue = data['status']?.toString() ?? 'inactive';
          firebaseActive = (statusValue == 'active' || statusValue == 'Active');
          debugPrint('📡 Firebase status: $statusValue, active: $firebaseActive');
        }
      } catch (e) {
        debugPrint('❌ Error reading Firebase status: $e');
        firebaseActive = false;
      }
      
      final savedValue = prefs.getBool('switchValue') ?? false;
      debugPrint('📱 Saved preference: $savedValue');
      debugPrint('🔥 Firebase active: $firebaseActive');
      
      if (!firebaseActive) {
        debugPrint('⚠️ Firebase says inactive - forcing toggle OFF');
        
        if (assignedRef != null) {
          try {
            final snapshot = await assignedRef!.get();
            if (snapshot.value != null) {
              final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
              for (var emergencyKey in data.keys) {
                await assignedRef!.child(emergencyKey.toString()).remove();
              }
            }
          } catch (e) {
            debugPrint('❌ Error removing emergency in load: $e');
          }
        }
        
        if (!mounted) return;
        setState(() {
          _switchValue = false;
          status = 'Inactive';
        });
        await prefs.setBool('switchValue', false);
        await _setResponderInactive();
        return;
      }
      
      if (!mounted) return;
      setState(() {
        _switchValue = savedValue;
        status = _switchValue ? 'Active' : 'Inactive';
      });
      
      if (_switchValue) {
        await _setResponderActive();
      } else {
        await _setResponderInactive();
      }
    } catch (e) {
      debugPrint('❌ Error in _loadSwitchValue: $e');
      if (!mounted) return;
      setState(() {
        _switchValue = false;
        status = 'Inactive';
      });
      await _setResponderInactive();
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
  // SET RESPONDER STATUS
  // ============================================================
  Future<void> _setResponderActive() async {
    if (user == null || !_isInitialized || myResponderRef == null) return;
    try {
      if (assignedRef != null) {
        try {
          final snapshot = await assignedRef!.get();
          if (snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
            for (var emergencyKey in data.keys) {
              await assignedRef!.child(emergencyKey.toString()).remove();
            }
          }
        } catch (e) {
          debugPrint('❌ Error clearing stale emergency on toggle ON: $e');
        }
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        // Silent catch
      }

      final updates = <String, dynamic>{
        'isActive': true,
        'isAvailable': true,
        'status': 'active',
        'currentEmergencyId': null,
        'currentEmergency': null,
        'isOnline': true,
        'lastActive': DateTime.now().millisecondsSinceEpoch,
      };

      if (position != null) {
        updates['lat'] = position.latitude.toString();
        updates['long'] = position.longitude.toString();
      } else {
        updates['lat'] = '';
        updates['long'] = '';
      }

      await myResponderRef!.update(updates);
      
      if (_presenceTimer == null || !_presenceTimer!.isActive) {
        _startPresenceTracking();
      }
    } catch (e) {
      debugPrint('❌ Error setting responder active: $e');
    }
  }

  Future<void> _setResponderInactive() async {
    if (!_isInitialized || myResponderRef == null) return;
    try {
      bool hadEmergency = false;
      
      if (assignedRef != null) {
        try {
          final snapshot = await assignedRef!.get();
          if (snapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
            if (data.isNotEmpty) {
              hadEmergency = true;
            }
            for (var emergencyKey in data.keys) {
              await assignedRef!.child(emergencyKey.toString()).remove();
            }
          }
        } catch (e) {
          debugPrint('❌ Error removing emergency on toggle OFF: $e');
        }
      }
      
      await myResponderRef!.update({
        'isActive': false,
        'isAvailable': false,
        'status': 'inactive',
        'isOnline': false,
        'lastActive': 0,
        'currentEmergencyId': null,
        'currentEmergency': null,
      });
      
      _presenceTimer?.cancel();
      _presenceTimer = null;
      debugPrint('📡 Presence tracking stopped');
      
      if (hadEmergency) {
        _showToggleOffSnackbar('Emergency removed - You turned OFF');
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ Error setting responder inactive: $e');
    }
  }

  Future<void> setResponderBusy(String emergencyId) async {
    if (!_isInitialized || myResponderRef == null) return;
    try {
      await myResponderRef!.update({
        'status': 'busy',
        'currentEmergencyId': emergencyId,
        'lastAssignedAt': ServerValue.timestamp,
        'isActive': false,
        'isAvailable': false,
      });
    } catch (e) {
      // Silent catch
    }
  }

  Future<void> setResponderActiveAfterEmergency() async {
    if (!_isInitialized || myResponderRef == null) return;
    try {
      await myResponderRef!.update({
        'status': 'active',
        'currentEmergencyId': null,
        'isActive': true,
        'isAvailable': true,
      });
    } catch (e) {
      // Silent catch
    }
  }

  Future<void> _updateDashboardTitle() async {
    if (user == null || !_isInitialized || myResponderRef == null) return;
    
    try {
      final snapshot = await myResponderRef!.get();
      if (snapshot.value != null) {
        final map = Map<dynamic, dynamic>.from(snapshot.value as Map);
        final userType = map['UserType']?.toString() ?? 'Responder';
        if (mounted) {
          setState(() {
            _dashboardTitle = '$userType Dashboard';
          });
        }
      }
    } catch (e) {
      // Silent catch
    }
  }

  // ============================================================
  // FIREBASE INITIALIZATION
  // ============================================================
  Future<void> _initializeFirebaseOnce() async {
    if (_isInitialized) return;
    
    try {
      await Firebase.initializeApp();
      
      await _initializeZegoForReceiving();
      
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      );
      respondersRef = db.ref().child('Responders');
      myResponderRef = db.ref().child('Responders').child(user!.uid);
      assignedRef = db.ref().child('assigned').child(user!.uid);
      usersRef = db.ref().child('Users');
      sosDoneRef = db.ref().child('SOS_Done');
      
      await Future.wait([
        _syncFirebaseState(),
        _loadSwitchValue(),
      ]);
      
      setState(() {
        _isInitialized = true;
      });
      
      _startPresenceTracking();
      _startResponderStatusCheck();
      
    } catch (e) {
      debugPrint('❌ Error initializing Firebase: $e');
    }
  }

  Future<void> _syncFirebaseState() async {
    if (user == null || myResponderRef == null) return;
    
    try {
      final responderSnapshot = await myResponderRef!.get();
      if (responderSnapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(responderSnapshot.value as Map);
        final currentStatus = data['status']?.toString() ?? 'inactive';
        
        debugPrint('📡 Current Firebase status: $currentStatus');
        
        if (currentStatus == 'inactive' || currentStatus == 'Inactive') {
          debugPrint('🔄 Syncing Firebase to inactive state...');
          await myResponderRef!.update({
            'isActive': false,
            'isAvailable': false,
            'status': 'inactive',
            'currentEmergencyId': null,
            'currentEmergency': null,
          });
          debugPrint('✅ Firebase synced to inactive');
        }
      } else {
        debugPrint('🆕 New user - creating with inactive state');
        await myResponderRef!.set({
          'isActive': false,
          'isAvailable': false,
          'status': 'inactive',
          'UserId': user!.uid,
          'Email': user!.email ?? '',
          'currentEmergencyId': null,
          'currentEmergency': null,
        });
      }
    } catch (e) {
      debugPrint('❌ Error syncing Firebase state: $e');
    }
  }

  Future<void> _verifyToggleState() async {
    if (myResponderRef == null) return;
    try {
      final responderSnapshot = await myResponderRef!.get();
      if (responderSnapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(responderSnapshot.value as Map);
        final statusValue = data['status']?.toString() ?? 'inactive';
        final isActive = data['isActive'] ?? false;
        
        debugPrint('🔍 Verification - status: $statusValue, isActive: $isActive');
        debugPrint('🔍 UI - _switchValue: $_switchValue, status: $status');
        
        if (statusValue == 'inactive' && _switchValue == true) {
          debugPrint('⚠️ MISMATCH DETECTED - Fixing UI');
          if (!mounted) return;
          setState(() {
            _switchValue = false;
            status = 'Inactive';
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('switchValue', false);
        }
      }
    } catch (e) {
      debugPrint('❌ Verification error: $e');
    }
  }

  Future<void> _clearSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('switchValue');
      debugPrint('✅ Cleared saved switch preference');
    } catch (e) {
      debugPrint('❌ Error clearing preferences: $e');
    }
  }

  // ============================================================
  // PRESENCE TRACKING
  // ============================================================
  void _startPresenceTracking() {
    if (!_switchValue) {
      debugPrint('📡 Toggle is OFF - not starting presence tracking');
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
    if (user == null || myResponderRef == null) return;
    
    if (isOnline && !_switchValue) {
      debugPrint('📡 Toggle is OFF - skipping presence update');
      return;
    }
    
    try {
      await myResponderRef!.update({
        'lastActive': isOnline ? DateTime.now().millisecondsSinceEpoch : 0,
        'isOnline': isOnline,
      });
      debugPrint('📡 Presence updated: isOnline=$isOnline, lastActive=${DateTime.now().millisecondsSinceEpoch}');
    } catch (e) {
      debugPrint('❌ Error updating presence: $e');
    }
  }

  // ============================================================
  // DISTANCE CALCULATION
  // ============================================================
  double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) *
            cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p)) /
            2;
    return 12742 * asin(sqrt(a));
  }

  String getDistance(Map list) {
    try {
      if (list['userLat'] == null ||
          list['userLong'] == null ||
          list['responderLat'] == null ||
          list['responderLong'] == null) return '';
      double dist = calculateDistance(
        double.tryParse(list['userLat'].toString()) ?? 0.0,
        double.tryParse(list['userLong'].toString()) ?? 0.0,
        double.tryParse(list['responderLat'].toString()) ?? 0.0,
        double.tryParse(list['responderLong'].toString()) ?? 0.0,
      );
      return '${dist.toStringAsFixed(2)} km';
    } catch (e) {
      return '';
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
          String address = '';
          if (userSnapshot.value != null) {
            final data = Map<dynamic, dynamic>.from(userSnapshot.value as Map);
            name = data['UserName']?.toString() ?? 'Unknown User';
            phone = data['Phone']?.toString() ?? '';
            address = data['Address']?.toString() ?? 'No Address';
          }
          _userCache[userId] = {'name': name, 'phone': phone, 'address': address};
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
                'Are you sure you want to log out? Any active emergencies will be reassigned.',
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

    final currentUser = FirebaseAuth.instance.currentUser;
    final String? uid = currentUser?.uid;
    
    _presenceTimer?.cancel();
    _responderStatusCheckTimer?.cancel();
    
    if (assignedRef != null && uid != null) {
      try {
        final snapshot = await assignedRef!.get();
        if (snapshot.value != null) {
          final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
          for (var emergencyKey in data.keys) {
            final emergencySnapshot = await assignedRef!.child(emergencyKey.toString()).get();
            Map emergencyData = {};
            if (emergencySnapshot.exists) {
              emergencyData = Map<String, dynamic>.from(emergencySnapshot.value as Map);
            }
            
            await assignedRef!.child(emergencyKey.toString()).remove();
            
            if (emergencyData.isNotEmpty) {
              final userId = emergencyData['userID']?.toString() ?? '';
              
              if (userId.isNotEmpty) {
                await FirebaseDatabase.instance
                    .ref('Users')
                    .child(userId)
                    .child('activeEmergency')
                    .remove();
                    
                await FirebaseDatabase.instance
                    .ref('assigned_emergencies')
                    .child(userId)
                    .child(emergencyKey.toString())
                    .remove();
              }
            }
          }
        }
      } catch (e) {
        print("❌ Error removing emergency on logout: $e");
      }
    }
    
    if (myResponderRef != null) {
      try {
        await myResponderRef!.update({
          'isActive': false,
          'isAvailable': false,
          'status': 'inactive',
          'isOnline': false,
          'lastActive': 0,
        });
      } catch (e) {
        print("❌ Error updating responder status: $e");
      }
    }
    
    try {
      await FirebaseAuth.instance.signOut();
      SessionController().userid = '';
      Get.offAll(() => const LoginScreen());
    } catch (e) {
      print("❌ Error signing out: $e");
      Get.offAll(() => const LoginScreen());
    }
  }

  // ============================================================
  // MARK EMERGENCY AS DONE
  // ============================================================
  Future<bool> _markEmergencyAsDone(String emergencyKey, Map emergencyData) async {
    try {
      if (myResponderRef == null || usersRef == null || sosDoneRef == null || assignedRef == null) {
        _showPremiumErrorSnackbar('Database not initialized');
        return false;
      }

      await Future.delayed(const Duration(milliseconds: 500));
      
      final refreshSnapshot = await myResponderRef!.get();
      if (!refreshSnapshot.exists) {
        _showPremiumErrorSnackbar('Responder data not found');
        return false;
      }
      
      final responderSnapshot = await myResponderRef!.get();
      Map<String, dynamic> responderData = {};
      String responderName = 'Unknown Responder';
      String responderType = 'Responder';
      
      if (responderSnapshot.value != null) {
        responderData = Map<String, dynamic>.from(responderSnapshot.value as Map);
        responderName = responderData['UserName']?.toString() ?? 'Unknown Responder';
        responderType = responderData['UserType']?.toString() ?? 'Responder';
      }
      
      final userId = emergencyData['userID']?.toString() ?? '';
      String userName = 'Unknown User';
      String userPhone = '';
      String userAddress = '';
      
      if (emergencyData['userAddress'] != null) {
        userAddress = emergencyData['userAddress'].toString();
      }
      
      if (userId.isNotEmpty) {
        final userSnapshot = await usersRef!.child(userId).get();
        if (userSnapshot.value != null) {
          final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
          userName = userData['UserName']?.toString() ?? 'Unknown User';
          userPhone = userData['Phone']?.toString() ?? '';
          
          if (userAddress == 'No Address' || userAddress.isEmpty) {
            String addressFromUser = userData['Address']?.toString() ?? '';
            if (addressFromUser.isEmpty) {
              addressFromUser = userData['address']?.toString() ?? '';
            }
            if (addressFromUser.isNotEmpty) {
              userAddress = addressFromUser;
            }
          }
        }
      }
      
      int sosTimeMs = 0;
      String sosTimeFormatted = 'Unknown';
      
      if (emergencyData['sosTime'] != null) {
        sosTimeMs = emergencyData['sosTime'] as int;
        final sosDateTime = DateTime.fromMillisecondsSinceEpoch(sosTimeMs);
        sosTimeFormatted = _formatDateTime(sosDateTime);
      }
      
      String responseTime = 'N/A';
      int responseTimeMs = 0;
      
      if (sosTimeMs > 0) {
        final now = DateTime.now();
        final completedAtMs = now.millisecondsSinceEpoch;
        responseTimeMs = completedAtMs - sosTimeMs;
        responseTime = _formatDuration(Duration(milliseconds: responseTimeMs));
      }
      
      User? currentUser = FirebaseAuth.instance.currentUser;
      String currentUserEmail = currentUser?.email ?? '';
      String currentUserUid = currentUser?.uid ?? '';
      
      final completedData = {
        'emergencyKey': emergencyKey,
        'emergencyData': emergencyData,
        'completedBy': {
          'uid': currentUserUid,
          'name': responderName,
          'email': currentUserEmail,
          'type': responderType,
        },
        'userInfo': {
          'uid': userId,
          'name': userName,
          'phone': userPhone,
          'address': userAddress,
          'timestamp': ServerValue.timestamp,
        },
        'completedAt': DateTime.now().toIso8601String(),
        'timestamp': ServerValue.timestamp,
        'distance': getDistance(emergencyData),
        'status': 'completed',
        'sosTime': sosTimeMs,
        'sosTimeFormatted': sosTimeFormatted,
        'responseTime': responseTime,
        'responseTimeMs': responseTimeMs,
      };
      
      await sosDoneRef!.child(emergencyKey).set(completedData);
      await assignedRef!.child(emergencyKey).remove();
      
      if (userId.isNotEmpty) {
        await FirebaseDatabase.instance
            .ref('Users')
            .child(userId)
            .child('activeEmergency')
            .remove();
      }
      
      await setResponderActiveAfterEmergency();
      
      _cachedEmergencyData = null;
      _cachedEmergencyKey = null;
      
      _showPremiumCompleteSnackbar(
        emergencyKey: emergencyKey,
        emergencyData: emergencyData,
        completedData: completedData,
      );
      
      return true;
    } catch (e) {
      _showPremiumErrorSnackbar('Failed to complete emergency');
      return false;
    }
  }

  // ============================================================
  // PREMIUM COMPLETE SNACKBAR (NO CLOSE BUTTON)
  // ============================================================
  void _showPremiumCompleteSnackbar({
    required String emergencyKey,
    required Map emergencyData,
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
                await _undoCompleteEmergency(emergencyKey, emergencyData, completedData);
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

  // ============================================================
  // ERROR SNACKBAR (NO CLOSE BUTTON)
  // ============================================================
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
  // UNDO COMPLETE EMERGENCY
  // ============================================================
  Future<bool> _undoCompleteEmergency(
    String emergencyKey, 
    Map emergencyData,
    Map completedData,
  ) async {
    try {
      if (sosDoneRef == null || assignedRef == null || myResponderRef == null) {
        _showPremiumErrorSnackbar('Database not initialized');
        return false;
      }
      
      await sosDoneRef!.child(emergencyKey).remove();
      await assignedRef!.child(emergencyKey).set(emergencyData);
      
      await myResponderRef!.update({
        'status': 'busy',
        'currentEmergencyId': emergencyKey,
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
  // CONTACT VERIFICATION DIALOG
  // ============================================================
  Future<bool?> _showContactVerificationDialog(Map emergencyData) async {
    String userName = emergencyData['userID']?.toString() ?? 'the user';
    
    final userId = emergencyData['userID']?.toString() ?? '';
    if (userId.isNotEmpty && _userCache.containsKey(userId)) {
      userName = _userCache[userId]?['name'] ?? userName;
    }
    
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
                  Icons.contact_support_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Contact Verification',
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
                    const TextSpan(text: 'Have you successfully made contact with "'),
                    TextSpan(
                      text: userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F4C5C),
                        fontSize: 16,
                      ),
                    ),
                    const TextSpan(text: '" and provided assistance?'),
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
                        'This confirms you have physically or virtually connected with the person in need.',
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
    final responderId = user?.uid ?? '';
    if (responderId.isEmpty) {
      Get.snackbar(
        'Error',
        'Unable to load completed emergencies',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      return;
    }
    
    Get.to(() => CompletedEmergenciesPage(
          responderId: responderId,
        ));
  }

  // ============================================================
  // BUILD HOME CONTENT
  // ============================================================
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
                        await _saveSwitchValue(value);
                        if (!mounted) return;
                        setState(() {
                          _switchValue = value;
                          status = value ? 'Active' : 'Inactive';
                        });
                        if (value) {
                          await _setResponderActive();
                        } else {
                          await _setResponderInactive();
                          if (mounted) {
                            setState(() {});
                          }
                        }
                        await _verifyToggleState();
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
                              'No active emergencies assigned',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _navigateToCompleted,
                              icon: const Icon(Icons.history),
                              label: const Text('View History'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF0F4C5C),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final rawData = snapshot.data!.snapshot.value;
                    if (rawData == null) {
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
                              'No active emergencies assigned',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _navigateToCompleted,
                              icon: const Icon(Icons.history),
                              label: const Text('View History'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF0F4C5C),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final data = Map<dynamic, dynamic>.from(rawData as Map);
                    final List<MapEntry<dynamic, dynamic>> entries = data.entries.toList();
                    
                    entries.sort((a, b) => b.key.toString().compareTo(a.key.toString()));

                    if (entries.isEmpty) {
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
                              'No active emergencies assigned',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _navigateToCompleted,
                              icon: const Icon(Icons.history),
                              label: const Text('View'),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF0F4C5C),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final userIds = entries
                        .map((e) => e.value['userID']?.toString() ?? '')
                        .where((id) => id.isNotEmpty)
                        .toList();

                    if (userIds.isEmpty) {
                      return _buildEmergencyList(entries, {});
                    }

                    return FutureBuilder<Map<String, Map<String, String>>>(
                      future: _fetchAllUserDetails(userIds),
                      builder: (context, userDataSnapshot) {
                        if (userDataSnapshot.connectionState == ConnectionState.waiting && 
                            _userCache.isEmpty) {
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
                                  'Loading emergencies...',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final userData = userDataSnapshot.data ?? _userCache;
                        return _buildEmergencyList(entries, userData);
                      },
                    );
                  },
                )
                : Center(
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
                          'No active emergencies assigned',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
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
              'Swipe right on an emergency to mark it as completed after making contact',
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

  Widget _buildEmergencyList(
    List<MapEntry<dynamic, dynamic>> entries,
    Map<String, Map<String, String>> userData,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final emergencyKey = entry.key;
        final Map list = Map<dynamic, dynamic>.from(entry.value);
        
        String emergencyTime = list['time']?.toString() ?? '';

        if (emergencyTime.isEmpty && list['assignedAt'] != null) {
          try {
            final timestamp = list['assignedAt'];
            if (timestamp is int) {
              final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
              emergencyTime = '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')} ${dateTime.day}/${dateTime.month}/${dateTime.year}';
            }
          } catch (e) {
            emergencyTime = 'Unknown time';
          }
        }

        if (emergencyTime.isEmpty) {
          emergencyTime = 'Unknown time';
        }
        
        String userAddress = list['userAddress']?.toString() ?? 'No Address';
        
        final userId = list['userID']?.toString() ?? '';
        
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

        final bool isProcessing = _processingEmergencyKey == emergencyKey || _isProcessing;

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          child: Dismissible(
            key: Key(emergencyKey),
            direction: DismissDirection.startToEnd,
            
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                if (isProcessing) {
                  return false;
                }
                
                bool? confirmed = await _showContactVerificationDialog(list);
                
                if (confirmed == true) {
                  _isProcessing = true;
                  _processingEmergencyKey = emergencyKey;
                  
                  final String key = emergencyKey;
                  final Map data = Map.from(list);
                  
                  bool success = await _markEmergencyAsDone(key, data);
                  
                  _isProcessing = false;
                  _processingEmergencyKey = null;
                  
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
                        'Swipe to complete this emergency',
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
    _cachedEmergencyData = list;
    _cachedEmergencyKey = emergencyKey;
    
    Get.to(() => EmergencyDetailPage(
          emergencyData: list,
          emergencyKey: emergencyKey,
          userName: userName,
          userPhone: userPhone,
          emergencyTime: emergencyTime,
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
                // Address with icon
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white70,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        userAddress.isNotEmpty ? userAddress : 'No Address',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Time + Distance
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      color: Colors.white70,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      emergencyTime,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: Colors.white30,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.straighten,
                      color: Colors.white70,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      getDistance(list),
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
          // Status Badge - GREEN (same as doctor)
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
          const ResponderAccountPage(),
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