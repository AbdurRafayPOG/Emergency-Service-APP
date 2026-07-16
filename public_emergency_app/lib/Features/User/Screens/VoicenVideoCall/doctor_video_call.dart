import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:get/get.dart';
import 'keys.dart';

class DoctorVideoCallPage extends StatefulWidget {
  final String callId;
  final String userName;
  final String doctorName;
  final bool isUser; // true = user calling doctor, false = doctor calling user

  const DoctorVideoCallPage({
    Key? key,
    required this.callId,
    required this.userName,
    required this.doctorName,
    this.isUser = true,
  }) : super(key: key);

  @override
  State<DoctorVideoCallPage> createState() => _DoctorVideoCallPageState();
}

class _DoctorVideoCallPageState extends State<DoctorVideoCallPage> {
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.camera.request();
    await Permission.microphone.request();

    final bool cameraGranted = await Permission.camera.isGranted;
    final bool micGranted = await Permission.microphone.isGranted;

    if (!cameraGranted || !micGranted) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage =
            'Camera and Microphone permissions are required for video call';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(fontSize: 16, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Get.back(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // User ID for ZEGO
    final String userID = widget.isUser 
        ? "user_${widget.userName}"
        : "doctor_${widget.doctorName}";
    
    // 🔥 FIX: Use doctorName as-is (already has "Dr." prefix from DoctorDetailPage)
    final String displayName = widget.isUser
        ? widget.userName
        : widget.doctorName; // No extra "Dr." added here

    final config = ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
      ..turnOnCameraWhenJoining = true
      ..turnOnMicrophoneWhenJoining = true;

    return WillPopScope(
      onWillPop: () async => true,
      child: SafeArea(
        child: ZegoUIKitPrebuiltCall(
          appID: Keys.appId,
          appSign: Keys.appSign,
          userID: userID,
          userName: displayName,
          callID: widget.callId,
          config: config,
        ),
      ),
    );
  }
}