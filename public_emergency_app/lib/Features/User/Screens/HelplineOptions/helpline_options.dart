import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'video_player_screen.dart';

class HelplineOptions extends StatefulWidget {
  const HelplineOptions({super.key});

  @override
  State<HelplineOptions> createState() => _HelplineOptionsState();
}

class _HelplineOptionsState extends State<HelplineOptions> {
  final List<Map<String, dynamic>> helplines = const [
    {
      "category": "Emergency Services",
      "numbers": [
        {"name": "Police", "number": "15"},
        {"name": "Ambulance (Edhi)", "number": "115"},
        {"name": "Fire Brigade", "number": "16"},
        {"name": "Rescue 1122", "number": "1122"},
      ]
    },
    {
      "category": "Women & Child Safety",
      "numbers": [
        {"name": "Women Helpline", "number": "1099"},
        {"name": "Child Protection", "number": "1121"},
        {"name": "Domestic Violence Help", "number": "1300"},
      ]
    },
    {
      "category": "Medical Support",
      "numbers": [
        {"name": "Red Crescent", "number": "1030"},
        {"name": "Shaukat Khanum Help", "number": "111-155-555"},
        {"name": "JPMC Emergency", "number": "99201300"},
      ]
    },
  ];

  final List<Map<String, String>> videos = const [
    {
      "title": "CPR First Aid",
      "url": "https://sample-videos.com/video123/mp4/480/asdasdas.mp4"
    },
    {
      "title": "Bleeding Control",
      "url": "https://sample-videos.com/video123/mp4/480/asdasdas.mp4"
    },
  ];

  Future<void> callNumber(String number) async {
    final Uri url = Uri.parse("tel:$number");

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void openVideoPlayer(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(videoUrl: url),
      ),
    );
  }

  Widget quickActionButton({
    required String title,
    required IconData icon,
    required Color color,
    required String number,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () => callNumber(number),
        child: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Helpline Center"),
        backgroundColor: const Color(0xFF2563EB),
        centerTitle: true,
      ),

      /// 🚨 FLOATING EMERGENCY BUTTON
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.red,
        icon: const Icon(Icons.local_hospital),
        label: const Text("Ambulance"),
        onPressed: () => callNumber("115"),
      ),

      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [

              /// HEADER
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Text(
                  "🚨 Emergency Help Center",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 15),

              /// ⚡ QUICK ACTIONS (NEW)
              Row(
                children: [
                  quickActionButton(
                    title: "Police",
                    icon: Icons.local_police,
                    color: Colors.blue,
                    number: "15",
                  ),
                  quickActionButton(
                    title: "Ambulance",
                    icon: Icons.local_hospital,
                    color: Colors.red,
                    number: "115",
                  ),
                  quickActionButton(
                    title: "First Aid",
                    icon: Icons.healing,
                    color: Colors.green,
                    number: "1122",
                  ),
                ],
              ),

              const SizedBox(height: 15),

              /// HELPLINES
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: helplines.length,
                itemBuilder: (context, index) {
                  final category = helplines[index];

                  return ExpansionTile(
                    leading: const Icon(Icons.health_and_safety),
                    title: Text(category["category"]),
                    children: [
                      ...List.generate(category["numbers"].length, (i) {
                        final item = category["numbers"][i];

                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.call, color: Colors.green),
                            title: Text(item["name"]),
                            subtitle: Text(item["number"]),
                            trailing: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              onPressed: () => callNumber(item["number"]),
                              child: const Text("Call"),
                            ),
                          ),
                        );
                      })
                    ],
                  );
                },
              ),

              const SizedBox(height: 20),

              /// FIRST AID VIDEOS
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "🎥 First Aid Videos",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 10),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: videos.length,
                itemBuilder: (context, index) {
                  final video = videos[index];

                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.play_circle_fill,
                          color: Colors.red, size: 35),
                      title: Text(video["title"]!),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () => openVideoPlayer(video["url"]!),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}