import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:get/get.dart';
import 'keys.dart';
import 'doctor_video_call.dart'; // 🔥 ONLY ADDED THIS IMPORT

class LiveStreamingPage extends StatefulWidget {
  final String liveId;
  final bool isHost;
  final String userName;
  final String? userType;
  final String? userId;

  const LiveStreamingPage({
    Key? key,
    required this.liveId,
    required this.isHost,
    required this.userName,
    this.userType,
    this.userId,
  }) : super(key: key);

  @override
  State<LiveStreamingPage> createState() => _LiveStreamingPageState();
}

class _LiveStreamingPageState extends State<LiveStreamingPage> {
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

    final String userID = widget.userId ??
        (widget.isHost
            ? "responder_${widget.userName}"
            : "user_${widget.userName}");

    final String displayName =
        widget.isHost && widget.userType != null
            ? "${widget.userName} (${widget.userType})"
            : widget.userName;

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
          callID: widget.liveId,
          config: config,
        ),
      ),
    );
  }
}