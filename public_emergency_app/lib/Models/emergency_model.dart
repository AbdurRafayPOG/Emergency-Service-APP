class Emergency {
  final String? id;
  final String userId;
  final String userEmail;
  final String userName;
  final double userLat;
  final double userLong;
  final String address;
  final String emergencyType; // 'Police' or 'Firefighter'
  final String status; // 'pending', 'assigned', 'en_route', 'completed', 'cancelled'
  final DateTime createdAt;
  final String? responderId;
  final String? responderName;
  final String? responderType;
  final DateTime? assignedAt;

  Emergency({
    this.id,
    required this.userId,
    required this.userEmail,
    required this.userName,
    required this.userLat,
    required this.userLong,
    required this.address,
    required this.emergencyType,
    this.status = 'pending',
    required this.createdAt,
    this.responderId,
    this.responderName,
    this.responderType,
    this.assignedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userEmail': userEmail,
      'userName': userName,
      'userLat': userLat,
      'userLong': userLong,
      'address': address,
      'emergencyType': emergencyType,
      'status': status,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'responderId': responderId,
      'responderName': responderName,
      'responderType': responderType,
      'assignedAt': assignedAt?.millisecondsSinceEpoch,
    };
  }

  factory Emergency.fromMap(Map<String, dynamic> map) {
    return Emergency(
      id: map['id']?.toString(),
      userId: map['userId']?.toString() ?? '',
      userEmail: map['userEmail']?.toString() ?? '',
      userName: map['userName']?.toString() ?? 'Unknown User',
      userLat: double.tryParse(map['userLat']?.toString() ?? '0') ?? 0,
      userLong: double.tryParse(map['userLong']?.toString() ?? '0') ?? 0,
      address: map['address']?.toString() ?? '',
      emergencyType: map['emergencyType']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] is int 
            ? map['createdAt'] 
            : DateTime.now().millisecondsSinceEpoch,
      ),
      responderId: map['responderId']?.toString(),
      responderName: map['responderName']?.toString(),
      responderType: map['responderType']?.toString(),
      assignedAt: map['assignedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              map['assignedAt'] is int ? map['assignedAt'] : 0,
            )
          : null,
    );
  }
}

class EmergencyHistory {
  final String id;
  final String userId;
  final String emergencyType;
  final String responderName;
  final String responderType;
  final String status;
  final DateTime completedAt;
  final String? responseTime;
  final Map<String, dynamic>? details;

  EmergencyHistory({
    required this.id,
    required this.userId,
    required this.emergencyType,
    required this.responderName,
    required this.responderType,
    required this.status,
    required this.completedAt,
    this.responseTime,
    this.details,
  });

  factory EmergencyHistory.fromMap(String id, Map<String, dynamic> map) {
    final emergencyData = map['emergencyData'] as Map? ?? {};
    
    return EmergencyHistory(
      id: id,
      userId: map['userInfo']?['uid']?.toString() ?? '',
      emergencyType: emergencyData['emergencyType']?.toString() ?? 'Unknown',
      responderName: map['completedBy']?['name']?.toString() ?? 'Unknown',
      responderType: map['completedBy']?['type']?.toString() ?? 'Responder',
      status: map['status']?.toString() ?? 'completed',
      completedAt: map['completedAt'] != null
          ? DateTime.parse(map['completedAt'].toString())
          : DateTime.now(),
      responseTime: map['responseTime']?.toString(),
      details: map,
    );
  }
}