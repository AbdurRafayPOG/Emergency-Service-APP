import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:public_emergency_app/Common%20Widgets/constants.dart';
import 'package:url_launcher/url_launcher.dart';

class FireFighterOptions extends StatelessWidget {
  const FireFighterOptions({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFDC2626),
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
                      image: const AssetImage(
                          "assets/logos/emergencyAppLogo.png"),
                      height: Get.height * 0.08,
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  child: const Text(
                    "Fire Fighter Options",
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Fire Station Map Display
            Card(
              child: ListTile(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(15.0),
                  ),
                ),
                tileColor: Color(color),
                leading: const Icon(Icons.map, color: Colors.yellowAccent),
                title: const Text('Fire Station Map Display',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Find the nearest fire station on the map',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  try {
                    Position position = await Geolocator.getCurrentPosition(
                        desiredAccuracy: LocationAccuracy.high);
                    double lat = position.latitude;
                    double long = position.longitude;

                    String url = '';
                    String urlAppleMaps = '';

                    if (Platform.isAndroid) {
                      url =
                          "https://www.google.com/maps/search/fire+brigade/@$lat,$long,12.5z";
                      if (await canLaunchUrl(Uri.parse(url))) {
                        await launchUrl(Uri.parse(url));
                      } else {
                        throw 'Could not launch $url';
                      }
                    } else {
                      urlAppleMaps = 'https://maps.apple.com/?q=$lat,$long';
                      url =
                          'comgooglemaps://?saddr=&daddr=$lat,$long&directionsmode=driving';
                      if (await canLaunchUrl(Uri.parse(url))) {
                        await launchUrl(Uri.parse(url));
                      } else if (await canLaunchUrl(Uri.parse(urlAppleMaps))) {
                        await launchUrl(Uri.parse(urlAppleMaps));
                      } else {
                        throw 'Could not launch map URL';
                      }
                    }
                  } catch (e) {
                    Get.snackbar(
                      'Error',
                      'Unable to get current location or launch map: $e',
                      backgroundColor: Colors.red,
                      colorText: Colors.white,
                    );
                  }
                },
              ),
            ),

            // Call Fire Station
            Card(
              child: ListTile(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(15.0),
                  ),
                ),
                tileColor: Color(color),
                leading: const Icon(Icons.call, color: Colors.yellowAccent),
                title:
                    const Text('Call', style: TextStyle(color: Colors.white)),
                subtitle: const Text(
                    'Directly call the fire station helpline',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  if (await Permission.phone.request().isGranted) {
                    try {
                      var url = Uri.parse("tel:16");
                      await launchUrl(url);
                    } catch (e) {
                      Get.snackbar(
                        'Error',
                        'Failed to make a call: $e',
                        backgroundColor: Colors.red,
                        colorText: Colors.white,
                      );
                    }
                  } else {
                    Get.snackbar(
                      'Permission Denied',
                      'Phone permission is required to make calls.',
                      backgroundColor: Colors.orange,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
