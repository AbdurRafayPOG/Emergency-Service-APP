import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';
import 'package:public_emergency_app/Features/User/Controllers/call_controller.dart';
import 'package:public_emergency_app/Features/User/Screens/VoicenVideoCall/keys.dart';
import 'package:public_emergency_app/Features/User/Screens/bottom_nav.dart';

var color = 0xFF0F4C5C;

// 🔥 Shared notification tracker for doctor sessions
class DoctorNotificationTracker {
  static String? _currentRequestId;
  static bool _completedShown = false;
  static bool _cancelledShown = false;
  static bool _inactiveShown = false;
  
  static void reset() {
    _completedShown = false;
    _cancelledShown = false;
    _inactiveShown = false;
  }
  
  static void setRequestId(String requestId) {
    if (_currentRequestId != requestId) {
      reset();
      _currentRequestId = requestId;
    }
  }
  
  static bool isCompletedShown() => _completedShown;
  static bool isCancelledShown() => _cancelledShown;
  static bool isInactiveShown() => _inactiveShown;
  
  static void markCompletedShown() { _completedShown = true; }
  static void markCancelledShown() { _cancelledShown = true; }
  static void markInactiveShown() { _inactiveShown = true; }
}

class ActiveDoctorStatus extends StatefulWidget {
  final String doctorName;
  final String profession;
  final String? doctorId;
  final String? requestId;

  const ActiveDoctorStatus({
    Key? key,
    required this.doctorName,
    required this.profession,
    this.doctorId,
    this.requestId,
  }) : super(key: key);

  @override
  State<ActiveDoctorStatus> createState() => _ActiveDoctorStatusState();
}

class _ActiveDoctorStatusState extends State<ActiveDoctorStatus> {
  bool _isLoading = true;
  String _status = 'En Route';
  String? _doctorPhone;
  DateTime? _assignedAt;
  bool _isCalling = false;
  bool _isClosing = false;
  String? _doctorStatus;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  late CallController callController;

  Timer? _timer;
  StreamSubscription<DatabaseEvent>? _assignedListener;
  StreamSubscription<DatabaseEvent>? _doctorStatusListener;

  @override
  void initState() {
    super.initState();
    if (widget.requestId != null) {
      DoctorNotificationTracker.setRequestId(widget.requestId!);
    }
    
    try {
      callController = Get.find<CallController>();
    } catch (e) {
      callController = Get.put(CallController());
    }
    
    _initializeData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _assignedListener?.cancel();
    _doctorStatusListener?.cancel();
    super.dispose();
  }

  void _initializeData() {
    _fetchDoctorDetails();
  }

  Future<void> _fetchDoctorDetails() async {
    if (widget.doctorId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doctorSnapshot = await _database
          .child('Doctors')
          .child(widget.doctorId!)
          .get();

      if (doctorSnapshot.value != null) {
        final data = Map<String, dynamic>.from(doctorSnapshot.value as Map);
        _doctorPhone = data['Phone']?.toString();
        _doctorStatus = data['status']?.toString();
      }

      final assignedSnapshot = await _database
          .child('assigned_doctors')
          .child(widget.doctorId!)
          .child(widget.requestId ?? '')
          .get();

      if (assignedSnapshot.value != null) {
        final data = Map<String, dynamic>.from(assignedSnapshot.value as Map);
        _status = data['status']?.toString() ?? 'En Route';
        if (data['assignedAt'] != null) {
          final assignedAtValue = data['assignedAt'];
          _assignedAt = DateTime.fromMillisecondsSinceEpoch(assignedAtValue as int);
        }
      }

      _startAssignedListener();
      _startDoctorStatusListener();

      setState(() {
        _isLoading = false;
      });

    } catch (e) {
      print("❌ Error fetching doctor details: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startDoctorStatusListener() {
    if (widget.doctorId == null) return;

    _doctorStatusListener?.cancel();
    _doctorStatusListener = _database
        .child('Doctors')
        .child(widget.doctorId!)
        .onValue
        .listen((event) {
          final snapshot = event.snapshot;

          if (!snapshot.exists) {
            return;
          }

          final data = Map<String, dynamic>.from(snapshot.value as Map);
          final status = data['status']?.toString() ?? '';

          if (status == 'inactive' || status == 'Inactive') {
            _handleDoctorInactive();
          }
        }, onError: (error) {
          print("❌ Doctor status listener error: $error");
        });
  }

  void _startAssignedListener() {
    if (widget.doctorId == null || widget.requestId == null) return;

    _assignedListener?.cancel();
    _assignedListener = _database
        .child('assigned_doctors')
        .child(widget.doctorId!)
        .child(widget.requestId!)
        .onValue
        .listen((event) {
          final snapshot = event.snapshot;

          if (!snapshot.exists) {
            _database
                .child('Doctor_Done')
                .child(widget.requestId!)
                .get()
                .then((doneSnapshot) {
              if (doneSnapshot.exists) {
                _handleDoctorCompleted();
              } else {
                _handleNotFound();
              }
            }).catchError((e) {
              _handleNotFound();
            });
            return;
          }

          final data = Map<String, dynamic>.from(snapshot.value as Map);
          final status = data['status']?.toString() ?? '';

          setState(() {
            _status = status;
          });

          if (status == 'completed') {
            _handleDoctorCompleted();
          }

          if (status == 'cancelled') {
            _handleNotFound();
          }
        }, onError: (error) {
          print("❌ Listener error: $error");
        });
  }

  void _handleDoctorCompleted() {
    if (_isClosing) return;
    _isClosing = true;

    _timer?.cancel();
    _assignedListener?.cancel();
    _doctorStatusListener?.cancel();

    if (!DoctorNotificationTracker.isCompletedShown()) {
      DoctorNotificationTracker.markCompletedShown();
      
      Get.snackbar(
        '',
        '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.transparent,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 16,
        padding: EdgeInsets.zero,
        isDismissible: true,
        snackStyle: SnackStyle.FLOATING,
        titleText: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Session Completed',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                    ),
                    Text(
                      'Session has been ended by Dr. ${widget.doctorName}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        messageText: const SizedBox.shrink(),
      );
    }

    _goToNavBar();
  }

  void _handleDoctorInactive() {
    if (_isClosing) return;
    _isClosing = true;

    _timer?.cancel();
    _assignedListener?.cancel();
    _doctorStatusListener?.cancel();

    if (!DoctorNotificationTracker.isInactiveShown()) {
      DoctorNotificationTracker.markInactiveShown();
      
      Get.snackbar(
        '',
        '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.transparent,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 16,
        padding: EdgeInsets.zero,
        isDismissible: true,
        snackStyle: SnackStyle.FLOATING,
        titleText: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Doctor Unavailable',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                    ),
                    Text(
                      'Dr. ${widget.doctorName} is no longer available',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        messageText: const SizedBox.shrink(),
      );
    }

    _goToNavBar();
  }

  void _handleNotFound() {
    if (_isClosing) return;
    _isClosing = true;

    _timer?.cancel();
    _assignedListener?.cancel();
    _doctorStatusListener?.cancel();

    if (!DoctorNotificationTracker.isCancelledShown()) {
      DoctorNotificationTracker.markCancelledShown();
      
      Get.snackbar(
        '',
        '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.transparent,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 16,
        padding: EdgeInsets.zero,
        isDismissible: true,
        snackStyle: SnackStyle.FLOATING,
        titleText: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cancel_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Request Cancelled',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                    ),
                    Text(
                      'Doctor request is no longer active',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        messageText: const SizedBox.shrink(),
      );
    }

    _goToNavBar();
  }

  void _goToNavBar() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        Get.offAll(() => const NavBar());
      }
    });
  }

  void _makePhoneCall(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.isEmpty) {
      Get.snackbar(
        'Error',
        'No phone number available',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    String cleanNumber = phoneNumber.replaceAll(RegExp(r'[\s\-()]'), '');
    final Uri phoneUri = Uri(scheme: 'tel', path: cleanNumber);
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        throw 'Could not launch phone';
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Cannot make call',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  void _startVideoCall() async {
    if (_isCalling) return;
    if (widget.doctorId == null) {
      Get.snackbar(
        'Error',
        'No doctor assigned',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    setState(() {
      _isCalling = true;
    });

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      Get.snackbar(
        'Error',
        'You must be logged in to make a call',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
      setState(() {
        _isCalling = false;
      });
      return;
    }

    String userName = currentUser.displayName ?? 'User';
    String userId = currentUser.uid;
    
    String doctorName = widget.doctorName;
    if (!doctorName.startsWith('Dr.') && !doctorName.startsWith('Dr ')) {
      doctorName = 'Dr. $doctorName';
    }

    try {
      if (callController == null) {
        throw Exception('CallController not initialized');
      }

      await callController.initializeZego(userId, userName);

      await callController.sendInvitation(
        calleeID: widget.doctorId!,
        calleeName: doctorName,
        callID: widget.requestId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        inviterID: userId,
        inviterName: userName,
        isInviterHost: false,
        customData: {
          'userType': 'User',
          'userName': userName,
          'doctorName': doctorName,
        },
      );
    } catch (e) {
      print("❌ Video call error: $e");
      Get.snackbar(
        'Error',
        'Video call service not available. Please try again later.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
    }

    setState(() {
      _isCalling = false;
    });
  }

  Future<void> _copyToClipboard(String text, String label) async {
    if (text.isEmpty || text == 'N/A') {
      Get.snackbar(
        'Error',
        'No $label available to copy',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
      return;
    }
    
    try {
      await Clipboard.setData(ClipboardData(text: text));
      Get.rawSnackbar(
        message: 'Copied!',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.black.withOpacity(0.8),
        duration: const Duration(milliseconds: 2000),
        margin: const EdgeInsets.symmetric(horizontal: 120, vertical: 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        borderRadius: 10,
        shouldIconPulse: false,
        isDismissible: true,
        forwardAnimationCurve: Curves.easeOut,
        reverseAnimationCurve: Curves.easeIn,
        animationDuration: const Duration(milliseconds: 300),
        snackStyle: SnackStyle.FLOATING,
        messageText: const Center(
          child: Text(
            'Copied!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to copy $label',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
    }
  }

  Widget _buildInfoItem({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    bool isCopyable = false,
    VoidCallback? onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCopyable && value.isNotEmpty && value != 'N/A')
                      GestureDetector(
                        onTap: onCopy,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.copy,
                            color: iconColor,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
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

  @override
  Widget build(BuildContext context) {
    final double appBarHeight = Get.height * 0.12 + kToolbarHeight;
    final double iconHeight = Get.height * 0.09;
    final double buttonSize = 44;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F4C5C),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(40),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/logos/emergencyAppLogo.png',
                      height: iconHeight,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Active Doctor',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                top: (appBarHeight / 2) - (buttonSize / 2),
                child: GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    width: buttonSize,
                    height: buttonSize,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white,
                          Colors.white,
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.6),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: const Color(0xFF0F4C5C),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                children: [
                  // ============================================================
// STATUS CARD - WITH ONLY "ASSIGNED" AT TOP RIGHT
// ============================================================
Container(
  width: double.infinity,
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(color),
        Color(color).withOpacity(0.8),
      ],
    ),
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
      BoxShadow(
        color: Color(color).withOpacity(0.2),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  child: Stack(
    children: [
      Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.5),
                width: 3,
              ),
            ),
            child: Center(
              child: Text(
                widget.doctorName.isNotEmpty
                    ? widget.doctorName[0].toUpperCase()
                    : 'D',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F4C5C),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Dr. ${widget.doctorName}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.profession,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      // 🔥 "ASSIGNED" BADGE AT TOP RIGHT
      Positioned(
        top: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.9),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                'Assigned',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
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
                  const SizedBox(height: 12),

                  // ============================================================
                  // DOCTOR INFORMATION CARD
                  // ============================================================
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(
                        color: Colors.grey.shade100,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          decoration: BoxDecoration(
                            color: Color(color),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.medical_services_rounded,
                                  color: Color(color),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Doctor Information',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1. Doctor Name 
                              _buildInfoItem(
                                label: 'Doctor Name',
                                value: 'Dr. ${widget.doctorName}',
                                icon: Icons.person_rounded,
                                iconColor: Color(color),
                                isCopyable: false,
                              ),
                              _buildDivider(),
                              // 2. Profession 
                              _buildInfoItem(
                                label: 'Profession',
                                value: widget.profession,
                                icon: Icons.work_rounded,
                                iconColor: Color(color),
                                isCopyable: false,
                              ),
                              _buildDivider(),
                              // 3. Request Time
                              _buildInfoItem(
                                label: 'Request Time',
                                value: _assignedAt != null ? _formatTime(_assignedAt!) : 'Not Available',
                                icon: Icons.access_time_rounded,
                                iconColor: Color(color),
                                isCopyable: false,
                              ),
                              _buildDivider(),
                              // 4. Phone Number - Copyable ✅
                              _buildInfoItem(
                                label: 'Phone Number',
                                value: _doctorPhone ?? 'Not Available',
                                icon: Icons.phone_rounded,
                                iconColor: Color(color),
                                isCopyable: true,
                                onCopy: () {
                                  if (_doctorPhone != null && _doctorPhone!.isNotEmpty) {
                                    _copyToClipboard(_doctorPhone!, 'phone number');
                                  }
                                },
                              ),
                              _buildDivider(),
                              // 5. Request ID - Copyable ✅
                              _buildInfoItem(
                                label: 'Request ID',
                                value: widget.requestId ?? 'N/A',
                                icon: Icons.qr_code_rounded,
                                iconColor: Color(color),
                                isCopyable: widget.requestId != null,
                                onCopy: () {
                                  if (widget.requestId != null) {
                                    _copyToClipboard(widget.requestId!, 'Request ID');
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ============================================================
                  // ACTION BUTTONS
                  // ============================================================
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.phone,
                          label: 'Sim Call',
                          color: const Color(0xFF2196F3),
                          onPressed: () {
                            if (_doctorPhone != null && _doctorPhone!.isNotEmpty) {
                              _makePhoneCall(_doctorPhone);
                            } else {
                              Get.snackbar(
                                'Error',
                                'No phone number available',
                                snackPosition: SnackPosition.TOP,
                                backgroundColor: Colors.red,
                                colorText: Colors.white,
                                duration: const Duration(seconds: 2),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildActionButton(
                          icon: Icons.video_call,
                          label: 'Call/Video Call',
                          color: Colors.red,
                          onPressed: _isCalling ? null : _startVideoCall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withOpacity(0.3)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        elevation: 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} ${time.day}/${time.month}/${time.year}';
  }
}