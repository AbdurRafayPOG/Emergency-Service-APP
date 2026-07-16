class DoctorRequest {
  final String userId;
  final String userName;
  final String userPhone;
  final String userEmail;
  final String status; // pending, assigned, completed
  final int createdAt;
  final String? requestId;
  final String? doctorId;
  final String? doctorName;

  DoctorRequest({
    required this.userId,
    required this.userName,
    required this.userPhone,
    required this.userEmail,
    this.status = 'pending',
    required this.createdAt,
    this.requestId,
    this.doctorId,
    this.doctorName,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'userEmail': userEmail,
      'status': status,
      'createdAt': createdAt,
      if (doctorId != null) 'doctorId': doctorId,
      if (doctorName != null) 'doctorName': doctorName,
    };
  }

  factory DoctorRequest.fromMap(Map<String, dynamic> map, {String? id}) {
    return DoctorRequest(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? 'Unknown User',
      userPhone: map['userPhone'] ?? '',
      userEmail: map['userEmail'] ?? '',
      status: map['status'] ?? 'pending',
      createdAt: map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      requestId: id,
      doctorId: map['doctorId'],
      doctorName: map['doctorName'],
    );
  }
}