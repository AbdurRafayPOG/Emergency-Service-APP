import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_config.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  Position? _currentPosition;
  String _locationInfo = "Karachi, Pakistan";
  String _selectedLanguage = "English";
  bool _stopRequested = false;

  bool _isUrduScript(String text) {
    final urduRegex = RegExp(r'[\u0600-\u06FF]');
    return urduRegex.hasMatch(text);
  }

  @override
  void initState() {
    super.initState();
    _showLanguageDialog();
    _getCurrentLocation();
  }

  void _showLanguageDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              _selectedLanguage == "Urdu" ? "زبان منتخب کریں" : "Select Language",
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F4C5C),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _selectedLanguage == "Urdu" 
                      ? "براہ کرم اپنی پسندیدہ زبان منتخب کریں"
                      : "Please select your preferred language",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildLanguageButton("English"),
                    _buildLanguageButton("Urdu"),
                  ],
                ),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _buildLanguageButton(String language) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLanguage = language;
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F4C5C),
              Color(0xFF1A7A8C),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F4C5C).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          language,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationInfo = "Karachi, Pakistan";
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationInfo = "Karachi, Pakistan";
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationInfo = "Karachi, Pakistan";
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      
      _currentPosition = position;
      await _getLocationDetails(position.latitude, position.longitude);
      
    } catch (e) {
      setState(() {
        _locationInfo = "Karachi, Pakistan";
      });
    }
  }

  Future<void> _getLocationDetails(double lat, double lng) async {
    try {
      final response = await http.get(
        Uri.parse(
          "https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&accept-language=en"
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data["address"] ?? {};
        
        String area = address["suburb"] ?? 
                      address["neighbourhood"] ?? 
                      address["city_district"] ?? 
                      "";
        
        String city = address["city"] ?? 
                     address["town"] ?? 
                     address["village"] ?? 
                     "Karachi";
        
        String country = address["country"] ?? "Pakistan";
        
        String location = area.isNotEmpty ? "$area, $city" : "$city, $country";
        
        setState(() {
          _locationInfo = location;
        });
      } else {
        setState(() {
          _locationInfo = "Karachi, Pakistan";
        });
      }
    } catch (e) {
      setState(() {
        _locationInfo = "Karachi, Pakistan";
      });
    }
  }

  void _stopGeneration() {
    setState(() {
      _stopRequested = true;
      _isLoading = false;
    });
    Get.snackbar(
      _selectedLanguage == "Urdu" ? "رک گیا" : "Stopped",
      _selectedLanguage == "Urdu" ? "جواب روک دیا گیا" : "Response stopped",
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: Colors.orange,
      colorText: Colors.white,
      duration: const Duration(seconds: 1),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    try {
      await launchUrl(launchUri);
    } catch (e) {
      Get.snackbar(
        "Error",
        "Could not launch dialer",
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.isEmpty) return;

    _stopRequested = false;

    setState(() {
      _messages.add({"role": "user", "text": text});
      _isLoading = true;
    });
    _controller.clear();
    _scrollToBottom();

    String responseLanguage;
    String languageInstruction;
    
    if (_selectedLanguage == "Urdu") {
      responseLanguage = "Urdu";
      languageInstruction = "Respond ONLY in URDU language using Urdu script (اردو). Write in proper Urdu. ALWAYS use Urdu script regardless of what language the user wrote in. Do NOT use English.";
    } else {
      responseLanguage = "English";
      languageInstruction = "Respond ONLY in ENGLISH language. Do NOT use Urdu. Always respond in English regardless of what language the user wrote in.";
    }

    String prompt = """
You are an emergency and medical assistant.

CRITICAL LANGUAGE INSTRUCTION: $languageInstruction

Location: $_locationInfo

The user asked: "$text"

Give helpful, practical, step-by-step advice for emergencies and medical situations.
If the question is not about emergencies or medical issues, politely decline.

Use **bold** for emergency numbers like 1122, 15, 16.
Use numbered steps (1., 2., 3.) for procedures.
Use bullet points for lists.
Keep paragraphs short and readable.

Your response MUST be in $responseLanguage.
""";

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.geminiApiUrl),
        headers: {
          "Authorization": "Bearer ${ApiConfig.geminiApiKey}",
          "Content-Type": "application/json",
          "HTTP-Referer": "https://your-app.com",
          "X-Title": "Emergency AI Assistant",
        },
        body: jsonEncode({
          "model": "google/gemini-3.5-flash",
          "messages": [
            {
              "role": "system",
              "content": "You are a helpful emergency and medical expert. Provide clear, practical, life-saving advice. Format with **bold**, numbered steps, and bullet points. CRITICAL: You must follow the language instruction in the user's message EXACTLY."
            },
            {
              "role": "user",
              "content": prompt
            }
          ],
          "temperature": 0.7,
          "max_tokens": 2000,
          "top_p": 0.9,
          "top_k": 50,
        }),
      );

      if (_stopRequested) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      String fallbackRefusal = _selectedLanguage == "Urdu"
          ? "میں صرف ہنگامی حالات اور طبی صحت کے سوالات میں آپ کی مدد کر سکتا ہوں۔"
          : "I can only assist with emergencies and medical health questions.";

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String reply = data["choices"]?[0]?["message"]?["content"] ?? fallbackRefusal;
        
        setState(() {
          _messages.add({"role": "assistant", "text": reply.trim()});
        });
        _scrollToBottom();
      } else {
        setState(() {
          _messages.add({
            "role": "assistant",
            "text": "Error ${response.statusCode}: Please try again.",
          });
        });
      }
    } catch (e) {
      if (!_stopRequested) {
        setState(() {
          _messages.add({
            "role": "assistant",
            "text": _selectedLanguage == "Urdu"
                ? "⚠️ کنکشن کی خرابی۔ براہ کرم دوبارہ کوشش کریں۔"
                : "⚠️ Connection error. Please try again.",
          });
        });
      }
    } finally {
      if (!_stopRequested) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _renderFormattedMessage(String messageText, bool isUser) {
    List<Widget> textSpans = [];
    final lines = messageText.split('\n');

    for (var line in lines) {
      if (line.trim().isEmpty) continue;

      Widget lineWidget;
      double leftPadding = 0.0;
      double topPadding = 2.0;
      double bottomPadding = 2.0;
      
      bool isHeader3 = line.trim().startsWith('###');
      bool isHeader2 = line.trim().startsWith('##');
      bool isHeader1 = line.trim().startsWith('#');
      
      String cleanLine = line;
      TextStyle customTextStyle = TextStyle(
        color: isUser ? Colors.white : Colors.black87,
        fontSize: 14,
        height: 1.4,
      );

      if (isHeader3) {
        cleanLine = line.replaceFirst('###', '').trim();
        customTextStyle = TextStyle(
          color: isUser ? Colors.white : const Color(0xFF0F4C5C),
          fontSize: 16,
          fontWeight: FontWeight.bold,
          height: 1.5,
        );
        topPadding = 8.0;
        bottomPadding = 4.0;
      } else if (isHeader2) {
        cleanLine = line.replaceFirst('##', '').trim();
        customTextStyle = TextStyle(
          color: isUser ? Colors.white : const Color(0xFF0F4C5C),
          fontSize: 18,
          fontWeight: FontWeight.bold,
          height: 1.5,
        );
        topPadding = 10.0;
        bottomPadding = 6.0;
      } else if (isHeader1) {
        cleanLine = line.replaceFirst('#', '').trim();
        customTextStyle = TextStyle(
          color: isUser ? Colors.white : const Color(0xFF0F4C5C),
          fontSize: 20,
          fontWeight: FontWeight.bold,
          height: 1.6,
        );
        topPadding = 12.0;
        bottomPadding = 6.0;
      }

      String trimmedLine = cleanLine.trim();
      bool isBullet = trimmedLine.startsWith('*') || 
                      trimmedLine.startsWith('-') || 
                      trimmedLine.startsWith('•') ||
                      trimmedLine.startsWith('---') ||
                      trimmedLine.startsWith('--');
      
      bool isNumeric = RegExp(r'^\d+\.\s+').hasMatch(trimmedLine);

      String displayText = cleanLine;
      String marker = "";
      bool hasMarker = false;
      
      if (isBullet) {
        displayText = cleanLine.replaceFirst(RegExp(r'^[\*\-•]+\s*'), '');
        displayText = displayText.replaceFirst(RegExp(r'^[\-]+\s*'), '');
        marker = "• ";
        leftPadding = 12.0;
        hasMarker = true;
      } else if (isNumeric) {
        final match = RegExp(r'^(\d+)\.\s+').firstMatch(trimmedLine);
        if (match != null) {
          marker = "${match.group(1)}. ";
          displayText = cleanLine.replaceFirst(RegExp(r'^\d+\.\s*'), '');
          leftPadding = 12.0;
          hasMarker = true;
        }
      }

      List<TextSpan> spans = [];
      final inlineRegex = RegExp(r'(\*\*(.*?)\*\*)|(\*(.*?)\*)|(\_(.*?)\_)');
      int lastIndex = 0;

      for (var match in inlineRegex.allMatches(displayText)) {
        if (match.start > lastIndex) {
          spans.add(TextSpan(text: displayText.substring(lastIndex, match.start)));
        }

        if (match.group(2) != null) {
          spans.add(TextSpan(
            text: match.group(2),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ));
        } else if (match.group(4) != null) {
          spans.add(TextSpan(
            text: match.group(4),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ));
        } else if (match.group(6) != null) {
          spans.add(TextSpan(
            text: match.group(6),
            style: const TextStyle(decoration: TextDecoration.underline),
          ));
        }
        lastIndex = match.end;
      }

      if (lastIndex < displayText.length) {
        spans.add(TextSpan(text: displayText.substring(lastIndex)));
      }

      if (hasMarker) {
        lineWidget = Padding(
          padding: EdgeInsets.only(left: leftPadding, top: topPadding, bottom: bottomPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                marker,
                style: TextStyle(
                  color: isUser ? Colors.white70 : const Color(0xFF0F4C5C),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Expanded(
                child: SelectableText.rich(
                  TextSpan(
                    style: customTextStyle,
                    children: spans,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        lineWidget = Padding(
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: SelectableText.rich(
            TextSpan(
              style: customTextStyle,
              children: spans,
            ),
          ),
        );
      }
      textSpans.add(lineWidget);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: textSpans,
    );
  }

  Widget _buildEmergencyButton(String label, String number, IconData icon, Color color) {
    bool isUrdu = _selectedLanguage == "Urdu";
    
    String displayLabel;
    if (isUrdu) {
      if (label == "Rescue") displayLabel = "ریسکیو";
      else if (label == "Police") displayLabel = "پولیس";
      else if (label == "Fire") displayLabel = "فائر";
      else displayLabel = label;
    } else {
      displayLabel = label;
    }

    return GestureDetector(
      onTap: () => _makePhoneCall(number),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.phone_rounded,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              displayLabel,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final double topPadding = (screenHeight * 0.035).clamp(15.0, 40.0);
    final double iconHeight = (screenHeight * 0.07).clamp(40.0, 70.0);
    final double buttonSize = (screenWidth * 0.11).clamp(36.0, 48.0);
    final double fixedAppBarHeight = (screenHeight * 0.12).clamp(90.0, 130.0);
    final double backButtonTop = topPadding + (iconHeight / 2) - (buttonSize / 2) - 6;

    bool isUrdu = _selectedLanguage == "Urdu";

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(fixedAppBarHeight + topPadding),
        child: Container(
          padding: EdgeInsets.only(top: topPadding),
          decoration: const BoxDecoration(
            color: Color(0xFF0F4C5C),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(24),
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
                    const SizedBox(height: 4),
                    Text(
                      isUrdu ? "اے آئی اسسٹنٹ" : "AI Assistant",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                top: backButtonTop,
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
      body: Column(
        children: [
          if (_messages.isEmpty)
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 60,
                        color: Color(0xFF0F4C5C),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        isUrdu 
                            ? "ہیلو، میں آپ کا ایمرجنسی اور میڈیکل اسسٹنٹ ہوں۔"
                            : "Hello. I am your emergency and medical assistant.",
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F4C5C),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isUrdu
                            ? "میں ہنگامی حالات اور طبی حالات میں مدد کے لیے ہوں"
                            : "I'm here to help with emergencies and medical situations",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.red.shade200,
                            width: 1,
                          ),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildEmergencyButton("Rescue", "1122", Icons.local_hospital, Colors.red),
                            _buildEmergencyButton("Police", "15", Icons.local_police, Colors.blue),
                            _buildEmergencyButton("Fire", "16", Icons.fire_extinguisher, Colors.orange),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.shade200,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isUrdu
                                  ? "ہنگامی خدمات کے لیے بٹن دبائیں"
                                  : "Tap buttons to call emergency services",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_messages.isNotEmpty)
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg["role"] == "user";
                  final text = msg["text"] ?? "";

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: isUser
                              ? const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF0F4C5C),
                                    Color(0xFF1A7A8C),
                                  ],
                                )
                              : null,
                          color: isUser ? null : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(isUser ? 16 : 4),
                            topRight: Radius.circular(isUser ? 4 : 16),
                            bottomLeft: const Radius.circular(16),
                            bottomRight: const Radius.circular(16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isUser ? 0.1 : 0.05),
                              blurRadius: isUser ? 12 : 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isUser)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 18,
                                      height: 18,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF0F4C5C),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.assistant_rounded,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      isUrdu ? "اے آئی اسسٹنٹ" : "AI Assistant",
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0F4C5C),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            _renderFormattedMessage(text, isUser),
                            const SizedBox(height: 4),
                            Text(
                              _getTimeString(),
                              style: TextStyle(
                                fontSize: 9,
                                color: isUser ? Colors.white70 : Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF0F4C5C),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isUrdu ? "سوچ رہا ہوں..." : "Thinking...",
                        style: const TextStyle(
                          color: Color(0xFF0F4C5C),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: Colors.grey.shade200,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: isUrdu ? "یہاں لکھیں..." : "Ask me anything...",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        suffixIcon: _controller.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: Colors.grey.shade400,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _controller.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      textInputAction: TextInputAction.send,
                      onChanged: (value) => setState(() {}),
                      onSubmitted: (value) => _sendMessage(value),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (_isLoading)
                  GestureDetector(
                    onTap: _stopGeneration,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade400,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.shade400.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.stop_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isUrdu ? "روکیں" : "Stop",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: _controller.text.isNotEmpty
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF0F4C5C),
                                Color(0xFF1A7A8C),
                              ],
                            )
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.grey.shade300,
                                Colors.grey.shade400,
                              ],
                            ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        if (_controller.text.isNotEmpty)
                          BoxShadow(
                            color: const Color(0xFF0F4C5C).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: _controller.text.isNotEmpty && !_isLoading
                          ? () => _sendMessage(_controller.text)
                          : null,
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getTimeString() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }
}