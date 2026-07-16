import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:public_emergency_app/Features/User/Controllers/call_controller.dart';
import 'package:public_emergency_app/Features/User/Screens/VoicenVideoCall/keys.dart';
import 'package:public_emergency_app/Features/User/Screens/VoicenVideoCall/sos_page.dart';
import 'package:public_emergency_app/Services/emergency_assignment_service.dart';
import 'package:public_emergency_app/Features/User/Screens/bottom_nav.dart';

class NotificationTracker {
  static bool _emergencyCompletedShown = false;
  static bool _emergencyCancelledShown = false;
  
  static void reset() {
    _emergencyCompletedShown = false;
    _emergencyCancelledShown = false;
  }
  
  static bool get isCompletedShown => _emergencyCompletedShown;
  static bool get isCancelledShown => _emergencyCancelledShown;
  
  static void markCompletedShown() { _emergencyCompletedShown = true; }
  static void markCancelledShown() { _emergencyCancelledShown = true; }
}

class EmergencyStatusPage extends StatefulWidget {
  final String emergencyId;
  
  const EmergencyStatusPage({
    Key? key,
    required this.emergencyId,
  }) : super(key: key);

  @override
  State<EmergencyStatusPage> createState() => _EmergencyStatusPageState();
}

class _EmergencyStatusPageState extends State<EmergencyStatusPage> {
  Map<String, dynamic>? _emergencyData;
  Map<String, dynamic>? _responderData;
  bool _isLoading = true;
  String _status = 'En Route';
  String? _currentUserId;
  String? _responderId;
  
  DateTime? _sosTime;
  DateTime? _completedAt;
  String _responseTime = 'In progress';
  
  Timer? _timer;
  Timer? _responderStatusTimer;
  
  StreamSubscription<DatabaseEvent>? _assignedListener;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final CallController callController = Get.find<CallController>();
  final EmergencyAssignmentService _assignmentService = Get.find<EmergencyAssignmentService>();

  bool _isCalling = false;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    NotificationTracker.reset();
    _initializeData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _responderStatusTimer?.cancel();
    _assignedListener?.cancel();
    if (_emergencyData != null && _responderId != null && _currentUserId != null) {
      _assignmentService.stopAssignmentValidation(widget.emergencyId);
    }
    super.dispose();
  }

  void _initializeData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.back();
      return;
    }
    _currentUserId = user.uid;
    _loadEmergencyData();
  }

  Future<void> _loadEmergencyData() async {
    try {
      final assignedSnapshot = await _database
          .child('assigned')
          .get();
      
      if (assignedSnapshot.value == null) {
        _handleEmergencyNotFound();
        return;
      }
      
      final data = Map<String, dynamic>.from(assignedSnapshot.value as Map);
      bool found = false;
      
      for (var responderId in data.keys) {
        final emergencies = Map<String, dynamic>.from(data[responderId] as Map);
        
        if (emergencies.containsKey(widget.emergencyId)) {
          _emergencyData = Map<String, dynamic>.from(emergencies[widget.emergencyId]);
          _status = _emergencyData?['status'] ?? 'En Route';
          _responderId = responderId.toString();
          
          if (_emergencyData!['sosTime'] != null) {
            final sosTimeValue = _emergencyData!['sosTime'];
            _sosTime = DateTime.fromMillisecondsSinceEpoch(sosTimeValue as int);
          }
          
          if (_emergencyData!['completedAt'] != null) {
            final completedAtValue = _emergencyData!['completedAt'];
            _completedAt = DateTime.fromMillisecondsSinceEpoch(completedAtValue as int);
            _calculateResponseTime();
          } else {
            _startResponseTimer();
          }
          
          found = true;
          await _fetchResponderData(responderId.toString());
          
          _startAssignmentValidation();
          _startResponderStatusCheck();
          _startAssignedListener();
          break;
        }
      }
      
      if (found) {
        setState(() {
          _isLoading = false;
        });
      } else {
        _handleEmergencyNotFound();
      }
      
    } catch (e) {
      print("❌ Error loading emergency data: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _startAssignedListener() {
    if (_responderId == null) return;
    
    _assignedListener?.cancel();
    _assignedListener = _database
        .child('assigned')
        .child(_responderId!)
        .child(widget.emergencyId)
        .onValue
        .listen((event) {
          final snapshot = event.snapshot;
          
          if (!snapshot.exists) {
            print("📋 Emergency removed from assigned");
            _database.child('SOS_Done').child(widget.emergencyId).get().then((sosSnapshot) {
              if (sosSnapshot.exists) {
                _handleEmergencyCompleted();
              } else {
                _handleEmergencyNotFound();
              }
            }).catchError((e) {
              _handleEmergencyNotFound();
            });
            return;
          }
          
          final emergency = Map<String, dynamic>.from(snapshot.value as Map);
          final status = emergency['status']?.toString() ?? '';
          
          if (mounted) {
            setState(() {
              _status = status;
            });
          }
          
          if (status == 'completed') {
            if (emergency['completedAt'] != null) {
              final completedAtValue = emergency['completedAt'];
              _completedAt = DateTime.fromMillisecondsSinceEpoch(completedAtValue as int);
              _calculateResponseTime();
            }
            _handleEmergencyCompleted();
          }
          
          if (status == 'cancelled') {
            _handleEmergencyNotFound();
          }
        }, onError: (error) {
          print("❌ Listener error: $error");
        });
  }

  void _startResponderStatusCheck() {
    _responderStatusTimer?.cancel();
    _responderStatusTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_responderId == null || _isClosing) return;
      
      try {
        final snapshot = await _database
            .child('Responders')
            .child(_responderId!)
            .get();
        
        if (!snapshot.exists) {
          _handleResponderOffline();
          return;
        }
        
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        final status = data['status']?.toString() ?? '';
        final isActive = data['isActive'] ?? false;
        final isOnline = data['isOnline'] ?? false;
        final currentEmergencyId = data['currentEmergencyId']?.toString() ?? '';
        
        bool isOffline = false;
        
        if (status == 'inactive' || status == 'Inactive') {
          if (currentEmergencyId != widget.emergencyId) {
            isOffline = true;
          }
        }
        else if (status == 'busy' && currentEmergencyId == widget.emergencyId) {
          print("🟡 Responder is busy with this emergency");
          return;
        }
        else if (status == 'busy' && currentEmergencyId != widget.emergencyId) {
          isOffline = true;
        }
        else if (status != 'busy') {
          if (!isActive || !isOnline) {
            isOffline = true;
          }
        }
        
        if (isOffline) {
          _handleResponderOffline();
          return;
        }
        
        final assignedSnapshot = await _database
            .child('assigned')
            .child(_responderId!)
            .child(widget.emergencyId)
            .get();
        
        if (!assignedSnapshot.exists) {
          _database.child('SOS_Done').child(widget.emergencyId).get().then((sosSnapshot) {
            if (sosSnapshot.exists) {
              _handleEmergencyCompleted();
            } else {
              _handleEmergencyNotFound();
            }
          }).catchError((e) {
            _handleEmergencyNotFound();
          });
        }
        
      } catch (e) {
        print("❌ Error checking responder status: $e");
      }
    });
  }

  void _startAssignmentValidation() {
    if (_responderId == null || _currentUserId == null) return;
    
    _assignmentService.startAssignmentValidation(
      emergencyId: widget.emergencyId,
      responderId: _responderId!,
      userId: _currentUserId!,
      onResponderOffline: () {
        _handleResponderOffline();
      },
      onEmergencyCompleted: () {
        _handleEmergencyCompleted();
      },
    );
  }

  void _handleEmergencyCompleted() {
    if (_isClosing) return;
    _isClosing = true;
    
    print("✅ Emergency completed");
    
    _timer?.cancel();
    _responderStatusTimer?.cancel();
    _assignedListener?.cancel();
    
    if (!NotificationTracker.isCompletedShown) {
      NotificationTracker.markCompletedShown();
      _showNotification(
        title: 'Emergency Completed',
        message: 'Responder has Marked as done.',
        icon: Icons.check_circle_rounded,
        color: Colors.green,
      );
      
      Future.delayed(const Duration(seconds: 5), () {
        NotificationTracker.reset();
      });
    }
    
    _goToNavBar();
  }

  void _handleEmergencyNotFound() {
    if (_isClosing) return;
    _isClosing = true;
    
    print("📋 Emergency not found");
    
    _timer?.cancel();
    _responderStatusTimer?.cancel();
    _assignedListener?.cancel();
    
    if (!NotificationTracker.isCancelledShown) {
      NotificationTracker.markCancelledShown();
      _showNotification(
        title: 'Emergency Cancelled',
        message: 'This emergency is no longer active.',
        icon: Icons.cancel_rounded,
        color: Colors.orange,
      );
      
      Future.delayed(const Duration(seconds: 5), () {
        NotificationTracker.reset();
      });
    }
    
    _goToNavBar();
  }

  void _handleResponderOffline() {
    if (_isClosing) return;
    _isClosing = true;
    
    print("⚠️ Responder offline");
    
    _timer?.cancel();
    _responderStatusTimer?.cancel();
    _assignedListener?.cancel();
    
    _showNotification(
      title: 'Responder Unavailable',
      message: 'Responder is no longer available.',
      icon: Icons.wifi_off_rounded,
      color: Colors.red,
    );
    
    _goToNavBar();
  }

  void _showNotification({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
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
          color: color,
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
              child: Icon(
                icon,
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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                  ),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.9),
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

  void _goToNavBar() {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        Get.offAll(() => const NavBar());
      }
    });
  }

  void _calculateResponseTime() {
    if (_sosTime != null && _completedAt != null) {
      final difference = _completedAt!.difference(_sosTime!);
      setState(() {
        _responseTime = _formatDuration(difference);
      });
      _timer?.cancel();
    }
  }

  void _startResponseTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _checkForCompletion();
    });
  }

  Future<void> _checkForCompletion() async {
    try {
      if (_responderId == null) return;
      
      final assignedSnapshot = await _database
          .child('assigned')
          .child(_responderId!)
          .child(widget.emergencyId)
          .get();
      
      if (!assignedSnapshot.exists) {
        final sosDoneSnapshot = await _database
            .child('SOS_Done')
            .child(widget.emergencyId)
            .get();
        
        if (sosDoneSnapshot.exists) {
          _handleEmergencyCompleted();
        } else {
          _handleEmergencyNotFound();
        }
        return;
      }
      
      final emergency = Map<String, dynamic>.from(assignedSnapshot.value as Map);
      final status = emergency['status']?.toString() ?? '';
      
      if (status == 'completed' || status == 'cancelled') {
        if (emergency['completedAt'] != null) {
          final completedAtValue = emergency['completedAt'];
          _completedAt = DateTime.fromMillisecondsSinceEpoch(completedAtValue as int);
          _calculateResponseTime();
        }
        _timer?.cancel();
        setState(() {
          _status = status;
        });
        
        if (status == 'completed') {
          _handleEmergencyCompleted();
        }
      }
      
    } catch (e) {
      // Silent catch
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '--:--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchResponderData(String responderId) async {
    try {
      final responderSnapshot = await _database
          .child('Responders')
          .child(responderId)
          .get();
      
      if (responderSnapshot.value != null) {
        _responderData = Map<String, dynamic>.from(responderSnapshot.value as Map);
        _responderData!['responderId'] = responderId;
      }
    } catch (e) {
      // Silent catch
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    if (text.isEmpty) {
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
        duration: const Duration(milliseconds: 1500),
        margin: const EdgeInsets.symmetric(horizontal: 140, vertical: 40),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        borderRadius: 10,
        shouldIconPulse: false,
        isDismissible: true,
        snackStyle: SnackStyle.FLOATING,
        messageText: const Center(
          child: Text(
            'Copied!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to copy',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
        borderRadius: 12,
      );
    }
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

  void _openResponderLocation() async {
    final lat = _responderData?['lat']?.toString();
    final long = _responderData?['long']?.toString();
    
    if (lat == null || long == null || lat.isEmpty || long.isEmpty) {
      Get.snackbar(
        'Error',
        'Location not available',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    
    final latDouble = double.tryParse(lat);
    final longDouble = double.tryParse(long);
    
    if (latDouble == null || longDouble == null) {
      Get.snackbar(
        'Error',
        'Invalid location',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    
    String url = 'https://www.google.com/maps/search/?api=1&query=$lat,$long';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      Get.snackbar(
        'Error',
        'Cannot open maps',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  void _startVideoCall() async {
    if (_isCalling) return;
    
    setState(() {
      _isCalling = true;
    });

    final String? responderId = _emergencyData?['responderId']?.toString();
    
    if (responderId == null || responderId.isEmpty) {
      setState(() {
        _isCalling = false;
      });
      _showNotification(
        title: 'Error',
        message: 'No responder assigned',
        icon: Icons.error_outline_rounded,
        color: Colors.red,
      );
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      setState(() {
        _isCalling = false;
      });
      _showNotification(
        title: 'Error',
        message: 'You must be logged in to make a call',
        icon: Icons.error_outline_rounded,
        color: Colors.red,
      );
      return;
    }

    String userId = currentUser.uid;
    String userName = Keys.currentUserName.isNotEmpty ? Keys.currentUserName : 'User';

    try {
      final responderSnapshot = await _database
          .child('Responders')
          .child(responderId)
          .get();
      
      if (!responderSnapshot.exists) {
        setState(() {
          _isCalling = false;
        });
        _showNotification(
          title: 'Error',
          message: 'Responder not found',
          icon: Icons.error_outline_rounded,
          color: Colors.red,
        );
        return;
      }
      
      final data = Map<String, dynamic>.from(responderSnapshot.value as Map);
      final status = data['status']?.toString() ?? '';
      final isActive = data['isActive'] ?? false;
      final isOnline = data['isOnline'] ?? false;
      final currentEmergencyId = data['currentEmergencyId']?.toString() ?? '';
      
      bool allowCall = false;
      String? blockReason;
      
      if (status == 'inactive' || status == 'Inactive') {
        blockReason = 'Responder is not currently active.';
      }
      else if (status == 'busy' && currentEmergencyId == widget.emergencyId && isOnline == true) {
        allowCall = true;
        print("🟡 Responder is busy with this emergency - allowing call");
      }
      else if (status == 'busy' && currentEmergencyId != widget.emergencyId) {
        blockReason = 'Responder is handling another emergency.';
      }
      else if (status != 'busy' && !isActive) {
        blockReason = 'Responder is currently unavailable.';
      }
      else if (status != 'busy' && !isOnline) {
        blockReason = 'Responder is currently offline.';
      }
      else {
        allowCall = true;
      }
      
      if (!allowCall && blockReason != null) {
        setState(() {
          _isCalling = false;
        });
        _showNotification(
          title: 'Call Unavailable',
          message: blockReason,
          icon: Icons.block_rounded,
          color: Colors.red,
        );
        return;
      }
      
    } catch (e) {
      print("⚠️ Could not verify responder status: $e");
      setState(() {
        _isCalling = false;
      });
      _showNotification(
        title: 'Error',
        message: 'Could not verify responder status',
        icon: Icons.error_outline_rounded,
        color: Colors.red,
      );
      return;
    }

    final String responderName = _responderData?['UserName']?.toString() ?? 'Responder';

    await callController.initializeZego(userId, userName);

    await callController.sendInvitation(
      calleeID: responderId,
      calleeName: responderName,
      callID: widget.emergencyId,
      inviterID: userId,
      inviterName: userName,
      isInviterHost: false,
      customData: {
        'emergencyId': widget.emergencyId,
        'userType': 'User',
        'userName': userName,
        'responderName': responderName,
      },
    );

    setState(() {
      _isCalling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F4C5C),
        centerTitle: true,
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(Get.height * 0.16),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Image.asset(
                        'assets/logos/emergencyAppLogo.png',
                        height: Get.height * 0.08,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Emergency Status',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                top: 8 + (Get.height * 0.08 / 2) - 20,
                child: GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    width: 40,
                    height: 40,
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
                        size: 18,
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
          : _emergencyData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No emergency data found',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Get.back(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F4C5C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // Status Card
                      _buildStatusCard(),
                      const SizedBox(height: 12),
                      
                      // Emergency Information Card
                      if (_responderData != null)
                        _buildEmergencyInfoCard(),
                      const SizedBox(height: 12),
                      
                      // Action Buttons
                      _buildActionButtons(),
                    ],
                  ),
                ),
    );
  }

  // ============================================================
  // STATUS CARD
  // ============================================================
  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F4C5C), Color(0xFF1A7A8C)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F4C5C).withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.emergency_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Emergency Status',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _status == 'completed' 
                  ? Colors.green.withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _status == 'completed' 
                  ? Icons.check_circle_rounded 
                  : Icons.pending_rounded,
              color: _status == 'completed' ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMERGENCY INFORMATION CARD
  // ============================================================
  Widget _buildEmergencyInfoCard() {
    return Container(
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
              color: const Color(0xFF0F4C5C),
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
                    Icons.info_rounded,
                    color: const Color(0xFF0F4C5C),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Emergency Information',
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
                // Responder Name - NOT COPYABLE
                _buildInfoItem(
                  label: 'Responder Name',
                  value: _responderData?['UserName'] ?? 'Unknown',
                  icon: Icons.person_rounded,
                  iconColor: const Color(0xFF0F4C5C),
                  isCopyable: false,
                ),
                _buildDivider(),
                // Responder Role - NOT COPYABLE
                _buildInfoItem(
                  label: 'Responder Role',
                  value: _responderData?['UserType'] ?? 'Responder',
                  icon: Icons.work_rounded,
                  iconColor: const Color(0xFF0F4C5C),
                  isCopyable: false,
                ),
                _buildDivider(),
                // Responder Phone - COPYABLE
                _buildInfoItem(
                  label: 'Responder Phone',
                  value: _responderData?['Phone'] ?? 'N/A',
                  icon: Icons.phone_rounded,
                  iconColor: const Color(0xFF0F4C5C),
                  isCopyable: true,
                  onCopy: () {
                    String phone = _responderData?['Phone']?.toString() ?? '';
                    if (phone.isNotEmpty) {
                      _copyToClipboard(phone, 'Responder Phone');
                    }
                  },
                ),
                _buildDivider(),
                // SOS Time - NOT COPYABLE
                _buildInfoItem(
                  label: 'SOS Time',
                  value: _formatTime(_sosTime),
                  icon: Icons.alarm_rounded,
                  iconColor: const Color(0xFF0F4C5C),
                  isCopyable: false,
                ),
                _buildDivider(),
                // Emergency ID - COPYABLE
                _buildInfoItem(
                  label: 'Emergency ID',
                  value: widget.emergencyId,
                  icon: Icons.qr_code_rounded,
                  iconColor: const Color(0xFF0F4C5C),
                  isCopyable: true,
                  onCopy: () {
                    _copyToClipboard(widget.emergencyId, 'Emergency ID');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

  // ============================================================
  // ACTION BUTTONS
  // ============================================================
  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.phone,
            label: 'Sim Call',
            color: const Color(0xFF2196F3),
            onPressed: () {
              if (_responderData?['Phone'] != null && _responderData!['Phone'].toString().isNotEmpty) {
                _makePhoneCall(_responderData!['Phone'].toString());
              } else {
                Get.snackbar(
                  'Error',
                  'No phone number available',
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                  duration: const Duration(seconds: 2),
                  margin: const EdgeInsets.all(16),
                  borderRadius: 12,
                );
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildActionButton(
            icon: Icons.location_on,
            label: 'Location',
            color: Colors.amber,
            onPressed: _openResponderLocation,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildActionButton(
            icon: Icons.video_call,
            label: 'Video Call',
            color: Colors.red,
            onPressed: _isCalling ? null : _startVideoCall,
          ),
        ),
      ],
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
}