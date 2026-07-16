import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import 'package:public_emergency_app/Services/zego_service.dart';
import 'package:public_emergency_app/Features/User/Screens/VoicenVideoCall/keys.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';

class CallController extends GetxController {
  static CallController get to => Get.find<CallController>();
  
  final RxBool isCallInProgress = false.obs;
  final RxBool isCallIncoming = false.obs;
  final RxString incomingCallerName = ''.obs;
  final RxString incomingCallerID = ''.obs;
  final RxString incomingCallID = ''.obs;
  final RxString incomingCallerType = ''.obs; // 'user', 'responder', 'doctor'
  
  final ZegoService _zegoService = ZegoService();
  
  bool _isZegoReady = false;
  bool _isInitializing = false;
  Completer<void>? _zegoReadyCompleter;
  
  String? _currentUserID;
  String? _currentUserName;
  String? _currentUserType;

  @override
  void onInit() {
    super.onInit();
    _setupCallbacks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoInitialize();
    });
  }

  @override
  void onClose() {
    super.onClose();
  }
  
  void _setupCallbacks() {
    _zegoService.onCallAccepted = (callID, callerID, callerName) {
      print("✅ Call accepted: $callerName");
      isCallInProgress.value = true;
      isCallIncoming.value = false;
    };
    
    _zegoService.onCallRejected = (callID, callerID) {
      print("❌ Call rejected");
      isCallInProgress.value = false;
      isCallIncoming.value = false;
      incomingCallerName.value = '';
      incomingCallerID.value = '';
      incomingCallID.value = '';
      incomingCallerType.value = '';
    };
  }
  
  // ✅ FIXED: Get username directly from database with correct field name and proper prefix
  Future<Map<String, String>> _getUserIdentity() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("⚠️ No Firebase user found");
      return {'id': '', 'name': '', 'type': ''};
    }
    
    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref('Users');
      final snapshot = await ref.child(user.uid).get();
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        print("🔍 Database data: $data");
        
        // ✅ Try 'userName' first (lowercase u - matches your database)
        // Then fallback to 'UserName' (capital U)
        String name = data['userName']?.toString() ?? 
                      data['UserName']?.toString() ?? 
                      'User';
                      
        String type = data['userType']?.toString() ?? 
                      data['UserType']?.toString() ?? 
                      'User';
        
        // ✅ Add "Dr." prefix for Doctor users
        if (type.toLowerCase() == 'doctor' && !name.startsWith('Dr.') && !name.startsWith('Dr ')) {
          name = 'Dr. $name';
        }
        
        print("✅ Found name: '$name', type: '$type'");
        
        // ✅ Update local variables with correct name
        _currentUserName = name;
        _currentUserType = type;
        _currentUserID = user.uid;
        
        // ✅ Also update Keys
        Keys.setUserInfo(user.uid, name);
        
        return {'id': user.uid, 'name': name, 'type': type};
      } else {
        print("⚠️ No data found for user ${user.uid}");
        // Check if Keys has a username
        if (Keys.userName.isNotEmpty && Keys.userName != 'User') {
          String name = Keys.userName;
          String type = Keys.responderType.isNotEmpty ? Keys.responderType : 'User';
          
          // ✅ Add "Dr." prefix for Doctor users
          if (type.toLowerCase() == 'doctor' && !name.startsWith('Dr.') && !name.startsWith('Dr ')) {
            name = 'Dr. $name';
          }
          
          print("✅ Using username from Keys: $name");
          return {'id': user.uid, 'name': name, 'type': type};
        }
        return {'id': user.uid, 'name': 'User', 'type': 'User'};
      }
    } catch (e) {
      print("❌ Error fetching user: $e");
      // Check if Keys has a username as fallback
      if (Keys.userName.isNotEmpty && Keys.userName != 'User') {
        String name = Keys.userName;
        String type = Keys.responderType.isNotEmpty ? Keys.responderType : 'User';
        
        // ✅ Add "Dr." prefix for Doctor users
        if (type.toLowerCase() == 'doctor' && !name.startsWith('Dr.') && !name.startsWith('Dr ')) {
          name = 'Dr. $name';
        }
        
        print("✅ Using username from Keys: $name");
        return {'id': user.uid, 'name': name, 'type': type};
      }
      return {'id': user.uid, 'name': 'User', 'type': 'User'};
    }
  }

  void _autoInitialize() async {
    final identity = await _getUserIdentity();
    if (identity['id']!.isNotEmpty) {
      _currentUserType = identity['type'];
      initializeZego(identity['id']!, identity['name']!);
    }
  }

  void initializeZegoFromAuth() async {
    final identity = await _getUserIdentity();
    if (identity['id']!.isNotEmpty) {
      _currentUserType = identity['type'];
      initializeZego(identity['id']!, identity['name']!);
    }
  }
  
  void _restoreUserIdentity() async {
    final identity = await _getUserIdentity();
    if (identity['id']!.isNotEmpty) {
      _currentUserID = identity['id'];
      _currentUserName = identity['name'];
      _currentUserType = identity['type'];
      Keys.setCurrentUser(identity['id']!, identity['name']!);
      print("🔄 Restored user identity: $_currentUserName (${_currentUserType})");
    }
  }
  
  // ✅ BEST SOLUTION: Properly reinitialize ZEGO with cleanup
  Future<void> _reinitializeZegoForNewCall(String userID, String userName) async {
    print("🔄 REINITIALIZING ZEGO for new call");
    
    try {
      // 1. Uninitialize the service completely to clear stale state
      print("📤 Uninitializing ZEGO service...");
      ZegoUIKitPrebuiltCallInvitationService().uninit();
      
      // 2. Reset local state
      _isZegoReady = false;
      _isInitializing = false;
      isCallInProgress.value = false;
      
      // 3. Reset the service
      await _zegoService.resetState();
      
      // 4. Wait for cleanup
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 5. Reinitialize fresh
      print("🟢 Initializing ZEGO fresh for: $userName ($userID)");
      await _zegoService.initialize(
        userID: userID,
        userName: userName,
      );
      
      // 6. Setup event handlers
      _setupInvitationEventHandlers();
      
      // 7. Mark as ready
      _isZegoReady = true;
      
      print("✅ ZEGO reinitialized successfully for new call");
      
    } catch (e) {
      print("❌ ZEGO reinitialization failed: $e");
      _isZegoReady = false;
      _isInitializing = false;
      rethrow;
    }
  }
  
  // ✅ FIXED: Initialize ZEGO with correct username
  Future<void> initializeZego(String userID, String userName) async {
    print("🔵 initializeZego called for: $userName ($userID)");
    
    // ✅ If username is empty or 'User', fetch from database
    if (userName.isEmpty || userName == 'User') {
      print("⚠️ Username is '$userName', fetching from database...");
      final identity = await _getUserIdentity();
      if (identity['name']!.isNotEmpty && identity['name'] != 'User') {
        userName = identity['name']!;
        userID = identity['id']!;
        print("✅ Retrieved name from database: $userName");
      }
    }
    
    _currentUserID = userID;
    _currentUserName = userName;
    Keys.setCurrentUser(userID, userName);
    
    if (_isZegoReady && _zegoService.isInitialized) {
      print("✅ ZEGO already ready");
      return;
    }
    
    if (_isInitializing) {
      print("⏳ ZEGO already initializing, waiting...");
      await _zegoReadyCompleter?.future;
      return;
    }
    
    _isInitializing = true;
    _zegoReadyCompleter = Completer<void>();
    
    try {
      String finalUserName = userName.trim();
      if (finalUserName.isEmpty) {
        finalUserName = 'User';
      }
      
      print("🟢 Initializing ZEGO with LOCAL user: $finalUserName");
      await _zegoService.initialize(
        userID: userID,
        userName: finalUserName,
      );
      
      _setupInvitationEventHandlers();
      
      _isZegoReady = true;
      if (_zegoReadyCompleter != null && !_zegoReadyCompleter!.isCompleted) {
        _zegoReadyCompleter!.complete();
      }
      print("✅ ZEGO initialized successfully with name: $finalUserName");
      
    } catch (e) {
      print("❌ ZEGO initialization failed: $e");
      _isZegoReady = false;
      if (_zegoReadyCompleter != null && !_zegoReadyCompleter!.isCompleted) {
        _zegoReadyCompleter!.completeError(e);
      }
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }
  
  void _setupInvitationEventHandlers() {
    try {
      print("📞 Setting up invitation event handlers");
      
      _zegoService.onIncomingCall = (callID, callerID, callerName) {
        print("📞 Incoming call from: $callerName");
        _onIncomingCallReceived(callerName, callerID, callID);
      };
      
    } catch (e) {
      print("⚠️ Could not set up invitation event handlers: $e");
    }
  }
  
  Future<void> waitForZegoReady() async {
    print("⏳ Waiting for ZEGO to be ready...");
    
    if (_isZegoReady && _zegoService.isInitialized) {
      print("✅ ZEGO is already ready");
      return;
    }
    
    if (_isInitializing && _zegoReadyCompleter != null) {
      try {
        print("⏳ Waiting for initialization to complete...");
        await _zegoReadyCompleter!.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            print("⚠️ ZEGO wait timeout, proceeding anyway");
            _isZegoReady = true;
            return;
          },
        );
        print("✅ ZEGO initialization completed");
      } catch (e) {
        print("❌ ZEGO initialization failed: $e");
        _isZegoReady = false;
      }
      return;
    }
    
    final identity = await _getUserIdentity();
    if (identity['id']!.isNotEmpty) {
      print("🔄 Initializing ZEGO during wait...");
      _currentUserType = identity['type'];
      await initializeZego(identity['id']!, identity['name']!);
    }
  }
  
  /// Send invitation with proper names - ✅ BEST SOLUTION IMPLEMENTED
  Future<void> sendInvitation({
    required String calleeID,
    required String calleeName,
    required String callID,
    required String inviterID,
    required String inviterName,
    required bool isInviterHost,
    Map<String, dynamic>? customData,
  }) async {
    print("========================================");
    print("📤 SENDING INVITATION");
    print("   LOCAL USER (Caller): $inviterName ($inviterID)");
    print("   REMOTE USER (Callee): $calleeName ($calleeID)");
    print("   Call ID: $callID");
    print("========================================");
    
    if (inviterName == calleeName && inviterID != calleeID) {
      print("⚠️⚠️⚠️ ERROR: inviterName and calleeName are the SAME!");
      print("   inviterName: '$inviterName'");
      print("   calleeName: '$calleeName'");
    }
    
    try {
      // ✅ BEST SOLUTION: Always reinitialize for new call
      // This ensures fresh SDK state and prevents the "second call fails" issue
      print("🔄 Ensuring fresh ZEGO state for new call...");
      
      // Get fresh user identity
      final identity = await _getUserIdentity();
      String freshUserName = identity['name'] ?? inviterName;
      String freshUserID = identity['id'] ?? inviterID;
      
      // ✅ Use the reinitialize method which properly cleans up and reinitializes
      await _reinitializeZegoForNewCall(freshUserID, freshUserName);
      
      // Update current user info
      _currentUserID = freshUserID;
      _currentUserName = freshUserName;
      Keys.setCurrentUser(freshUserID, freshUserName);
      
      print("✅ ZEGO ready for new call with user: $freshUserName");
      
    } catch (e) {
      print("❌ Failed to initialize ZEGO for new call: $e");
      Get.snackbar(
        'Error',
        'Call service is not available. Please try again.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      return;
    }
    
    isCallInProgress.value = true;
    print("📞 Sending invitation to ZEGO...");
    
    final bool result = await _zegoService.sendInvitation(
      calleeID: calleeID,
      calleeName: calleeName,
      callID: callID,
      inviterID: inviterID,
      inviterName: inviterName,
      isInviterHost: isInviterHost,
      customData: customData,
    );
    
    if (!result) {
      print("❌ Invitation failed!");
      isCallInProgress.value = false;
      Get.snackbar(
        'Error',
        'Could not send invitation. Please try again.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    } else {
      print("✅ Invitation sent successfully to: $calleeName");
    }
  }
  
  void _onIncomingCallReceived(String callerName, String callerID, String callID) {
    print("📞 Incoming call from: $callerName");
    isCallIncoming.value = true;
    incomingCallerName.value = callerName;
    incomingCallerID.value = callerID;
    incomingCallID.value = callID;
    
    // Fetch caller type from database
    _fetchCallerType(callerID);
  }
  
  Future<void> _fetchCallerType(String callerID) async {
    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref('Users');
      final snapshot = await ref.child(callerID).get();
      
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        // ✅ Try both cases
        String type = data['userType']?.toString() ?? 
                      data['UserType']?.toString() ?? 
                      'User';
        incomingCallerType.value = type;
        print("📞 Caller type: $type");
      }
    } catch (e) {
      print("⚠️ Could not fetch caller type: $e");
      incomingCallerType.value = 'User';
    }
  }
  
  void onIncomingCallReceived(String callerName, String callerID, String callID) {
    print("📞 Incoming call received: $callerName");
    isCallIncoming.value = true;
    incomingCallerName.value = callerName;
    incomingCallerID.value = callerID;
    incomingCallID.value = callID;
    _fetchCallerType(callerID);
  }
  
  void acceptCall() {
    print("✅ Accepting call from: ${incomingCallerName.value} (${incomingCallerType.value})");
    if (incomingCallID.value.isNotEmpty) {
      isCallIncoming.value = false;
    }
  }
  
  void rejectCall() {
    print("❌ Rejecting call from: ${incomingCallerName.value}");
    isCallIncoming.value = false;
    incomingCallerName.value = '';
    incomingCallerID.value = '';
    incomingCallID.value = '';
    incomingCallerType.value = '';
  }
  
  void endCall() {
    print("🔚 Ending call");
    try {
      // ✅ Properly uninitialize the service
      ZegoUIKitPrebuiltCallInvitationService().uninit();
      _zegoService.resetState();
      _isZegoReady = false;
      _isInitializing = false;
    } catch (e) {
      print("❌ Error ending call: $e");
      _isZegoReady = false;
      _isInitializing = false;
    }
    
    // Reset all state
    isCallInProgress.value = false;
    isCallIncoming.value = false;
    incomingCallerName.value = '';
    incomingCallerID.value = '';
    incomingCallID.value = '';
    incomingCallerType.value = '';
    
    _restoreUserIdentity();
  }
  
  void resetForNewCall() {
    print("🔄 Resetting for new call");
    try {
      // ✅ Properly uninitialize the service
      ZegoUIKitPrebuiltCallInvitationService().uninit();
      _zegoService.resetState();
      _isZegoReady = false;
      _isInitializing = false;
    } catch (e) {
      print("❌ Error resetting: $e");
      _isZegoReady = false;
      _isInitializing = false;
    }
    
    // Reset all state
    isCallInProgress.value = false;
    isCallIncoming.value = false;
    incomingCallerName.value = '';
    incomingCallerID.value = '';
    incomingCallID.value = '';
    incomingCallerType.value = '';
    
    _restoreUserIdentity();
  }
  
  void uninitializeZego() {
    print("🔄 Uninitializing ZEGO");
    try {
      ZegoUIKitPrebuiltCallInvitationService().uninit();
      _zegoService.uninitialize();
      _isZegoReady = false;
      _isInitializing = false;
      isCallInProgress.value = false;
      isCallIncoming.value = false;
      _currentUserID = null;
      _currentUserName = null;
      _currentUserType = null;
    } catch (e) {
      _isZegoReady = false;
    }
  }
  
  bool get isInCall => isCallInProgress.value || isCallIncoming.value;
  
  bool get isZegoReady => _isZegoReady && _zegoService.isInitialized;
  
  // Helper method to get display name with type
  String getCallerDisplayName(String name, String type) {
    if (type == 'Responder') {
      return 'Responder $name';
    } else if (type == 'Doctor') {
      return 'Dr. $name';
    }
    return name;
  }
  
  // Get current user's display name with type
  String getCurrentUserDisplayName() {
    if (_currentUserType == 'Responder') {
      return 'Responder $_currentUserName';
    } else if (_currentUserType == 'Doctor') {
      return 'Dr. $_currentUserName';
    }
    return _currentUserName ?? 'User';
  }
  
  // ✅ Force update username (optional - can be called from any page if needed)
  void forceUpdateUsername(String name) {
    if (name.isNotEmpty && name != 'User' && name != 'user') {
      print("✅ Forcing username update to: $name");
      _currentUserName = name;
      if (_currentUserID != null) {
        Keys.setUserInfo(_currentUserID!, name);
      }
    }
  }
}