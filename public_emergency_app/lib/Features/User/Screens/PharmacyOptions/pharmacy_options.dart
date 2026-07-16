import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../Common Widgets/constants.dart';

class PharmacyOptions extends StatelessWidget {
  const PharmacyOptions({Key? key}) : super(key: key);

  // ✅ FIXED URL Launcher (NO ERROR)
  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);

    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication, // 🔥 important fix
      );
    } catch (e) {
      Get.snackbar(
        "Error",
        "Could not open link",
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(color),
        centerTitle: true,
        automaticallyImplyLeading: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(40),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(Get.height * 0.1),
          child: Container(
            padding: const EdgeInsets.only(bottom: 15),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image(
                      image: const AssetImage("assets/logos/emergencyAppLogo.png"),
                      height: Get.height * 0.08,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  "Pharmacy Services",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            // 🗺️ Nearby Pharmacy
            Card(
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                tileColor: Color(color),
                leading: const Icon(Icons.local_pharmacy, color: Colors.yellowAccent),
                title: const Text("Nearby Pharmacy",
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  "Find nearest pharmacy on map",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  try {
                    Position position = await Geolocator.getCurrentPosition(
                        desiredAccuracy: LocationAccuracy.high);

                    double lat = position.latitude;
                    double long = position.longitude;

                    String url =
                        "https://www.google.com/maps/search/pharmacy/@$lat,$long,14z";

                    await _launchURL(url);
                  } catch (e) {
                    Get.snackbar("Error", "Location error: $e",
                        backgroundColor: Colors.red,
                        colorText: Colors.white);
                  }
                },
              ),
            ),

            // 💊 Search Medicine (FIXED)
            Card(
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                tileColor: Color(color),
                leading: const Icon(Icons.search, color: Colors.yellowAccent),
                title: const Text("Search Medicine",
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  "Search medicine online",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _launchURL("https://www.google.com/search?q=buy+medicine+online+Pakistan");
                },
              ),
            ),

            // 🚚 Order Medicine (FIXED)
            Card(
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                tileColor: Color(color),
                leading: const Icon(Icons.delivery_dining,
                    color: Colors.yellowAccent),
                title: const Text("Order Medicine",
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  "Order medicine from online pharmacy",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _launchURL("https://www.dawaai.pk/");
                },
              ),
            ),

            // 📞 Call Helpline
            Card(
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                tileColor: Color(color),
                leading: const Icon(Icons.call, color: Colors.yellowAccent),
                title: const Text("Call Helpline",
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  "Call for medical help",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  if (await Permission.phone.request().isGranted) {
                    await launchUrl(Uri.parse("tel:115"));
                  } else {
                    Get.snackbar(
                      "Permission Denied",
                      "Phone permission required",
                      backgroundColor: Colors.orange,
                    );
                  }
                },
              ),
            ),

            // ⏰ 24/7 Pharmacy
            Card(
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                tileColor: Color(color),
                leading: const Icon(Icons.access_time,
                    color: Colors.yellowAccent),
                title: const Text("24/7 Pharmacy",
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                  "Find open pharmacies anytime",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _launchURL(
                      "https://www.google.com/maps/search/24+hour+pharmacy+near+me/");
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}