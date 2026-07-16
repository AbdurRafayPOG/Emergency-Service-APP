import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:public_emergency_app/Models/emergency_model.dart';

class SOSResult {
  final bool success;
  final String? emergencyId;
  final Map<String, dynamic>? responderData;
  final String? message;
  
  SOSResult({
    required this.success,
    this.emergencyId,
    this.responderData,
    this.message,
  });
}

class SOSService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // ============================================================
  // ✅ Create emergency - ONLY writes to 'assigned' node
  // ============================================================
  Future<SOSResult> createEmergency(Emergency emergency) async {
    try {
      debugPrint('🔵 [createEmergency] STARTING...');
      debugPrint('🔵 [createEmergency] Emergency Type: ${emergency.emergencyType}');
      debugPrint('🔵 [createEmergency] User ID: ${emergency.userId}');
      debugPrint('🔵 [createEmergency] User Lat: ${emergency.userLat}');
      debugPrint('🔵 [createEmergency] User Long: ${emergency.userLong}');
      debugPrint('🔵 [createEmergency] Created At: ${emergency.createdAt}');
      
      // 1. Find nearest available responder
      debugPrint('🔵 [createEmergency] Finding nearest responder...');
      final responderData = await _findNearestAvailableResponder(
        emergency.emergencyType,
        emergency.userLat,
        emergency.userLong,
      );
      
      if (responderData == null) {
        debugPrint('❌ [createEmergency] No responder found!');
        return SOSResult(
          success: false,
          message: 'No ${emergency.emergencyType} available right now',
        );
      }
      
      debugPrint('✅ [createEmergency] Responder found: ${responderData['UserName']}');
      debugPrint('✅ [createEmergency] Responder ID: ${responderData['uid']}');
      
      // 2. Get responder details
      final responderId = responderData['uid'];
      final responderName = responderData['UserName'] ?? 'Unknown Responder';
      final responderType = responderData['UserType'] ?? 'Responder';
      final responderPhone = responderData['Phone'] ?? '';
      
      // 3. Generate emergency ID
      debugPrint('🔵 [createEmergency] Generating emergency ID...');
      final emergencyRef = _database.child('assigned').child(responderId).push();
      final emergencyId = emergencyRef.key!;
      debugPrint('✅ [createEmergency] Emergency ID: $emergencyId');
      
      // 4. ✅ Write to 'assigned' node
      debugPrint('🔵 [createEmergency] Writing to Firebase...');
      
      final Map<String, dynamic> emergencyData = {
        'emergencyId': emergencyId,
        'userID': emergency.userId,
        'userEmail': emergency.userEmail,
        'userName': emergency.userName,
        'userLat': emergency.userLat,
        'userLong': emergency.userLong,
        'userAddress': emergency.address,
        'type': emergency.emergencyType,
        'responderId': responderId,
        'responderName': responderName,
        'responderType': responderType,
        'responderPhone': responderPhone,
        'responderLat': responderData['lat']?.toString() ?? '',
        'responderLong': responderData['long']?.toString() ?? '',
        'assignedAt': ServerValue.timestamp,
        'status': 'assigned',
        // ✅ SOS Time - When user clicked SOS
        'sosTime': ServerValue.timestamp,
      };
      
      debugPrint('📊 [createEmergency] Data being written:');
      debugPrint('   emergencyId: $emergencyId');
      debugPrint('   userID: ${emergencyData['userID']}');
      debugPrint('   responderId: ${emergencyData['responderId']}');
      debugPrint('   sosTime: ${emergencyData['sosTime']} (ServerValue.timestamp)');
      debugPrint('   assignedAt: ${emergencyData['assignedAt']} (ServerValue.timestamp)');
      
      await emergencyRef.set(emergencyData);
      debugPrint('✅ [createEmergency] Data written successfully to assigned/$responderId/$emergencyId');
      
      // 5. Update responder status to BUSY
      debugPrint('🔵 [createEmergency] Updating responder status to BUSY...');
      await _database
          .child('Responders')
          .child(responderId)
          .update({
        'status': 'busy',
        'currentEmergencyId': emergencyId,
        'lastAssignedAt': ServerValue.timestamp,
        'isActive': false,
      });
      debugPrint('✅ [createEmergency] Responder status updated to BUSY');
      
      // 6. ✅ Store active emergency for user
      debugPrint('🔵 [createEmergency] Storing active emergency for user...');
      await _database
          .child('Users')
          .child(emergency.userId)
          .child('activeEmergency')
          .set({
        'emergencyId': emergencyId,
        'responderId': responderId,
        'responderName': responderName,
        'responderPhone': responderPhone,
        'status': 'assigned',
        'type': emergency.emergencyType,
      });
      debugPrint('✅ [createEmergency] Active emergency stored for user');
      
      debugPrint('✅ [createEmergency] COMPLETED SUCCESSFULLY!');
      debugPrint('========================================');
      
      return SOSResult(
        success: true,
        emergencyId: emergencyId,
        responderData: responderData,
        message: '${responderType} assigned successfully',
      );
      
    } catch (e) {
      debugPrint('❌ [createEmergency] ERROR: $e');
      debugPrint('❌ [createEmergency] Stack trace: ${StackTrace.current}');
      return SOSResult(
        success: false,
        message: 'Failed to create emergency: $e',
      );
    }
  }

  // ============================================================
  // Find nearest available responder
  // ============================================================
  Future<Map<String, dynamic>?> _findNearestAvailableResponder(
    String emergencyType,
    double userLat,
    double userLong,
  ) async {
    try {
      debugPrint('🔍 [_findNearestAvailableResponder] Searching for $emergencyType responders...');
      
      final snapshot = await _database
          .child('Responders')
          .get();
      
      if (snapshot.value == null) {
        debugPrint('❌ [_findNearestAvailableResponder] No responders found');
        return null;
      }
      
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      debugPrint('📊 [_findNearestAvailableResponder] Found ${data.keys.length} responders total');
      
      final availableResponders = <Map<String, dynamic>>[];
      
      data.forEach((uid, responderData) {
        final responder = Map<String, dynamic>.from(responderData);
        
        // CASE-INSENSITIVE TYPE CHECK
        final userType = responder['UserType']?.toString() ?? '';
        final isTypeMatch = userType.toLowerCase() == emergencyType.toLowerCase();
        
        if (!isTypeMatch) {
          debugPrint('   ⏭️ Skipping $uid: Type mismatch ($userType != $emergencyType)');
          return;
        }
        
        // Check if responder is available
        final status = responder['status']?.toString() ?? '';
        final isActive = responder['isActive'] ?? false;
        final isAvailable = responder['isAvailable'] ?? false;
        final hasNoEmergency = responder['currentEmergencyId'] == null ||
            responder['currentEmergencyId'].toString().isEmpty;
        
        debugPrint('   🔍 Checking $uid: status=$status, isActive=$isActive, isAvailable=$isAvailable, hasNoEmergency=$hasNoEmergency');
        
        // Accept if: status is active OR (isActive AND isAvailable are true)
        final isActiveStatus = status == 'active' || 
            (isActive == true && isAvailable == true);
        
        if (isActiveStatus && hasNoEmergency) {
          responder['uid'] = uid;
          availableResponders.add(responder);
          debugPrint('   ✅ $uid is available!');
        } else {
          debugPrint('   ❌ $uid is NOT available');
        }
      });
      
      if (availableResponders.isEmpty) {
        debugPrint('❌ [_findNearestAvailableResponder] No active $emergencyType responders available');
        return null;
      }
      
      debugPrint('📊 [_findNearestAvailableResponder] Found ${availableResponders.length} available responders');
      
      // Calculate distance for each responder
      for (var responder in availableResponders) {
        final latStr = responder['lat']?.toString() ?? '';
        final longStr = responder['long']?.toString() ?? '';
        
        if (latStr.isEmpty || longStr.isEmpty) {
          responder['distance'] = double.infinity;
          continue;
        }
        
        final responderLat = double.tryParse(latStr) ?? 0;
        final responderLong = double.tryParse(longStr) ?? 0;
        
        if (responderLat == 0 && responderLong == 0) {
          responder['distance'] = double.infinity;
          continue;
        }
        
        final distance = _calculateDistance(
          userLat,
          userLong,
          responderLat,
          responderLong,
        );
        
        responder['distance'] = distance;
        debugPrint('   📍 ${responder['UserName']}: distance = ${distance.toStringAsFixed(2)} km');
      }
      
      // Remove responders without valid distance
      availableResponders.removeWhere((r) => 
          r['distance'] == null || r['distance'] == double.infinity);
      
      if (availableResponders.isEmpty) {
        debugPrint('❌ [_findNearestAvailableResponder] No available responders with valid location');
        return null;
      }
      
      // Sort by distance (nearest first)
      availableResponders.sort((a, b) {
        final aDist = a['distance'] ?? double.infinity;
        final bDist = b['distance'] ?? double.infinity;
        return aDist.compareTo(bDist);
      });
      
      final nearest = availableResponders.first;
      debugPrint('✅ [_findNearestAvailableResponder] Nearest responder: ${nearest['UserName']} (${nearest['distance'].toStringAsFixed(2)} km)');
      
      return nearest;
      
    } catch (e) {
      debugPrint('❌ [_findNearestAvailableResponder] Error: $e');
      return null;
    }
  }

  // ============================================================
  // Calculate distance using Haversine formula
  // ============================================================
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295;
    const double earthRadius = 12742; // Earth's radius in km
    
    double a = 0.5 - 
        (cos((lat2 - lat1) * p) / 2) + 
        (cos(lat1 * p) * cos(lat2 * p) * 
        (1 - cos((lon2 - lon1) * p)) / 2);
    
    return earthRadius * asin(sqrt(a));
  }

  // ============================================================
  // ✅ Get all emergencies for a responder
  // ============================================================
  Future<List<Map<String, dynamic>>> getResponderEmergencies(String responderId) async {
    try {
      final snapshot = await _database
          .child('assigned')
          .child(responderId)
          .get();
      
      if (snapshot.value == null) return [];
      
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final emergencies = <Map<String, dynamic>>[];
      
      data.forEach((emergencyId, emergencyData) {
        final emergency = Map<String, dynamic>.from(emergencyData);
        emergency['id'] = emergencyId;
        emergencies.add(emergency);
      });
      
      // Sort by assignedAt (newest first)
      emergencies.sort((a, b) {
        final aTime = a['assignedAt'] ?? 0;
        final bTime = b['assignedAt'] ?? 0;
        return bTime.compareTo(aTime);
      });
      
      return emergencies;
    } catch (e) {
      debugPrint('Error getting responder emergencies: $e');
      return [];
    }
  }

  // ============================================================
  // ✅ Cancel emergency
  // ============================================================
  Future<bool> cancelEmergency(String emergencyId, String userId, String responderId) async {
    try {
      // ✅ Update status in 'assigned' node
      await _database
          .child('assigned')
          .child(responderId)
          .child(emergencyId)
          .update({
        'status': 'cancelled',
        'cancelledAt': ServerValue.timestamp,
      });
      
      // Update responder status back to available
      await _database
          .child('Responders')
          .child(responderId)
          .update({
        'status': 'active',
        'currentEmergencyId': null,
        'isActive': true,
      });
      
      // Remove from user's activeEmergency
      await _database
          .child('Users')
          .child(userId)
          .child('activeEmergency')
          .remove();
      
      return true;
    } catch (e) {
      debugPrint('Error cancelling emergency: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ Complete emergency - WITH RESPONSE TIME CALCULATION
  // ============================================================
  Future<bool> completeEmergency(String emergencyId, String userId, String responderId) async {
    try {
      debugPrint('🔵 [completeEmergency] STARTING...');
      debugPrint('🔵 [completeEmergency] Emergency ID: $emergencyId');
      debugPrint('🔵 [completeEmergency] Responder ID: $responderId');
      
      // ✅ Get the emergency data to calculate response time
      final snapshot = await _database
          .child('assigned')
          .child(responderId)
          .child(emergencyId)
          .get();
      
      if (snapshot.value == null) {
        debugPrint('❌ [completeEmergency] Emergency not found: $emergencyId');
        return false;
      }
      
      final emergency = Map<String, dynamic>.from(snapshot.value as Map);
      debugPrint('📊 [completeEmergency] Emergency data retrieved');
      
      // ✅ Get SOS Time from sosTime field
      int sosTimeMs = 0;
      debugPrint('🔍 [completeEmergency] Checking for sosTime field...');
      
      if (emergency['sosTime'] != null) {
        sosTimeMs = emergency['sosTime'] as int;
        debugPrint('✅ [completeEmergency] sosTime found: $sosTimeMs');
        final sosDateTime = DateTime.fromMillisecondsSinceEpoch(sosTimeMs);
        debugPrint('✅ [completeEmergency] SOS Time: ${sosDateTime.toLocal()}');
      } else {
        debugPrint('⚠️ [completeEmergency] No sosTime field found in emergency data');
        debugPrint('📊 [completeEmergency] Available keys: ${emergency.keys}');
        
        // Try fallback to assignedAt
        if (emergency['assignedAt'] != null) {
          sosTimeMs = emergency['assignedAt'] as int;
          debugPrint('⚠️ [completeEmergency] Using assignedAt as fallback: $sosTimeMs');
        } else {
          debugPrint('❌ [completeEmergency] No timestamp found to calculate response time');
          return false;
        }
      }
      
      // ✅ Get current time as completion time
      final now = DateTime.now();
      final completedAtMs = now.millisecondsSinceEpoch;
      debugPrint('🕐 [completeEmergency] Completed at: ${now.toLocal()}');
      debugPrint('🕐 [completeEmergency] Completed at ms: $completedAtMs');
      
      // ✅ Calculate response time in milliseconds
      final responseTimeMs = completedAtMs - sosTimeMs;
      debugPrint('⏱️ [completeEmergency] Response time ms: $responseTimeMs');
      
      // ✅ Format response time as human-readable string
      final responseTimeStr = _formatDuration(Duration(milliseconds: responseTimeMs));
      debugPrint('⏱️ [completeEmergency] Response time: $responseTimeStr');
      
      // ✅ Format SOS Time as human-readable string
      final sosTimeStr = _formatDateTime(DateTime.fromMillisecondsSinceEpoch(sosTimeMs));
      debugPrint('📅 [completeEmergency] SOS Time formatted: $sosTimeStr');
      
      // ✅ Update status with response time and SOS time
      debugPrint('🔵 [completeEmergency] Updating Firebase...');
      await _database
          .child('assigned')
          .child(responderId)
          .child(emergencyId)
          .update({
        'status': 'completed',
        'completedAt': ServerValue.timestamp,
        'completedAtMs': completedAtMs,
        'responseTimeMs': responseTimeMs,
        'responseTime': responseTimeStr,
        'sosTimeFormatted': sosTimeStr,
      });
      debugPrint('✅ [completeEmergency] Firebase updated successfully');
      
      // Update responder status back to available
      await _database
          .child('Responders')
          .child(responderId)
          .update({
        'status': 'active',
        'currentEmergencyId': null,
        'isActive': true,
      });
      
      // Remove from user's activeEmergency
      await _database
          .child('Users')
          .child(userId)
          .child('activeEmergency')
          .remove();
      
      debugPrint('✅ [completeEmergency] COMPLETED SUCCESSFULLY!');
      debugPrint('   SOS Time: $sosTimeStr');
      debugPrint('   Response Time: $responseTimeStr');
      debugPrint('========================================');
      
      return true;
    } catch (e) {
      debugPrint('❌ [completeEmergency] ERROR: $e');
      debugPrint('❌ [completeEmergency] Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  // ============================================================
  // ✅ Format duration as human-readable string
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

  // ============================================================
  // ✅ Format DateTime as string
  // ============================================================
  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    
    return '$hour:$minute:$second $day/$month/$year';
  }
}