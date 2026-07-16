import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';
import 'package:public_emergency_app/Features/Login/login_screen.dart';
import 'package:public_emergency_app/Features/Admin/Records/responder_history.dart';
import 'package:public_emergency_app/Features/Admin/Records/docter_history.dart';
import 'package:firebase_core/firebase_core.dart';

class EmergenciesScreen extends StatefulWidget {
  const EmergenciesScreen({Key? key}) : super(key: key);

  @override
  State<EmergenciesScreen> createState() => _EmergenciesScreenState();
}

class _EmergenciesScreenState extends State<EmergenciesScreen> {
  // ============================================================
  // DATABASE REFERENCES
  // ============================================================
  late DatabaseReference sosDoneRef;
  late DatabaseReference assignedRef;
  late DatabaseReference doctorDoneRef;
  late DatabaseReference assignedDoctorsRef;  // ✅ FIXED: Use assigned_doctors
  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app';
  
  // ============================================================
  // STATS VARIABLES
  // ============================================================
  // Responder Stats (Police + Firefighter)
  int _totalResponderRecords = 0;
  int _activeResponderEmergencies = 0;
  int _completedResponderEmergencies = 0;
  
  // Doctor Stats
  int _totalDoctorRecords = 0;
  int _activeDoctorRequests = 0;
  int _completedDoctorRequests = 0;
  
  bool _isLoading = true;
  String _errorMessage = '';

  // ============================================================
  // INIT STATE
  // ============================================================
  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  // ============================================================
  // INITIALIZE DATABASE
  // ============================================================
  Future<void> _initializeDatabase() async {
    try {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      );
      sosDoneRef = db.ref().child('SOS_Done');
      assignedRef = db.ref().child('assigned');
      doctorDoneRef = db.ref().child('Doctor_Done');
      assignedDoctorsRef = db.ref().child('assigned_doctors');  // ✅ FIXED
      
      await _loadStats();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error initializing database: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading stats';
      });
    }
  }

  // ============================================================
  // ✅ LOAD REAL STATS FROM FIREBASE
  // ============================================================
  Future<void> _loadStats() async {
    try {
      print('=== LOADING ADMIN STATS ===');
      
      final results = await Future.wait([
        sosDoneRef.once(),
        assignedRef.once(),
        doctorDoneRef.once(),
        assignedDoctorsRef.once(),  // ✅ FIXED
      ]);

      final sosDoneSnapshot = results[0];
      final assignedSnapshot = results[1];
      final doctorDoneSnapshot = results[2];
      final assignedDoctorsSnapshot = results[3];  // ✅ FIXED

      // ============================================================
      // RESPONDER STATS (Police + Firefighter)
      // ============================================================
      
      // Completed Responder Emergencies (SOS_Done)
      int completedResponderCount = 0;
      if (sosDoneSnapshot.snapshot.value != null) {
        final sosDoneData = Map<dynamic, dynamic>.from(sosDoneSnapshot.snapshot.value as Map);
        completedResponderCount = sosDoneData.length;
        print('📊 Completed Responder emergencies: $completedResponderCount');
      }

      // Active Responder Emergencies (assigned)
      int activeResponderCount = 0;
      if (assignedSnapshot.snapshot.value != null) {
        final assignedData = Map<dynamic, dynamic>.from(assignedSnapshot.snapshot.value as Map);
        
        for (var responderEntry in assignedData.entries) {
          final responderData = Map<dynamic, dynamic>.from(responderEntry.value);
          for (var emergencyEntry in responderData.entries) {
            final emergencyData = Map<dynamic, dynamic>.from(emergencyEntry.value);
            final status = emergencyData['status']?.toString() ?? '';
            
            if (status != 'completed') {
              activeResponderCount++;
            }
          }
        }
        print('📊 Active Responder emergencies: $activeResponderCount');
      }

      // ============================================================
      // DOCTOR STATS (Doctor_Done + assigned_doctors)
      // ============================================================
      
      // ✅ Completed Doctor Requests (Doctor_Done)
      int completedDoctorCount = 0;
      if (doctorDoneSnapshot.snapshot.value != null) {
        final doctorDoneData = Map<dynamic, dynamic>.from(doctorDoneSnapshot.snapshot.value as Map);
        completedDoctorCount = doctorDoneData.length;
        print('📊 Completed Doctor requests: $completedDoctorCount');
      }
      
      // ✅ Active Doctor Requests (assigned_doctors)
      int activeDoctorCount = 0;
      if (assignedDoctorsSnapshot.snapshot.value != null) {
        final assignedDoctorsData = Map<dynamic, dynamic>.from(assignedDoctorsSnapshot.snapshot.value as Map);
        
        for (var doctorEntry in assignedDoctorsData.entries) {
          final doctorData = Map<dynamic, dynamic>.from(doctorEntry.value);
          for (var requestEntry in doctorData.entries) {
            final requestData = Map<dynamic, dynamic>.from(requestEntry.value);
            final status = requestData['status']?.toString() ?? 'assigned';
            
            // Only count if status is not 'completed' or 'cancelled'
            if (status != 'completed' && status != 'cancelled') {
              activeDoctorCount++;
            }
          }
        }
        print('📊 Active Doctor requests: $activeDoctorCount');
      }

      // Update Responder Stats
      _completedResponderEmergencies = completedResponderCount;
      _activeResponderEmergencies = activeResponderCount;
      _totalResponderRecords = completedResponderCount + activeResponderCount;
      
      // Update Doctor Stats
      _completedDoctorRequests = completedDoctorCount;
      _activeDoctorRequests = activeDoctorCount;
      _totalDoctorRecords = completedDoctorCount + activeDoctorCount;

      print('📊 Total Responder Records: $_totalResponderRecords');
      print('📊 Total Doctor Records: $_totalDoctorRecords');
      print('📊 Active Doctor Requests: $_activeDoctorRequests');
      print('📊 Completed Doctor Requests: $_completedDoctorRequests');

      setState(() {});
      
    } catch (e) {
      print('❌ Error loading stats: $e');
      setState(() {
        _errorMessage = 'Error loading stats: $e';
      });
    }
  }

  // ============================================================
  // LOGOUT DIALOG
  // ============================================================
  void _showLogoutDialog() {
    Get.dialog(
      Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.red.shade500,
                      Colors.red.shade700,
                    ],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Logout?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Are you sure you want to log out?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Get.back(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Get.back();
                        FirebaseAuth.instance.signOut().then((_) {
                          Get.offAll(() => const LoginScreen());
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F4C5C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text(
                        'Yes, Logout',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  // ============================================================
  // NAVIGATION FUNCTIONS
  // ============================================================
  void _navigateToResponderHistory() {
    Get.to(() => const ResponderHistoryScreen());
  }

  void _navigateToDocterHistory() {
    Get.to(() => const DocterHistoryScreen());
  }

  // ============================================================
  // BUILD METHOD
  // ============================================================
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
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(Get.height * 0.15),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 0),
                      child: Image.asset(
                        'assets/logos/emergencyAppLogo.png',
                        height: Get.height * 0.07,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Admin Dashboard',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              Positioned(
                right: 16,
                top: 6,
                child: GestureDetector(
                  onTap: _showLogoutDialog,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.red,
                          Colors.redAccent,
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                        size: 22,
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
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F4C5C)),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading dashboard...',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ============================================================
                  // RESPONDER SECTION
                  // ============================================================
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF0F4C5C).withOpacity(0.08),
                          const Color(0xFF1A7A8C).withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF0F4C5C).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Responder Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF0F4C5C),
                                    const Color(0xFF1A7A8C),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.people_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Responders',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F4C5C),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Responder Stats Cards
                        Row(
                          children: [
                            // Total Records
                            Expanded(
                              child: _buildStatsCard(
                                icon: Icons.history_rounded,
                                label: 'Total Records',
                                value: _totalResponderRecords.toString(),
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Active
                            Expanded(
                              child: _buildStatsCard(
                                icon: Icons.pending_actions,
                                label: 'Active',
                                value: _activeResponderEmergencies.toString(),
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Completed
                            Expanded(
                              child: _buildStatsCard(
                                icon: Icons.check_circle,
                                label: 'Completed',
                                value: _completedResponderEmergencies.toString(),
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 14),
                        
                        // View History Button
                        GestureDetector(
                          onTap: _navigateToResponderHistory,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF0F4C5C),
                                  const Color(0xFF1A7A8C),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'View Responder History',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // ============================================================
                  // DOCTOR SECTION
                  // ============================================================
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF0D8F6F).withOpacity(0.08),
                          const Color(0xFF0D8F6F).withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF0D8F6F).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Doctor Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF0D8F6F),
                                    const Color(0xFF0D8F6F).withOpacity(0.7),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.medical_services_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Doctors',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D8F6F),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Doctor Stats Cards
                        Row(
                          children: [
                            // Total Records
                            Expanded(
                              child: _buildStatsCard(
                                icon: Icons.history_rounded,
                                label: 'Total Records',
                                value: _totalDoctorRecords.toString(),
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Active
                            Expanded(
                              child: _buildStatsCard(
                                icon: Icons.pending_actions,
                                label: 'Active',
                                value: _activeDoctorRequests.toString(),
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Completed
                            Expanded(
                              child: _buildStatsCard(
                                icon: Icons.check_circle,
                                label: 'Completed',
                                value: _completedDoctorRequests.toString(),
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 14),
                        
                        // View History Button
                        GestureDetector(
                          onTap: _navigateToDocterHistory,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF0D8F6F),
                                  const Color(0xFF0D8F6F).withOpacity(0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'View Doctor History',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // STATS CARD WIDGET
  // ============================================================
  Widget _buildStatsCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}