import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class EmergencyAssignmentService extends GetxService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  // Track active timers for each emergency
  final Map<String, Timer> _validationTimers = {};
  final Map<String, Timer> _statusCheckTimers = {};
  
  // Callbacks
  Function(String emergencyId)? onEmergencyCancelled;
  Function(String emergencyId)? onEmergencyCompleted;
  
  /// Start validating an emergency assignment
  void startAssignmentValidation({
    required String emergencyId,
    required String responderId,
    required String userId,
    VoidCallback? onResponderOffline,
    VoidCallback? onEmergencyCompleted,
  }) {
    // Stop any existing validation for this emergency
    stopAssignmentValidation(emergencyId);
    
    print("🟢 Starting assignment validation for emergency: $emergencyId");
    
    // Timer to check responder online status every 10 seconds
    final validationTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) async {
        await _validateResponderStatus(
          emergencyId: emergencyId,
          responderId: responderId,
          userId: userId,
          onResponderOffline: onResponderOffline,
        );
      },
    );
    
    _validationTimers[emergencyId] = validationTimer;
    
    // Timer to check for completion status every 5 seconds
    final statusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) async {
        await _checkEmergencyStatus(
          emergencyId: emergencyId,
          onEmergencyCompleted: onEmergencyCompleted,
        );
      },
    );
    
    _statusCheckTimers[emergencyId] = statusTimer;
  }
  
  /// Stop validating an emergency
  void stopAssignmentValidation(String emergencyId) {
    _validationTimers[emergencyId]?.cancel();
    _validationTimers.remove(emergencyId);
    
    _statusCheckTimers[emergencyId]?.cancel();
    _statusCheckTimers.remove(emergencyId);
    
    print("🛑 Stopped validation for emergency: $emergencyId");
  }
  
  /// Validate if responder is still online
  Future<void> _validateResponderStatus({
    required String emergencyId,
    required String responderId,
    required String userId,
    VoidCallback? onResponderOffline,
  }) async {
    try {
      // Check if responder exists in database
      final responderSnapshot = await _database
          .child('Responders')
          .child(responderId)
          .get();
      
      if (!responderSnapshot.exists) {
        // Responder doesn't exist - remove assignment
        await _removeStaleEmergency(
          emergencyId: emergencyId,
          responderId: responderId,
          userId: userId,
        );
        
        if (onResponderOffline != null) {
          onResponderOffline();
        }
        return;
      }
      
      // 🔥 FIX: Check responder's status and online state more carefully
      final responderData = Map<String, dynamic>.from(responderSnapshot.value as Map);
      final status = responderData['status']?.toString() ?? '';
      final isActive = responderData['isActive'] ?? false;
      final isOnline = responderData['isOnline'] ?? false;
      final currentEmergencyId = responderData['currentEmergencyId']?.toString() ?? '';
      final lastActive = responderData['lastActive'];
      
      // 🔥 CRITICAL FIX: Don't delete if responder is busy with THIS emergency
      if (status == 'busy' && currentEmergencyId == emergencyId) {
        print("🟢 Responder is busy with this emergency - keeping it");
        return;
      }
      
      // 🔥 CRITICAL FIX: Don't delete if responder is active
      if (status == 'active' || status == 'Active') {
        print("🟢 Responder is active - keeping emergency");
        return;
      }
      
      // Check last active time
      if (lastActive != null) {
        final lastActiveTime = DateTime.fromMillisecondsSinceEpoch(lastActive as int);
        final isRecentlyOnline = DateTime.now().difference(lastActiveTime).inSeconds < 30;
        
        // 🔥 FIX: Only delete if truly offline AND not in a call
        if (!isRecentlyOnline && currentEmergencyId != emergencyId) {
          print("⚠️ Responder $responderId is offline (last active: ${lastActiveTime.difference(DateTime.now()).inSeconds.abs()}s ago)");
          
          // Check if emergency is still in 'assigned' node
          final assignedSnapshot = await _database
              .child('assigned')
              .child(responderId)
              .child(emergencyId)
              .get();
          
          if (assignedSnapshot.exists) {
            await _removeStaleEmergency(
              emergencyId: emergencyId,
              responderId: responderId,
              userId: userId,
            );
            
            if (onResponderOffline != null) {
              onResponderOffline();
            }
          }
        }
      }
      
    } catch (e) {
      print("❌ Error validating responder status: $e");
    }
  }
  
  /// Check if emergency has been completed
  Future<void> _checkEmergencyStatus({
    required String emergencyId,
    VoidCallback? onEmergencyCompleted,
  }) async {
    try {
      // Search for the emergency in assigned node
      final assignedSnapshot = await _database
          .child('assigned')
          .get();
      
      if (assignedSnapshot.value == null) return;
      
      final data = Map<String, dynamic>.from(assignedSnapshot.value as Map);
      
      for (var responderId in data.keys) {
        final emergencies = Map<String, dynamic>.from(data[responderId] as Map);
        
        if (emergencies.containsKey(emergencyId)) {
          final emergency = Map<String, dynamic>.from(emergencies[emergencyId]);
          final status = emergency['status']?.toString() ?? '';
          
          if (status == 'completed' || status == 'cancelled') {
            print("✅ Emergency $emergencyId is $status");
            
            // Stop validation timers
            stopAssignmentValidation(emergencyId);
            
            if (onEmergencyCompleted != null) {
              onEmergencyCompleted();
            }
            break;
          }
        }
      }
      
    } catch (e) {
      print("❌ Error checking emergency status: $e");
    }
  }
  
  /// Remove stale emergency assignment
  Future<void> _removeStaleEmergency({
    required String emergencyId,
    required String responderId,
    required String userId,
  }) async {
    try {
      print("🗑️ Removing stale emergency: $emergencyId");
      
      // Get the emergency data before removing
      final emergencySnapshot = await _database
          .child('assigned')
          .child(responderId)
          .child(emergencyId)
          .get();
      
      if (!emergencySnapshot.exists) return;
      
      final emergencyData = emergencySnapshot.value as Map;
      
      // Remove from assigned
      await _database
          .child('assigned')
          .child(responderId)
          .child(emergencyId)
          .remove();
      
      // Remove from user's active emergency
      await _database
          .child('Users')
          .child(userId)
          .child('activeEmergency')
          .remove();
      
      print("✅ Stale emergency removed successfully");
      
    } catch (e) {
      print("❌ Error removing stale emergency: $e");
    }
  }
  
  /// Check if responder is online
  Future<bool> isResponderOnline(String responderId) async {
    try {
      final snapshot = await _database
          .child('Responders')
          .child(responderId)
          .get();
      
      if (!snapshot.exists) return false;
      
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final status = data['status']?.toString() ?? '';
      final isActive = data['isActive'] ?? false;
      final isOnline = data['isOnline'] ?? false;
      final lastActive = data['lastActive'];
      
      // 🔥 FIX: Check if responder is busy
      if (status == 'busy') {
        return true;
      }
      
      // Check active/online status
      if (isActive && isOnline) {
        return true;
      }
      
      // Check last active time
      if (lastActive != null) {
        final lastActiveTime = DateTime.fromMillisecondsSinceEpoch(lastActive as int);
        return DateTime.now().difference(lastActiveTime).inSeconds < 30;
      }
      
      return false;
      
    } catch (e) {
      return false;
    }
  }
  
  @override
  void onClose() {
    // Cancel all timers when service is disposed
    for (var timer in _validationTimers.values) {
      timer.cancel();
    }
    _validationTimers.clear();
    
    for (var timer in _statusCheckTimers.values) {
      timer.cancel();
    }
    _statusCheckTimers.clear();
    
    super.onClose();
  }
}