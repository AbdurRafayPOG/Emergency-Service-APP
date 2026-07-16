import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:get/get.dart';

class DoctorService {
  static const String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app';

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // ============================================================
  // CREATE DOCTOR REQUEST - NO doctor_requests node
  // ============================================================
  Future<Map<String, dynamic>> createDoctorRequest() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return {'success': false, 'error': 'User not logged in'};
      }

      String userName = 'Unknown User';
      String userPhone = '';
      String userEmail = user.email ?? '';
      
      try {
        final userSnapshot = await _db.child('Users').child(user.uid).get();
        if (userSnapshot.value != null) {
          final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
          userName = userData['UserName']?.toString() ?? 'Unknown User';
          userPhone = userData['Phone']?.toString() ?? '';
          userEmail = userData['Email']?.toString() ?? user.email ?? '';
        }
      } catch (e) {
        // Ignore
      }

      final assignmentResult = await _assignToAvailableDoctor(
        userId: user.uid,
        userName: userName,
        userPhone: userPhone,
        userEmail: userEmail,
      );

      return {
        'success': true,
        'assigned': assignmentResult['assigned'] ?? false,
        'doctorId': assignmentResult['doctorId'],
        'doctorName': assignmentResult['doctorName'],
        'profession': assignmentResult['profession'] ?? 'Doctor', // ✅ Added profession
        'requestId': assignmentResult['requestId'],
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // AUTO-ASSIGN TO AVAILABLE DOCTOR
  // ============================================================
  Future<Map<String, dynamic>> _assignToAvailableDoctor({
    required String userId,
    required String userName,
    required String userPhone,
    required String userEmail,
  }) async {
    try {
      final doctorsSnapshot = await _db.child('Doctors').get();
      
      if (doctorsSnapshot.value == null) {
        return {'assigned': false};
      }

      final doctors = Map<String, dynamic>.from(doctorsSnapshot.value as Map);
      
      for (var doctorId in doctors.keys) {
        final doctorData = Map<String, dynamic>.from(doctors[doctorId] as Map);
        final status = doctorData['status']?.toString() ?? '';
        final isActive = doctorData['isActive'] ?? false;
        final currentRequestId = doctorData['currentRequestId']?.toString() ?? '';
        
        if ((status == 'active' || status == 'Active') && isActive == true && currentRequestId.isEmpty) {
          final requestRef = _db.child('assigned_doctors').child(doctorId).push();
          final requestId = requestRef.key!;
          
          await _assignRequestToDoctor(
            requestId: requestId,
            doctorId: doctorId,
            doctorData: doctorData,
            userId: userId,
            userName: userName,
            userPhone: userPhone,
            userEmail: userEmail,
          );
          
          // ✅ Get profession from doctor data
          String profession = doctorData['Profession']?.toString() ?? 
                              doctorData['UserType']?.toString() ?? 
                              'Doctor';
          
          return {
            'assigned': true,
            'doctorId': doctorId,
            'doctorName': doctorData['UserName']?.toString() ?? 'Unknown Doctor',
            'profession': profession, // ✅ Return profession
            'requestId': requestId,
          };
        }
      }

      return {'assigned': false};
    } catch (e) {
      return {'assigned': false};
    }
  }

  // ============================================================
  // ASSIGN REQUEST TO DOCTOR
  // ============================================================
  Future<void> _assignRequestToDoctor({
    required String requestId,
    required String doctorId,
    required Map<String, dynamic> doctorData,
    required String userId,
    required String userName,
    required String userPhone,
    required String userEmail,
  }) async {
    // ✅ Get profession from doctor data
    String profession = doctorData['Profession']?.toString() ?? 
                        doctorData['UserType']?.toString() ?? 
                        'Doctor';

    await _db
        .child('assigned_doctors')
        .child(doctorId)
        .child(requestId)
        .set({
          'userId': userId,
          'userName': userName,
          'userPhone': userPhone,
          'userEmail': userEmail,
          'status': 'assigned',
          'assignedAt': DateTime.now().millisecondsSinceEpoch,
          'doctorId': doctorId,
          'doctorName': doctorData['UserName']?.toString() ?? 'Unknown Doctor',
          'profession': profession, // ✅ Added profession to request data
        });

    await _db.child('Doctors').child(doctorId).update({
      'status': 'busy',
      'isActive': false,
      'isAvailable': false,
      'currentRequestId': requestId,
    });
  }

  // ============================================================
  // MARK AS DONE - Moves to Doctor_Done
  // ============================================================
  Future<bool> markDoctorRequestAsDone({
    required String requestId,
    required Map<String, dynamic> requestData,
    required String doctorId,
    required String doctorName,
  }) async {
    try {
      final userId = requestData['userId']?.toString() ?? '';
      String userName = requestData['userName']?.toString() ?? 'Unknown User';
      String userPhone = requestData['userPhone']?.toString() ?? '';
      String userEmail = requestData['userEmail']?.toString() ?? '';

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

      final currentUser = FirebaseAuth.instance.currentUser;
      String currentUserEmail = currentUser?.email ?? '';
      String currentUserUid = currentUser?.uid ?? '';

      final completedData = {
        'requestId': requestId,
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

      await _db.child('Doctor_Done').child(requestId).set(completedData);
      await _db.child('assigned_doctors').child(doctorId).child(requestId).remove();
      await _db.child('Doctors').child(doctorId).update({
        'status': 'active',
        'isActive': true,
        'isAvailable': true,
        'currentRequestId': null,
      });

      return true;
    } catch (e) {
      print('❌ Error marking doctor request as done: $e');
      return false;
    }
  }

  // ============================================================
  // UNDO - Restore from Doctor_Done
  // ============================================================
  Future<bool> undoDoctorRequest({
    required String requestId,
    required Map<String, dynamic> completedData,
    required String doctorId,
  }) async {
    try {
      final userInfo = Map<String, dynamic>.from(completedData['userInfo'] as Map);
      final userId = userInfo['uid']?.toString() ?? '';
      final userName = userInfo['name']?.toString() ?? 'Unknown User';
      final userPhone = userInfo['phone']?.toString() ?? '';
      final userEmail = userInfo['email']?.toString() ?? '';

      final doctorSnapshot = await _db.child('Doctors').child(doctorId).get();
      if (!doctorSnapshot.exists) {
        return false;
      }
      final doctorData = Map<String, dynamic>.from(doctorSnapshot.value as Map);
      
      // ✅ Get profession from doctor data
      String profession = doctorData['Profession']?.toString() ?? 
                          doctorData['UserType']?.toString() ?? 
                          'Doctor';

      await _db
          .child('assigned_doctors')
          .child(doctorId)
          .child(requestId)
          .set({
            'userId': userId,
            'userName': userName,
            'userPhone': userPhone,
            'userEmail': userEmail,
            'status': 'assigned',
            'assignedAt': DateTime.now().millisecondsSinceEpoch,
            'doctorId': doctorId,
            'doctorName': doctorData['UserName']?.toString() ?? 'Unknown Doctor',
            'profession': profession, // ✅ Added profession
          });

      await _db.child('Doctors').child(doctorId).update({
        'status': 'busy',
        'isActive': false,
        'isAvailable': false,
        'currentRequestId': requestId,
      });

      await _db.child('Doctor_Done').child(requestId).remove();

      return true;
    } catch (e) {
      print('❌ Error undoing doctor request: $e');
      return false;
    }
  }

  // ============================================================
  // VIDEO CALL - User to Doctor
  // ============================================================
  Future<Map<String, dynamic>> startDoctorVideoCall({
    required String doctorId,
    required String doctorName,
    required String userId,
    required String userName,
    required String requestId,
  }) async {
    try {
      final assignedSnapshot = await _db
          .child('assigned_doctors')
          .child(doctorId)
          .child(requestId)
          .get();
      
      if (!assignedSnapshot.exists) {
        return {
          'success': false,
          'error': 'Doctor is no longer assigned to this request',
        };
      }

      final requestData = Map<String, dynamic>.from(assignedSnapshot.value as Map);
      final status = requestData['status']?.toString() ?? '';

      if (status != 'assigned') {
        return {
          'success': false,
          'error': 'Request is no longer active',
        };
      }

      return {
        'success': true,
        'callId': requestId,
        'doctorName': doctorName,
        'userName': userName,
        'doctorId': doctorId,
        'userId': userId,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ============================================================
  // HELPER: Format Duration
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
  // HELPER: Format DateTime
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