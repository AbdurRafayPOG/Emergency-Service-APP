import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:public_emergency_app/Features/User/Controllers/session_controller.dart';
import 'package:public_emergency_app/Services/sos_service.dart';
import 'package:public_emergency_app/Models/emergency_model.dart';
import 'package:public_emergency_app/Features/User/Screens/bottom_nav.dart';
import '../../../../Common Widgets/constants.dart';
import 'videoncall.dart';
import 'emergency_status_page.dart';
import 'dart:math';

final sessionController = Get.put(SessionController());

class LiveStreamUser extends StatefulWidget {
  const LiveStreamUser({Key? key}) : super(key: key);

  @override
  State<LiveStreamUser> createState() => _LiveStreamUserState();
}

class _LiveStreamUserState extends State<LiveStreamUser>
    with SingleTickerProviderStateMixin {
  late AnimationController _wobbleController;
  bool _isAnimating = false;
  
  // 🔥 ANTI-SPAM: Flags to prevent multiple SOS presses
  bool _isProcessingSOS = false;
  DateTime? _lastSOSTime;
  static const int _sosCooldownSeconds = 5;
  
  // 🔥 Track if listener has completed initial check
  bool _isListenerInitialized = false;
  
  final SOSService _sosService = SOSService();
  
  StreamSubscription<DatabaseEvent>? _assignedStreamSubscription;
  String? _assignedEmergencyId;
  Map<String, dynamic>? _assignedResponderData;
  bool _hasActiveEmergency = false;
  String? _currentUserId;
  
  // 🔥 Track if we're closing to prevent duplicate navigation
  bool _isClosing = false;

  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    handleLocationPermission();
    _wobbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAssignedEmergencyListener();
    });
  }

  @override
  void dispose() {
    _wobbleController.dispose();
    _assignedStreamSubscription?.cancel();
    super.dispose();
  }

  // ============================================================
  // REAL-TIME LISTENER - Watches 'assigned' node
  // ============================================================
  void _setupAssignedEmergencyListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    _currentUserId = user.uid;

    _assignedStreamSubscription?.cancel();
    
    setState(() {
      _isListenerInitialized = false;
    });
    
    _assignedStreamSubscription = FirebaseDatabase.instance
        .ref('assigned')
        .onValue
        .listen((event) {
      final snapshot = event.snapshot;
      
      // 🔥 If assigned node is empty or emergency removed
      if (snapshot.value == null) {
        // Check if it's in SOS_Done (completed)
        if (_assignedEmergencyId != null) {
          _database.child('SOS_Done').child(_assignedEmergencyId!).get().then((sosSnapshot) {
            if (sosSnapshot.exists) {
              _handleEmergencyCompleted();
            } else {
              _clearEmergencyState();
              // 🔥 Check if we're on status page before showing notification
              final currentRoute = Get.currentRoute;
              final isOnStatusPage = currentRoute.contains('EmergencyStatusPage');
              if (!isOnStatusPage) {
                _showNotification(
                  title: 'Emergency Cancelled',
                  message: 'This emergency is no longer active.',
                  icon: Icons.cancel_rounded,
                  color: Colors.orange,
                );
              }
              if (mounted) {
                setState(() {
                  _isListenerInitialized = true;
                });
              }
            }
          }).catchError((e) {
            _clearEmergencyState();
            final currentRoute = Get.currentRoute;
            final isOnStatusPage = currentRoute.contains('EmergencyStatusPage');
            if (!isOnStatusPage) {
              _showNotification(
                title: 'Emergency Cancelled',
                message: 'This emergency is no longer active.',
                icon: Icons.cancel_rounded,
                color: Colors.orange,
              );
            }
            if (mounted) {
              setState(() {
                _isListenerInitialized = true;
              });
            }
          });
        } else {
          _clearEmergencyState();
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
        
        for (var responderId in data.keys) {
          final responderValue = data[responderId];
          if (responderValue is! Map) continue;
          
          final emergencies = Map<String, dynamic>.from(responderValue as Map);
          
          for (var emergencyId in emergencies.keys) {
            final emergency = Map<String, dynamic>.from(emergencies[emergencyId] as Map);
            final status = emergency['status']?.toString() ?? '';
            
            if (emergency['userID'] == _currentUserId) {
              // 🔥 If emergency completed
              if (status == 'completed') {
                // 🔥 Check if we're on the status page
                final currentRoute = Get.currentRoute;
                final isOnStatusPage = currentRoute.contains('EmergencyStatusPage');
                
                if (!isOnStatusPage) {
                  _handleEmergencyCompleted();
                } else {
                  // Just clear state, status page handles notification
                  _clearEmergencyState();
                  if (mounted) {
                    setState(() {
                      _isListenerInitialized = true;
                    });
                  }
                }
                return;
              }
              
              // 🔥 If emergency cancelled
              if (status == 'cancelled') {
                _clearEmergencyState();
                final currentRoute = Get.currentRoute;
                final isOnStatusPage = currentRoute.contains('EmergencyStatusPage');
                if (!isOnStatusPage) {
                  _showNotification(
                    title: 'Emergency Cancelled',
                    message: 'This emergency is no longer active.',
                    icon: Icons.cancel_rounded,
                    color: Colors.orange,
                  );
                }
                if (mounted) {
                  setState(() {
                    _isListenerInitialized = true;
                  });
                }
                return;
              }
              
              if (status != 'completed' && status != 'cancelled') {
                if (mounted) {
                  setState(() {
                    _hasActiveEmergency = true;
                    _assignedEmergencyId = emergencyId;
                    _assignedResponderData = emergency;
                    _assignedResponderData!['responderId'] = responderId;
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
          _clearEmergencyState();
          if (mounted) {
            setState(() {
              _isListenerInitialized = true;
            });
          }
        }
      } catch (e) {
        _clearEmergencyState();
        if (mounted) {
          setState(() {
            _isListenerInitialized = true;
          });
        }
      }
    }, onError: (error) {
      print("❌ Listener error: $error");
      _clearEmergencyState();
      if (mounted) {
        setState(() {
          _isListenerInitialized = true;
        });
      }
    });
  }

  void _clearEmergencyState() {
    if (mounted) {
      setState(() {
        _hasActiveEmergency = false;
        _assignedEmergencyId = null;
        _assignedResponderData = null;
      });
    }
  }

  // ============================================================
  // 🔥 SHOW NOTIFICATION
  // ============================================================
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
      duration: const Duration(seconds: 4),
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

  // ============================================================
  // 🔥 HANDLE EMERGENCY COMPLETED - Only show if NOT on status page
  // ============================================================
  void _handleEmergencyCompleted() {
    if (_isClosing) return;
    _isClosing = true;
    
    print("✅ Emergency completed - SOS page detected");
    
    // 🔥 Clear emergency state
    _clearEmergencyState();
    
    // 🔥 Check if we're on the status page
    final currentRoute = Get.currentRoute;
    final isOnStatusPage = currentRoute.contains('EmergencyStatusPage');
    
    // Only show notification if we're NOT on the status page
    if (!isOnStatusPage) {
      _showNotification(
        title: 'Emergency Completed',
        message: 'Responder has Marked as done.',
        icon: Icons.check_circle_rounded,
        color: Colors.green,
      );
    } else {
      print("📋 User is on EmergencyStatusPage - SOS page will NOT show notification");
    }
    
    // 🔥 DO NOT navigate away - user stays on SOS page
    _isClosing = false;
    
    // 🔥 Update UI to show "No active emergency" state
    if (mounted) {
      setState(() {
        _isListenerInitialized = true;
      });
    }
  }

  Future<void> handleLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Get.snackbar(
          'Location Disabled',
          'Please enable location services',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        Get.snackbar(
          'Permission Denied',
          'Location permission is required.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Location permission error: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  // ============================================================
  // MANUAL CHECK - For after creating emergency
  // ============================================================
  Future<void> _checkForActiveEmergency() async {
    if (_currentUserId == null) return;
    
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('assigned')
          .get();
      
      if (snapshot.value == null) {
        _clearEmergencyState();
        if (mounted) {
          setState(() {
            _isListenerInitialized = true;
          });
        }
        return;
      }
      
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      
      for (var responderId in data.keys) {
        final responderValue = data[responderId];
        if (responderValue is! Map) continue;
        
        final emergencies = Map<String, dynamic>.from(responderValue as Map);
        
        for (var emergencyId in emergencies.keys) {
          final emergency = Map<String, dynamic>.from(emergencies[emergencyId] as Map);
          final status = emergency['status']?.toString() ?? '';
          
          if (emergency['userID'] == _currentUserId) {
            if (status != 'completed' && status != 'cancelled') {
              if (mounted) {
                setState(() {
                  _hasActiveEmergency = true;
                  _assignedEmergencyId = emergencyId;
                  _assignedResponderData = emergency;
                  _assignedResponderData!['responderId'] = responderId;
                  _isListenerInitialized = true;
                });
              }
              return;
            }
          }
        }
      }
      
      _clearEmergencyState();
      if (mounted) {
        setState(() {
          _isListenerInitialized = true;
        });
      }
    } catch (e) {
      _clearEmergencyState();
      if (mounted) {
        setState(() {
          _isListenerInitialized = true;
        });
      }
    }
  }

  // ============================================================
  // SOS CONFIRMATION DIALOG
  // ============================================================
  Future<void> _showSOSConfirmationDialog() async {
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
                    colors: [Color(0xFF0F4C5C), Color(0xFF1A7A8C)],
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
                        Icons.sos_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Select Emergency Type',
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
              
              _buildEmergencyOption(
                icon: Icons.local_police_rounded,
                label: 'Police',
                color: Colors.blue,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _handleEmergencySelection('Police');
                },
              ),
              const SizedBox(height: 12),
              
              _buildEmergencyOption(
                icon: Icons.fire_extinguisher_rounded,
                label: 'Firefighter',
                color: Colors.orange,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _handleEmergencySelection('Firefighter');
                },
              ),
              const SizedBox(height: 20),
              
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

  Widget _buildEmergencyOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(0.2),
              color.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withOpacity(0.4),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HANDLE EMERGENCY SELECTION - WITH ANTI-SPAM
  // ============================================================
  Future<void> _handleEmergencySelection(String emergencyType) async {
    if (_isProcessingSOS) {
      Get.snackbar(
        'Please Wait',
        'Your SOS request is already being processed...',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    if (_lastSOSTime != null) {
      final elapsed = DateTime.now().difference(_lastSOSTime!);
      if (elapsed.inSeconds < _sosCooldownSeconds) {
        final remaining = _sosCooldownSeconds - elapsed.inSeconds;
        Get.snackbar(
          'Too Fast!',
          'Please wait $remaining seconds before sending another SOS.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 2),
        );
        return;
      }
    }

    if (_hasActiveEmergency) {
      Get.snackbar(
        'Active Emergency',
        'You already have an active emergency. Please wait for responder.',
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
        'Checking for existing emergencies... Please wait.',
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
      _isProcessingSOS = true;
      _lastSOSTime = DateTime.now();
    });

    try {
      String userName = 'Unknown User';
      try {
        final userSnapshot = await FirebaseDatabase.instance
            .ref('Users')
            .child(user.uid)
            .get();
        
        if (userSnapshot.value != null) {
          final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
          userName = userData['UserName']?.toString() ?? 'Unknown User';
        }
      } catch (e) {
        // Ignore
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      Placemark place = placemarks.first;
      String address =
          '${place.street ?? ''}, ${place.subLocality ?? ''}, ${place.subAdministrativeArea ?? ''}, ${place.postalCode ?? ''}';

      Emergency emergency = Emergency(
        userId: user.uid,
        userEmail: user.email ?? '',
        userName: userName,
        userLat: position.latitude,
        userLong: position.longitude,
        address: address,
        emergencyType: emergencyType,
        status: 'pending',
        createdAt: DateTime.now(),
      );

      final result = await _sosService.createEmergency(emergency);

      setState(() {
        _isProcessingSOS = false;
      });

      if (result.success) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _checkForActiveEmergency();
        _showSOSSuccessDialog(result.emergencyId!, result.responderData!);
      } else {
        _showNoResponderAvailableDialog(emergencyType);
      }
    } catch (e) {
      setState(() {
        _isProcessingSOS = false;
      });
      
      Get.snackbar(
        'Error',
        'Failed to send SOS. Please try again.',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
    }
  }

  void _showSOSSuccessDialog(String emergencyId, Map<String, dynamic> responderData) {
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
                'SOS Sent!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${responderData['UserType'] ?? 'Responder'} assigned to you',
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
                        color: Colors.blue.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          (responderData['UserName'] ?? 'R')[0].toUpperCase(),
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
                            responderData['UserName'] ?? 'Unknown Responder',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            responderData['UserType'] ?? 'Responder',
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
                        'En Route',
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

  void _showNoResponderAvailableDialog(String emergencyType) {
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
            Text(
              'No $emergencyType Available',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'All $emergencyType responders are currently busy or unavailable. Please try again later or contact emergency services directly.',
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

  void _navigateToEmergencyStatus(String emergencyId) {
    Get.to(() => EmergencyStatusPage(emergencyId: emergencyId));
  }

  // ============================================================
  // START WOBBLE ANIMATION - WITH ANTI-SPAM
  // ============================================================
  void _startWobbleAnimation() async {
    if (!_isListenerInitialized) {
      Get.snackbar(
        'Loading',
        'Checking for existing emergencies... Please wait.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );
      return;
    }
    
    if (_isAnimating || _isProcessingSOS) {
      return;
    }

    if (_hasActiveEmergency) {
      Get.snackbar(
        'Active Emergency',
        'You already have an active emergency. Please wait for responder.',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    if (_lastSOSTime != null) {
      final elapsed = DateTime.now().difference(_lastSOSTime!);
      if (elapsed.inSeconds < _sosCooldownSeconds) {
        final remaining = _sosCooldownSeconds - elapsed.inSeconds;
        Get.snackbar(
          'Too Fast!',
          'Please wait $remaining seconds before sending another SOS.',
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
    await _showSOSConfirmationDialog();

    _isAnimating = false;
  }

  @override
  Widget build(BuildContext context) {
    bool isButtonDisabled = _hasActiveEmergency || _isProcessingSOS || _isAnimating || !_isListenerInitialized;
    
    String responderType = _assignedResponderData?['type'] ?? 'Responder';
    String userName = _assignedResponderData?['userName'] ?? 'User';
    
    return Scaffold(
      appBar: AppBar(
  backgroundColor: Color(color),
  centerTitle: true,
  automaticallyImplyLeading: false,
  toolbarHeight: 0,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
  ),
  bottom: PreferredSize(
    preferredSize: Size.fromHeight(Get.height * 0.14),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                "assets/logos/emergencyAppLogo.png",
                height: Get.height * 0.07,
              ),
              const SizedBox(height: 4),
              const Text(
                "SOS",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ),
),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🔥 SOS Button with loading indicator
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
                                : Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                            shadowColor: isButtonDisabled 
                                ? Colors.grey.withOpacity(0.5) 
                                : Colors.red.withOpacity(0.5),
                          ),
                          onPressed: isButtonDisabled ? null : _startWobbleAnimation,
                          child: _isProcessingSOS
                              ? const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 4,
                                  ),
                                )
                              : Text(
                                  _hasActiveEmergency ? "ACTIVE" : "SOS",
                                  style: TextStyle(
                                    fontSize: _hasActiveEmergency ? 32 : 48,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: _hasActiveEmergency ? 4 : 8,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  if (!_isListenerInitialized && !_hasActiveEmergency)
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
              SizedBox(height: Get.height * 0.06),
              
              if (!_hasActiveEmergency && _isListenerInitialized)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Color(color).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Color(color).withOpacity(0.15),
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
                          "Press the button to send your location to the rescue headquarters.",
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
              
              if (!_isListenerInitialized && !_hasActiveEmergency)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
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
                          "Checking for existing emergencies...",
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
              
              if (_hasActiveEmergency)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: GestureDetector(
                    onTap: () {
                      if (_assignedEmergencyId != null) {
                        _navigateToEmergencyStatus(_assignedEmergencyId!);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF43A047),
                            Color(0xFF2E7D32),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.4),
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
                              Icons.emergency_rounded,
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
                                  'View Active Emergency',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$responderType En Route',
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
    );
  }

  Future<void> saveCurrentLocation() async {
    // Kept for compatibility
  }
}