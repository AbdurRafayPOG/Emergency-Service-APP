import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';
import '../Features/User/Screens/VoicenVideoCall/keys.dart';

class ZegoService {
  static final ZegoService _instance = ZegoService._internal();
  factory ZegoService() => _instance;
  ZegoService._internal();

  bool _isInitialized = false;
  bool _isInitializing = false;
  
  Function(String callID, String? callerID, String? callerName)? onCallAccepted;
  Function(String callID, String? callerID)? onCallRejected;
  Function(String callID, String callerID, String callerName)? onIncomingCall;

  Future<void> initialize({
    required String userID, 
    required String userName,
  }) async {
    if (_isInitialized) {
      print("✅ ZEGO already initialized for: $userName");
      return;
    }
    
    if (_isInitializing) {
      print("⏳ ZEGO is already initializing, waiting...");
      int retries = 0;
      while (_isInitializing && retries < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        retries++;
      }
      if (_isInitialized) {
        print("✅ ZEGO initialization completed while waiting");
        return;
      }
      print("⚠️ ZEGO initialization stuck, trying fresh init...");
    }

    _isInitializing = true;
    print("========================================");
    print("🔄 INITIALIZING ZEGO SERVICE");
    print("   LOCAL USER ID: $userID");
    print("   LOCAL USER NAME: $userName");
    print("========================================");
    
    try {
      Keys.setUserInfo(userID, userName);
      
      print("🟢 Calling ZegoUIKitPrebuiltCallInvitationService().init()...");
      
      ZegoUIKitPrebuiltCallInvitationService().init(
        appID: Keys.appId,
        appSign: Keys.appSign,
        userID: userID,
        userName: userName,  // 👈 LOCAL user's name
        plugins: [ZegoUIKitSignalingPlugin()],
      );
      
      _setupInvitationServiceHandlers();
      
      print("⏳ Waiting 2 seconds for ZEGO signaling to connect...");
      await Future.delayed(const Duration(seconds: 2));
      
      _isInitialized = true;
      print("✅ ZEGO initialized successfully");
      print("📱 LOCAL USER NAME SET: $userName");
      print("========================================");
      
    } catch (e) {
      print("❌ ZEGO initialization failed: $e");
      _isInitialized = false;
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  void _setupInvitationServiceHandlers() {
    try {
      print("📞 ZEGO invitation service handlers are ready");
    } catch (e) {
      print("⚠️ Could not set up invitation service handlers: $e");
    }
  }

  Future<void> resetState() async {
    print("🔄 Resetting ZEGO state...");
    
    try {
      String userId = Keys.currentUserId.isNotEmpty ? Keys.currentUserId : Keys.userId;
      String userName = Keys.currentUserName.isNotEmpty ? Keys.currentUserName : Keys.userName;
      
      if (userId.isEmpty || userName.isEmpty) {
        print("⚠️ No user info found, skipping reset");
        return;
      }
      
      print("📱 Resetting for user: $userName ($userId)");
      
      _isInitialized = false;
      _isInitializing = false;
      
      try {
        ZegoUIKitPrebuiltCallInvitationService().uninit();
        print("✅ ZEGO uninitialized for reset");
      } catch (e) {
        print("⚠️ Error during uninit: $e");
      }
      
      await Future.delayed(const Duration(milliseconds: 500));
      await initialize(userID: userId, userName: userName);
      
      print("✅ ZEGO reset successfully");
    } catch (e) {
      print("❌ Failed to reset ZEGO state: $e");
      _isInitialized = false;
    }
  }

  Future<bool> sendInvitation({
    required String calleeID,
    required String calleeName,    // 👈 REMOTE user's name
    required String callID,
    required String inviterID,
    required String inviterName,   // 👈 LOCAL user's name
    required bool isInviterHost,
    Map<String, dynamic>? customData,
  }) async {
    print("========================================");
    print("📤 ZEGO: SENDING INVITATION");
    print("   LOCAL USER (Caller): $inviterName ($inviterID)");
    print("   REMOTE USER (Callee): $calleeName ($calleeID)");
    print("========================================");
    
    // ✅ Validate names are different
    if (inviterName == calleeName && inviterID != calleeID) {
      print("⚠️⚠️⚠️ ERROR: inviterName == calleeName!");
      print("   This will cause double username on call screen!");
      print("   inviterName: '$inviterName'");
      print("   calleeName: '$calleeName'");
    }
    
    if (!_isInitialized) {
      print("⚠️ ZEGO not initialized! Auto-initializing...");
      try {
        await initialize(
          userID: Keys.userId.isNotEmpty ? Keys.userId : inviterID,
          userName: Keys.userName.isNotEmpty ? Keys.userName : inviterName,
        );
        print("✅ Auto-initialization completed");
      } catch (e) {
        print("❌ Auto-initialization failed: $e");
        Get.snackbar(
          'Error',
          'Call service is initializing. Please try again.',
          snackPosition: SnackPosition.TOP,
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
        return false;
      }
    }

    if (!_isInitialized) {
      print("❌ ZEGO not initialized!");
      Get.snackbar(
        'Error',
        'Call service not available.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      return false;
    }

    try {
      print("🟢 Sending invitation to ZEGO...");
      print("   Invitees: ${ZegoCallUser(calleeID, calleeName)}");
      
      final result = await ZegoUIKitPrebuiltCallInvitationService().send(
        invitees: [
          ZegoCallUser(calleeID, calleeName),  // 👈 REMOTE user's name
        ],
        isVideoCall: true,
        customData: customData?.toString() ?? '',
        callID: callID,
        timeoutSeconds: 30,
      );
      
      print("📤 ZEGO send() result: $result");
      
      if (!result) {
        print("❌ Invitation failed!");
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
      
      return result;
      
    } catch (e) {
      print("❌ ZEGO send() exception: $e");
      
      if (e.toString().contains("not initialized") || 
          e.toString().contains("init")) {
        _isInitialized = false;
      }
      
      Get.snackbar(
        'Error',
        'Failed to send call. Please try again.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      return false;
    }
  }

  bool get isInitialized => _isInitialized;

  void dispose() {
    print("🔄 Disposing ZegoService...");
  }

  Future<void> forceReinitialize({
    required String userID, 
    required String userName,
  }) async {
    print("🔄 Force reinitializing...");
    _isInitialized = false;
    _isInitializing = false;
    await initialize(userID: userID, userName: userName);
  }

  void uninitialize() {
    print("🔄 Uninitializing ZEGO...");
    try {
      ZegoUIKitPrebuiltCallInvitationService().uninit();
      _isInitialized = false;
      _isInitializing = false;
      print("✅ ZEGO uninitialized");
    } catch (e) {
      print("⚠️ Error uninitializing: $e");
      _isInitialized = false;
    }
  }
}