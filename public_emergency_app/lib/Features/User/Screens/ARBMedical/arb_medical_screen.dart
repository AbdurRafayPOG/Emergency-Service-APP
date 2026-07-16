import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';

class ArbMedicalScreen extends StatefulWidget {
  const ArbMedicalScreen({Key? key}) : super(key: key);

  @override
  State<ArbMedicalScreen> createState() => _ArbMedicalScreenState();
}

class _ArbMedicalScreenState extends State<ArbMedicalScreen> {
  bool _aboutExpanded = false;
  bool _certificationExpanded = false;
  final Set<int> _expandedDoctors = {};

  static const String _arbLat = '24.8756';
  static const String _arbLng = '67.0671';

  Future<void> _openMap() async {
    const String query = 'Plot+77+K,+ARB+Medical+Center,+Block+6+PECHS,+Karachi';
    final String googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=$query';
    final String appleMapsUrl = 'https://maps.apple.com/?q=$query';

    if (Platform.isAndroid) {
      if (await canLaunchUrl(Uri.parse(googleMapsUrl))) {
        await launchUrl(Uri.parse(googleMapsUrl),
            mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar('Error', 'Could not open maps',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
    } else {
      if (await canLaunchUrl(Uri.parse(googleMapsUrl))) {
        await launchUrl(Uri.parse(googleMapsUrl),
            mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(Uri.parse(appleMapsUrl))) {
        await launchUrl(Uri.parse(appleMapsUrl),
            mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar('Error', 'Could not open maps',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
    }
  }

  Future<void> _makeCall(String number) async {
    final Uri url = Uri.parse('tel:$number');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      Get.snackbar('Error', 'Could not make call',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  Future<void> _openDonation() async {
    final Uri uri = Uri(
      scheme: 'https',
      host: 'arbmedical.org.pk',
      path: '/product/donation/',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      try {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (e2) {
        Get.snackbar(
          'Error',
          'Could not open browser. Please visit arbmedical.org.pk manually.',
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  void _showCallBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Call ARB Medical Centre',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFC0392B),
                ),
              ),
              const SizedBox(height: 16),
              _callNumberTile('021-34527777'),
              const Divider(),
              _callNumberTile('021-34532222'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _callNumberTile(String number) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFC0392B).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.phone, color: Color(0xFFC0392B)),
      ),
      title: Text(
        number,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
      onTap: () {
        Navigator.pop(context);
        _makeCall(number.replaceAll('-', ''));
      },
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  // ─── ABOUT SECTION ───────────────────────────────────────────────────────────
  Widget _buildAboutSection() {
    return _sectionCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _aboutExpanded = !_aboutExpanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC0392B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.info_outline,
                        color: Color(0xFFC0392B)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'About ARB Medical Centre',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFC0392B),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _aboutExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: Color(0xFFC0392B)),
                  ),
                ],
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  child: _aboutExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),
                            const Divider(),
                            const SizedBox(height: 10),
                            const Text(
                              'The ARB Medical Centre, established by the Haseen Habib Foundation Trust and named in honor of the late Hafiz Ateeq-Ur-Rahman Barry, the esteemed founder of Haseen Habib with "ARB" serving as an abbreviation of his revered name, was officially inaugurated on December 2, 2024. This state-of-the-art facility is poised to become a valuable healthcare resource for surrounding communities, particularly in the lower localities adjacent to P.E.C.H.S, including Umar Colony, Baloch Colony, Mahmoodabad, Railway Line, Chanesar Halt, Azam Basti, and Manzoor Colony, among others.',
                              textAlign: TextAlign.justify,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.6,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── CERTIFICATE SECTION ──────────────────────────────────────────────────
  Widget _buildCertificationSection() {
    return _sectionCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _certificationExpanded = !_certificationExpanded),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC0392B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.verified_rounded,
                        color: Color(0xFFC0392B)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Certificate',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFC0392B),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _certificationExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: Color(0xFFC0392B)),
                  ),
                ],
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  child: _certificationExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 14),
                            const Divider(),
                            const SizedBox(height: 12),
                            
                            // Certificate 1
                            GestureDetector(
                              onTap: () => _showCertificationImage('assets/arb/certificate1.png'),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFC0392B).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.verified_rounded,
                                        color: Color(0xFFC0392B),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Certificate Technical Assistance',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 10),
                            
                            // Certificate 2
                            GestureDetector(
                              onTap: () => _showCertificationImage('assets/arb/certificate2.png'),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFC0392B).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.verified_rounded,
                                        color: Color(0xFFC0392B),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Certificate Authorization',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 4),
                            
                            // Tap instruction
                            const Text(
                              'Tap on any certificate to view',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SHOW CERTIFICATION IMAGE FULL SCREEN ──────────────────────────────────
  void _showCertificationImage(String imagePath) {
    Get.to(
      () => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 30),
            onPressed: () => Get.back(),
          ),
          title: const Text(
            'Certificate',
            style: TextStyle(color: Colors.white),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 3.0,
            child: Image.asset(
              imagePath,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.broken_image_rounded,
                      size: 80,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Image not found',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 16,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      fullscreenDialog: true,
    );
  }

  // ─── DOCTOR TILE ─────────────────────────────────────────────────────────────
  Widget _buildDoctorTile({
    required int index,
    required String role,
    required String name,
    required String days,
    required String time,
  }) {
    final bool isExpanded = _expandedDoctors.contains(index);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedDoctors.remove(index);
          } else {
            _expandedDoctors.add(index);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isExpanded ? const Color(0xFF0A3545) : const Color(0xFF0F4C5C),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isExpanded
              ? [
                  BoxShadow(
                    color: const Color(0xFF0F4C5C).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.medical_services_rounded,
                      color: Colors.white70, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(role,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white60, size: 20),
                  ),
                ],
              ),
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: isExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            const Divider(color: Colors.white24),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today,
                                    color: Colors.white60, size: 13),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(days,
                                      style: const TextStyle(
                                          color: Colors.white60, fontSize: 13)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time,
                                    color: Colors.white60, size: 13),
                                const SizedBox(width: 6),
                                Text(time,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 13)),
                              ],
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double appBarHeight = Get.height * 0.1 + kToolbarHeight;
    final double iconHeight = Get.height * 0.12;
    final double iconCenterY = appBarHeight / 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarHeight),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFFC0392B),
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
                      'assets/arb/arb_icon0.png',
                      height: iconHeight,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'ARB Medical Centre',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                top: iconCenterY - 20,
                child: GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Color(0xFFC0392B),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// ABOUT SECTION
            _buildAboutSection(),

            /// LOCATION
            _sectionCard(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _openMap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC0392B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.location_on,
                            color: Color(0xFFC0392B)),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Location',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),

            /// CALL US
            _sectionCard(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _showCallBottomSheet,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC0392B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.call,
                            color: Color(0xFFC0392B)),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Call Us',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),

            /// ONLINE DONATION
            _sectionCard(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _openDonation,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC0392B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.favorite,
                            color: Color(0xFFC0392B)),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Online Donation',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),

            /// TIMING SECTION
            _sectionCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC0392B).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.access_time,
                              color: Color(0xFFC0392B)),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Timing',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              Text(
                                'Monday to Saturday • 9:00 AM – 5:00 PM',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 10),
                    const Text(
                      'Clinic Timings (OPD)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F4C5C),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDoctorTile(
                      index: 0,
                      role: 'General Surgeon + Urologist',
                      name: 'Dr. Muhammad Tufail Bawa',
                      days: 'Saturday',
                      time: '10:00 AM to 11:00 AM',
                    ),
                    _buildDoctorTile(
                      index: 1,
                      role: 'Pediatrician (Children\'s Doctor)',
                      name: 'Dr. Sana Fateh',
                      days: 'Monday, Wednesday & Saturday',
                      time: '2:30 PM to 4:30 PM',
                    ),
                    _buildDoctorTile(
                      index: 2,
                      role: 'Psychologist (Psychotherapist)',
                      name: 'Faiza Aslam',
                      days: 'Thursday',
                      time: '10:00 AM to 1:00 PM',
                    ),
                  ],
                ),
              ),
            ),

            /// ✅ CERTIFICATION SECTION - Added after Timing
            _buildCertificationSection(),

            /// FOOTER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Image.asset('assets/arb/arb_icon.png', height: 90),
                  const SizedBox(height: 14),
                  const Text(
                    'In honor of the late\nHafiz Ateeq-Ur-Rahman Barry',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC0392B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'The esteemed founder of Haseen Habib Foundation Trust',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey, height: 1.5),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}