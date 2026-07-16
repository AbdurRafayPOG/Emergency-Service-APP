import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';
import 'manage_responders.dart';
import 'manage_doctors.dart';
import 'users_screen.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({Key? key}) : super(key: key);

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final String firebaseDatabaseUrl =
      'https://emergencyresponse-0xyvwt-default-rtdb.asia-southeast1.firebasedatabase.app';
  
  // Stats variables
  int _totalResponders = 0;
  int _policeCount = 0;
  int _firefighterCount = 0;
  int _totalDoctors = 0;
  int _totalUsers = 0;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: firebaseDatabaseUrl,
      );
      
      final respondersRef = db.ref('Responders');
      final doctorsRef = db.ref('Doctors');
      final usersRef = db.ref('Users');
      
      final results = await Future.wait([
        respondersRef.once(),
        doctorsRef.once(),
        usersRef.once(),
      ]);

      final respondersSnapshot = results[0];
      final doctorsSnapshot = results[1];
      final usersSnapshot = results[2];

      // Count Responders
      int policeCount = 0;
      int firefighterCount = 0;
      if (respondersSnapshot.snapshot.value != null) {
        final respondersData = Map<dynamic, dynamic>.from(respondersSnapshot.snapshot.value as Map);
        for (var entry in respondersData.entries) {
          final data = Map<dynamic, dynamic>.from(entry.value);
          final userType = data['UserType']?.toString() ?? '';
          if (userType == 'Police') {
            policeCount++;
          } else if (userType == 'FireFighter') {
            firefighterCount++;
          }
        }
      }

      // Count Doctors
      int doctorCount = 0;
      if (doctorsSnapshot.snapshot.value != null) {
        final doctorsData = Map<dynamic, dynamic>.from(doctorsSnapshot.snapshot.value as Map);
        doctorCount = doctorsData.length;
      }

      // Count Users
      int userCount = 0;
      if (usersSnapshot.snapshot.value != null) {
        final usersData = Map<dynamic, dynamic>.from(usersSnapshot.snapshot.value as Map);
        userCount = usersData.length;
      }

      setState(() {
        _policeCount = policeCount;
        _firefighterCount = firefighterCount;
        _totalResponders = policeCount + firefighterCount;
        _totalDoctors = doctorCount;
        _totalUsers = userCount;
        _isLoading = false;
      });

    } catch (e) {
      print('❌ Error loading staff stats: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading stats';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Color(color),
        centerTitle: true,
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
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
                      padding: const EdgeInsets.only(top: 0),
                      child: Image.asset(
                        'assets/logos/emergencyAppLogo.png',
                        height: Get.height * 0.07,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Management',
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
                    'Loading staff data...',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : Container(
              padding: const EdgeInsets.all(16),
              height: Get.height * 0.75,
              child: Column(
                children: [
                  // Row 1: Responders + Police + FireFighter
                  Expanded(
                    child: _buildManagementCard(
                      title: 'Responders',
                      subtitle: 'Police & FireFighters',
                      totalCount: _totalResponders,
                      icon: Icons.shield_rounded,
                      gradientColors: [
                        Colors.blue.shade600,
                        Colors.blue.shade800,
                      ],
                      lightColor: Colors.blue.shade50,
                      borderColor: Colors.blue.shade200,
                      onTap: () => Get.to(() => const ManageResponders()),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSubStatCard(
                              label: 'Police',
                              value: _policeCount.toString(),
                              icon: Icons.local_police_rounded,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSubStatCard(
                              label: 'FireFighter',
                              value: _firefighterCount.toString(),
                              icon: Icons.fire_truck_rounded,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Row 2: Doctors
                  Expanded(
                    child: _buildManagementCard(
                      title: 'Doctors',
                      subtitle: 'Medical professionals',
                      totalCount: _totalDoctors,
                      icon: Icons.medical_services_rounded,
                      gradientColors: [
                        const Color(0xFF0D8F6F),
                        const Color(0xFF0D8F6F).withOpacity(0.7),
                      ],
                      lightColor: const Color(0xFFE8F5F0),
                      borderColor: const Color(0xFF0D8F6F).withOpacity(0.3),
                      onTap: () => Get.to(() => const ManageDoctors()),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSubStatCard(
                              label: 'Total',
                              value: _totalDoctors.toString(),
                              icon: Icons.medical_services_rounded,
                              color: const Color(0xFF0D8F6F),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Row 3: Users
                  Expanded(
                    child: _buildManagementCard(
                      title: 'Users',
                      subtitle: 'Registered app users',
                      totalCount: _totalUsers,
                      icon: Icons.people_alt_rounded,
                      gradientColors: [
                        const Color(0xFF0F4C5C),
                        const Color(0xFF1A7A8C),
                      ],
                      lightColor: const Color(0xFF0F4C5C).withOpacity(0.08),
                      borderColor: const Color(0xFF0F4C5C).withOpacity(0.2),
                      onTap: () => Get.to(() => const UsersScreen()),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildSubStatCard(
                              label: 'Total',
                              value: _totalUsers.toString(),
                              icon: Icons.people_alt_rounded,
                              color: const Color(0xFF0F4C5C),
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

  // ============================================================
  // MANAGEMENT CARD WIDGET
  // ============================================================
  Widget _buildManagementCard({
    required String title,
    required String subtitle,
    required int totalCount,
    required IconData icon,
    required List<Color> gradientColors,
    required Color lightColor,
    required Color borderColor,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            lightColor,
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: gradientColors.first.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // Total badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradientColors,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  totalCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          
          // Stats Row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: child,
          ),
          
          // Manage/View Button
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    title == 'Users' ? Icons.visibility_rounded : Icons.add_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title == 'Users' ? 'View Users' : 'Manage $title',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUB STAT CARD WIDGET
  // ============================================================
  Widget _buildSubStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}