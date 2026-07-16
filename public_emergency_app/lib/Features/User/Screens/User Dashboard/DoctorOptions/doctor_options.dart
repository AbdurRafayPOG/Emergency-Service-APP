import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';
import 'package:public_emergency_app/Features/User/Controllers/session_controller.dart';
import 'package:public_emergency_app/Services/doctor_service.dart';
import 'package:public_emergency_app/Features/Doctor/doctor_dashboard.dart';
import 'package:public_emergency_app/Features/User/Screens/User%20Dashboard/DoctorOptions/doctor_list.dart';
import 'active_doctor_status.dart';
import 'dart:math';

final sessionController = Get.put(SessionController());

class DoctorOptions extends StatefulWidget {
  const DoctorOptions({Key? key}) : super(key: key);

  @override
  State<DoctorOptions> createState() => _DoctorOptionsState();
}

class _DoctorOptionsState extends State<DoctorOptions>
    with SingleTickerProviderStateMixin {
  late AnimationController _wobbleController;
  bool _isAnimating = false;

  bool _isProcessingDoctor = false;
  DateTime? _lastDoctorTime;
  static const int _doctorCooldownSeconds = 5;

  bool _isListenerInitialized = false;

  final DoctorService _doctorService = DoctorService();

  StreamSubscription<DatabaseEvent>? _assignedStreamSubscription;
  String? _assignedRequestId;
  Map<String, dynamic>? _assignedDoctorData;
  bool _hasActiveDoctor = false;
  String? _currentUserId;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _wobbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupDoctorListener();
    });
  }

  @override
  void dispose() {
    _wobbleController.dispose();
    _assignedStreamSubscription?.cancel();
    super.dispose();
  }

  void _setupDoctorListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _currentUserId = user.uid;

    _assignedStreamSubscription?.cancel();

    setState(() {
      _isListenerInitialized = false;
    });

    _assignedStreamSubscription = FirebaseDatabase.instance
        .ref('assigned_doctors')
        .onValue
        .listen((event) {
      final snapshot = event.snapshot;

      if (snapshot.value == null) {
        if (_assignedRequestId != null) {
          _database.child('Doctor_Done').child(_assignedRequestId!).get().then((doneSnapshot) {
            if (doneSnapshot.exists) {
              _handleDoctorCompleted();
            } else {
              _showDoctorUnavailableNotification(_assignedDoctorData?['doctorName'] ?? 'Doctor');
              _clearDoctorState();
              if (mounted) {
                setState(() {
                  _isListenerInitialized = true;
                });
              }
            }
          }).catchError((e) {
            _showDoctorUnavailableNotification(_assignedDoctorData?['doctorName'] ?? 'Doctor');
            _clearDoctorState();
            if (mounted) {
              setState(() {
                _isListenerInitialized = true;
              });
            }
          });
        } else {
          _clearDoctorState();
          if (mounted) {
            setState(() {
              _isListenerInitialized = true;
            });
          }
        }
        return;
      }

      try {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        bool found = false;

        for (var doctorId in data.keys) {
          final doctorValue = data[doctorId];
          if (doctorValue is! Map) continue;

          final requests = Map<String, dynamic>.from(doctorValue as Map);

          for (var requestId in requests.keys) {
            final request = Map<String, dynamic>.from(requests[requestId] as Map);
            final status = request['status']?.toString() ?? '';

            if (request['userId'] == _currentUserId) {
              if (status != 'completed' && status != 'cancelled') {
                if (mounted) {
                  setState(() {
                    _hasActiveDoctor = true;
                    _assignedRequestId = requestId;
                    _assignedDoctorData = request;
                    _assignedDoctorData!['doctorId'] = doctorId;
                    _assignedDoctorData!['profession'] = request['profession'] ?? 'Doctor';
                    _isListenerInitialized = true;
                  });
                }
                found = true;
                break;
              }
            }
          }
          if (found) break;
        }

        if (!found) {
          if (_assignedRequestId != null) {
            _database.child('Doctor_Done').child(_assignedRequestId!).get().then((doneSnapshot) {
              if (doneSnapshot.exists) {
                _handleDoctorCompleted();
              } else {
                _showDoctorUnavailableNotification(_assignedDoctorData?['doctorName'] ?? 'Doctor');
                _clearDoctorState();
                if (mounted) {
                  setState(() {
                    _isListenerInitialized = true;
                  });
                }
              }
            }).catchError((e) {
              _showDoctorUnavailableNotification(_assignedDoctorData?['doctorName'] ?? 'Doctor');
              _clearDoctorState();
              if (mounted) {
                setState(() {
                  _isListenerInitialized = true;
                });
              }
            });
          } else {
            _clearDoctorState();
            if (mounted) {
              setState(() {
                _isListenerInitialized = true;
              });
            }
          }
        }
      } catch (e) {
        _clearDoctorState();
        if (mounted) {
          setState(() {
            _isListenerInitialized = true;
          });
        }
      }
    });
  }

  void _clearDoctorState() {
    if (mounted) {
      setState(() {
        _hasActiveDoctor = false;
        _assignedRequestId = null;
        _assignedDoctorData = null;
      });
    }
  }

  // ============================================================
  // 🔥 DOCTOR COMPLETED - Shows Snackbar (SAME AS ACTIVE DOCTOR)
  // ============================================================
  void _handleDoctorCompleted() {
    String doctorName = _assignedDoctorData?['doctorName'] ?? 'Doctor';

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
                      'Session has been ended by Dr. $doctorName',
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
    } else {
      print("📋 Notification already shown - skipping duplicate in DoctorOptions");
    }

    _clearDoctorState();

    if (mounted) {
      setState(() {
        _isListenerInitialized = true;
      });
    }
  }

  void _showDoctorUnavailableNotification(String doctorName) {
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
                    'Dr. $doctorName is no longer available',
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

  void _startWobbleAnimation() async {
    if (!_isListenerInitialized) {
      Get.snackbar(
        'Loading',
        'Checking for existing doctor requests... Please wait.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    if (_isAnimating || _isProcessingDoctor) {
      return;
    }

    if (_hasActiveDoctor) {
      Get.snackbar(
        'Active Doctor Session',
        'You already have an active doctor request. Please wait.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    if (_lastDoctorTime != null) {
      final elapsed = DateTime.now().difference(_lastDoctorTime!);
      if (elapsed.inSeconds < _doctorCooldownSeconds) {
        final remaining = _doctorCooldownSeconds - elapsed.inSeconds;
        Get.snackbar(
          'Too Fast!',
          'Please wait $remaining seconds before requesting again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 2),
        );
        return;
      }
    }

    _isAnimating = true;

    _wobbleController.reset();
    await _wobbleController.forward();
    await _showDoctorConfirmationDialog();

    _isAnimating = false;
  }

  Future<void> _showDoctorConfirmationDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TweenAnimationBuilder(
        tween: Tween<double>(begin: 0.5, end: 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Opacity(
              opacity: value,
              child: child,
            ),
          );
        },
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F4C5C), Color(0xFF00BCD4)],
                  ),
                  borderRadius: BorderRadius.circular(16),
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
                        Icons.medical_services_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Request a Doctor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'A doctor will be assigned to you shortly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _handleDoctorRequest();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Confirm Request',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleDoctorRequest() async {
    if (_isProcessingDoctor) {
      Get.snackbar(
        'Please Wait',
        'Your request is already being processed...',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    if (_lastDoctorTime != null) {
      final elapsed = DateTime.now().difference(_lastDoctorTime!);
      if (elapsed.inSeconds < _doctorCooldownSeconds) {
        final remaining = _doctorCooldownSeconds - elapsed.inSeconds;
        Get.snackbar(
          'Too Fast!',
          'Please wait $remaining seconds before requesting again.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 2),
        );
        return;
      }
    }

    if (_hasActiveDoctor) {
      Get.snackbar(
        'Active Doctor',
        'You already have an active doctor request. Please wait.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    if (!_isListenerInitialized) {
      Get.snackbar(
        'Loading',
        'Checking for existing doctor requests... Please wait.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Get.snackbar('Error', 'User not logged in');
      return;
    }

    setState(() {
      _isProcessingDoctor = true;
      _lastDoctorTime = DateTime.now();
    });

    try {
      final result = await _doctorService.createDoctorRequest();

      setState(() {
        _isProcessingDoctor = false;
      });

      if (result['success'] && result['assigned'] == true) {
        await Future.delayed(const Duration(milliseconds: 500));
        _showDoctorSuccessDialog(
          doctorName: result['doctorName'] ?? 'Doctor',
          profession: result['profession'] ?? 'Doctor',
        );
      } else {
        _showNoDoctorAvailableDialog();
      }
    } catch (e) {
      setState(() {
        _isProcessingDoctor = false;
      });

      Get.snackbar(
        'Error',
        'Failed to request doctor. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
    }
  }

  void _showDoctorSuccessDialog({
    required String doctorName,
    required String profession,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TweenAnimationBuilder(
        tween: Tween<double>(begin: 0.5, end: 1.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Opacity(
              opacity: value,
              child: child,
            ),
          );
        },
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.green,
                  size: 60,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Doctor Assigned!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Dr. $doctorName has been assigned to you',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BCD4).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          doctorName.isNotEmpty ? doctorName[0].toUpperCase() : 'D',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dr. $doctorName',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            profession,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Assigned',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNoDoctorAvailableDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 60,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Doctor Available',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'All doctors are currently busy or unavailable. Please try again later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDoctorDashboard() {
    Get.to(() => ActiveDoctorStatus(
          doctorName: _assignedDoctorData?['doctorName'] ?? 'Doctor',
          profession: _assignedDoctorData?['profession'] ?? 'Doctor',
          doctorId: _assignedDoctorData?['doctorId']?.toString(),
          requestId: _assignedRequestId,
        ));
  }

  void _navigateToDoctorList() {
    Get.to(() => const DoctorListPage());
  }

  @override
  Widget build(BuildContext context) {
    bool isButtonDisabled = _hasActiveDoctor || _isProcessingDoctor || _isAnimating || !_isListenerInitialized;

    String doctorName = _assignedDoctorData?['doctorName'] ?? 'Doctor';
    String profession = _assignedDoctorData?['profession'] ?? 'Doctor';

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
                      "assets/logos/emergencyAppLogo.png",
                      height: iconHeight,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Doctor Options",
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
                    child: const Center(
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Color(0xFF0F4C5C),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 36, 112, 131),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _navigateToDoctorList,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
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
                              Icons.medical_services_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Doctor Referrals',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'View external doctors and specialists',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: _wobbleController,
                          builder: (context, child) {
                            final double value = _wobbleController.value;
                            final double wobbleAngle = sin(value * 4 * 3.14159) * 0.08 * (1 - value);
                            final double scaleValue = 1.0 + (0.05 * (1 - value));

                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..rotateZ(wobbleAngle)
                                ..scale(scaleValue),
                              child: child,
                            );
                          },
                          child: TweenAnimationBuilder(
                            tween: Tween<double>(begin: 0.8, end: 1.0),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Transform.scale(
                                scale: value,
                                child: child,
                              );
                            },
                            child: SizedBox(
                              width: Get.width * 0.8,
                              height: Get.height * 0.25,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  elevation: 20,
                                  backgroundColor: isButtonDisabled
                                      ? Colors.grey
                                      : const Color(0xFF00BCD4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                  shadowColor: isButtonDisabled
                                      ? Colors.grey.withOpacity(0.5)
                                      : const Color(0xFF00BCD4).withOpacity(0.5),
                                ),
                                onPressed: isButtonDisabled ? null : _startWobbleAnimation,
                                child: _isProcessingDoctor
                                    ? const SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 4,
                                        ),
                                      )
                                    : Text(
                                        _hasActiveDoctor ? "ACTIVE" : "Onboard Doctor",
                                        style: TextStyle(
                                          fontSize: _hasActiveDoctor ? 32 : 26,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: _hasActiveDoctor ? 4 : 1,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                        if (!_isListenerInitialized && !_hasActiveDoctor)
                          Positioned(
                            bottom: -30,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Checking...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    if (!_hasActiveDoctor && _isListenerInitialized)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F4C5C).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF0F4C5C).withOpacity(0.15),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.info_outline_rounded,
                                color: Colors.red,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                "Press the button to request a doctor. A doctor will be assigned shortly. Available during office hours only.",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!_isListenerInitialized && !_hasActiveDoctor)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.orange.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.hourglass_top_rounded,
                                color: Colors.orange,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                "Checking for existing doctor requests...",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_hasActiveDoctor)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: _navigateToDoctorDashboard,
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF00BCD4),
                                  Color(0xFF00838F),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00BCD4).withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.medical_services_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'View Active Doctor',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Dr. $doctorName ($profession)',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}