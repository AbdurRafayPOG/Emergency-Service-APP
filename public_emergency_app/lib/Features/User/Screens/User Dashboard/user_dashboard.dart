import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:public_emergency_app/Features/User/Screens/User%20DashBoard/grid_dash.dart';
import 'package:public_emergency_app/Features/User/Screens/User%20DashBoard/weather_widget.dart';
import '../ARBMedical/arb_medical_screen.dart';
import '../Chatbot/ai_chat_screen.dart';
import './DoctorOptions/doctor_options.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({Key? key}) : super(key: key);

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  FirebaseAuth auth = FirebaseAuth.instance;
  WeatherData? _weatherData;
  bool _isWeatherLoading = true;
  String _weatherError = '';
  static const String WEATHER_API_KEY = 'f0dbe5113db2db758394e7351f6254d0';

  @override
  void initState() {
    super.initState();
    _fetchWeatherForAppBar();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _fetchWeatherForAppBar() async {
    setState(() {
      _isWeatherLoading = true;
      _weatherError = '';
    });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _weatherError = 'Location permission denied';
            _isWeatherLoading = false;
          });
          return;
        }
      }
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      final response = await http.get(Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=${position.latitude}&lon=${position.longitude}&appid=$WEATHER_API_KEY&units=metric'));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        setState(() {
          _weatherData = WeatherData.fromJson(data);
          _isWeatherLoading = false;
        });
      } else {
        setState(() {
          _weatherError = 'Failed to load weather data';
          _isWeatherLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _weatherError = 'Error fetching weather: $e';
        _isWeatherLoading = false;
      });
    }
  }

  Widget _getWeatherIconWithTemp(String iconCode, double temp) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isLargeScreen = screenWidth > 600;
    
    // Responsive sizes
    final iconSize = isSmallScreen 
        ? screenWidth * 0.12 
        : isLargeScreen 
            ? screenWidth * 0.07 
            : screenWidth * 0.10;
            
    final fontSize = isSmallScreen 
        ? screenWidth * 0.028 
        : isLargeScreen 
            ? screenWidth * 0.025 
            : screenWidth * 0.032;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.network(
          'https://openweathermap.org/img/wn/$iconCode@2x.png',
          width: iconSize,
          height: iconSize,
          errorBuilder: (context, error, stackTrace) =>
              Icon(Icons.cloud, color: Colors.white, size: iconSize),
        ),
        const SizedBox(width: 0),
        Text(
          '${temp.round()}°C',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showWeatherDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: WeatherWidget(
            existingWeatherData: _weatherData,
            isLoading: _isWeatherLoading,
            onRefresh: _fetchWeatherForAppBar,
          ),
        );
      },
    );
  }

  void _openDoctorPage() {
    Get.to(() => const DoctorOptions());
  }

  void _openArbMedical() {
    Get.to(() => const ArbMedicalScreen());
  }

  void _openChatBot() {
    Get.to(() => const AIChatScreen());
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    final isLargeScreen = screenWidth > 600;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    // Responsive card height
    final cardHeight = isLandscape 
        ? screenHeight * 0.12 
        : isSmallScreen 
            ? screenHeight * 0.10 
            : screenHeight * 0.09;
    
    // Responsive padding
    final horizontalPadding = screenWidth * 0.04;
    final verticalPadding = screenHeight * 0.005;
    final spacing = screenHeight * 0.015;

    return Scaffold(
      appBar: PreferredSize(
  preferredSize: Size.fromHeight(isSmallScreen ? kToolbarHeight : kToolbarHeight + 0),
  child: AppBar(
    backgroundColor: const Color(0xFF0F4C5C),
    centerTitle: true,
    automaticallyImplyLeading: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
    ),
    titleSpacing: 0,
    
    // DASHBOARD TITLE - Responsive font size
    title: Text(
      "Dashboard",
      style: TextStyle(
        fontSize: isSmallScreen ? 24 : isLargeScreen ? 40 : 34,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        fontFamily: 'Trajan Pro',
        letterSpacing: 2.5,
      ),
    ),
    
    // AI CHATBOT ICON - Far left with responsive sizing
    leading: Padding(
      padding: EdgeInsets.only(left: isSmallScreen ? 8.0 : 12.0),
      child: GestureDetector(
        onTap: _openChatBot,
        child: Container(
          padding: EdgeInsets.all(isSmallScreen ? 4 : 6),
          child: Icon(
            Icons.smart_toy_rounded,
            color: Colors.white,
            size: isSmallScreen ? 22 : isLargeScreen ? 32 : 28,
          ),
        ),
      ),
    ),
    
    // FIX: Controls the width of the leading space so title centers properly
    leadingWidth: isSmallScreen 
        ? screenWidth * 0.15  // Small screens: 15% of screen width
        : isLargeScreen 
            ? screenWidth * 0.08  // Large screens: 8% of screen width
            : screenWidth * 0.12, // Medium screens: 12% of screen width
    
    // WEATHER WIDGET - Far right with responsive sizing
    actions: [
      SizedBox(
        // Responsive width for weather widget container
        width: isSmallScreen 
            ? screenWidth * 0.32  // Small screens: 32% of screen width
            : isLargeScreen 
                ? screenWidth * 0.20  // Large screens: 20% of screen width
                : screenWidth * 0.20, // Medium screens: 28% of screen width
        child: Center(
          child: _isWeatherLoading
              // LOADING INDICATOR - Responsive size
              ? SizedBox(
                  height: isSmallScreen ? 22 : 30,
                  width: isSmallScreen ? 22 : 30,
                  child: CircularProgressIndicator(
                    strokeWidth: isSmallScreen ? 1.5 : 2,
                    color: Colors.white,
                  ),
                )
              : _weatherData != null
                  // WEATHER ICON WITH TEMP - Responsive
                  ? GestureDetector(
                      onTap: _showWeatherDialog,
                      child: _getWeatherIconWithTemp(
                        _weatherData!.iconCode,
                        _weatherData!.temperature,
                      ),
                    )
                  // FALLBACK CLOUD ICON - Responsive
                  : GestureDetector(
                      onTap: _showWeatherDialog,
                      child: Icon(
                        Icons.cloud,
                        color: Colors.white,
                        size: isSmallScreen ? 22 : isLargeScreen ? 32 : 28,
                      ),
                    ),
        ),
      ),
    ],
    
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(20.0),
      child: const SizedBox.shrink(),
    ),
  ),
),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding, 
            vertical: verticalPadding
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(height: spacing),

              /// ARB MEDICAL CENTRE CARD - FIXED
              Material(
                elevation: 6,
                shadowColor: const Color(0xFFC0392B).withOpacity(0.4),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _openArbMedical,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: cardHeight,
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.04, 
                      vertical: screenHeight * 0.005
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFC0392B), Color(0xFFE74C3C)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(screenWidth * 0.025),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Image.asset(
                            'assets/arb/arb_icon0.png',
                            width: screenWidth * 0.08,
                            height: screenWidth * 0.08,
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.035),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ARB Medical Centre',
                                style: TextStyle(
                                  fontSize: isSmallScreen 
                                      ? screenWidth * 0.035 
                                      : isLargeScreen 
                                          ? screenWidth * 0.025 
                                          : screenWidth * 0.04,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: screenHeight * 0.002),
                              Text(
                                'Haseen Habib Foundation Trust',
                                style: TextStyle(
                                  fontSize: isSmallScreen 
                                      ? screenWidth * 0.025 
                                      : isLargeScreen 
                                          ? screenWidth * 0.018 
                                          : screenWidth * 0.03,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.all(screenWidth * 0.02),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            color: Colors.white,
                            size: isSmallScreen 
                                ? screenWidth * 0.03 
                                : isLargeScreen 
                                    ? screenWidth * 0.025 
                                    : screenWidth * 0.035,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing),

              /// DOCTOR CARD - FIXED
              Material(
                elevation: 6,
                shadowColor: const Color(0xFF0F4C5C).withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _openDoctorPage,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: cardHeight,
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.04, 
                      vertical: screenHeight * 0.005
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF0F4C5C).withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(screenWidth * 0.025),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F4C5C).withOpacity(0.08),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF0F4C5C).withOpacity(0.15),
                              width: 1,
                            ),
                          ),
                          child: Image.asset(
                            "assets/logos/Doctor.png",
                            width: screenWidth * 0.08,
                            height: screenWidth * 0.08,
                          ),
                        ),
                        SizedBox(width: screenWidth * 0.035),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Onboard Doctor",
                                style: TextStyle(
                                  fontSize: isSmallScreen 
                                      ? screenWidth * 0.035 
                                      : isLargeScreen 
                                          ? screenWidth * 0.025 
                                          : screenWidth * 0.04,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0F4C5C),
                                ),
                              ),
                              SizedBox(height: screenHeight * 0.002),
                              Text(
                                "Connect with a doctor instantly",
                                style: TextStyle(
                                  fontSize: isSmallScreen 
                                      ? screenWidth * 0.025 
                                      : isLargeScreen 
                                          ? screenWidth * 0.018 
                                          : screenWidth * 0.03,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.all(screenWidth * 0.02),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F4C5C).withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            color: const Color(0xFF0F4C5C),
                            size: isSmallScreen 
                                ? screenWidth * 0.03 
                                : isLargeScreen 
                                    ? screenWidth * 0.025 
                                    : screenWidth * 0.035,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: spacing / 2),

              /// GRID DASHBOARD - Takes remaining space
              Expanded(
                child: GridDashboard(onItemTap: () {}),
              ),
            ],
          ),
        ),
      ),
    );
  }
}