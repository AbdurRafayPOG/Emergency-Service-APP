import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class HospitalOptions extends StatefulWidget {
  const HospitalOptions({Key? key}) : super(key: key);

  @override
  State<HospitalOptions> createState() => _HospitalOptionsState();
}

class _HospitalOptionsState extends State<HospitalOptions> {
  GoogleMapController? mapController;

  final Set<Marker> _markers = {};

  double currentLat = 24.8607;
  double currentLng = 67.0011;

  bool isLoading = true;

  final String googleApiKey = "YOUR_GOOGLE_MAPS_API_KEY";

  @override
  void initState() {
    super.initState();
    initializeMap();
  }

  /// INITIALIZE MAP
  Future<void> initializeMap() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        Get.snackbar(
          "Permission Denied",
          "Location permission is required",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      currentLat = position.latitude;
      currentLng = position.longitude;

      await fetchNearbyHospitals();

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      Get.snackbar(
        "Error",
        e.toString(),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// FETCH HOSPITALS (OPTIMIZED)
  Future<void> fetchNearbyHospitals() async {
    try {
      final url =
          "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
          "?location=$currentLat,$currentLng"
          "&radius=5000"
          "&type=hospital"
          "&key=$googleApiKey";

      final response = await http.get(Uri.parse(url));
      final data = jsonDecode(response.body);

      if (data["results"] == null) return;

      Set<Marker> tempMarkers = {};

      for (var hospital in data["results"]) {
        double lat = hospital["geometry"]["location"]["lat"];
        double lng = hospital["geometry"]["location"]["lng"];

        tempMarkers.add(
          Marker(
            markerId: MarkerId(hospital["place_id"]),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(title: hospital["name"]),
            onTap: () {
              showHospitalDetails(hospital);
            },
          ),
        );

        // limit (important)
        if (tempMarkers.length > 20) break;
      }

      if (!mounted) return;

      setState(() {
        _markers
          ..clear()
          ..addAll(tempMarkers);
      });
    } catch (e) {
      if (!mounted) return;

      Get.snackbar(
        "API Error",
        e.toString(),
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// HOSPITAL DETAILS (UNCHANGED)
  void showHospitalDetails(dynamic hospital) {
    double hospitalLat = hospital["geometry"]["location"]["lat"];

    double hospitalLng = hospital["geometry"]["location"]["lng"];

    double distanceInMeters = Geolocator.distanceBetween(
      currentLat,
      currentLng,
      hospitalLat,
      hospitalLng,
    );

    double distanceInKm = distanceInMeters / 1000;

    String rating = hospital["rating"]?.toString() ?? "N/A";

    String address = hospital["vicinity"] ?? "Unknown Address";

    String hospitalName = hospital["name"] ?? "Hospital";

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hospitalName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F4C5C),
              ),
            ),

            const SizedBox(height: 15),

            Row(
              children: [
                const Icon(Icons.star, color: Colors.orange),
                const SizedBox(width: 5),
                Text(rating),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.red),
                const SizedBox(width: 5),
                Text("${distanceInKm.toStringAsFixed(2)} KM Away"),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(Icons.home, color: Colors.blue),
                const SizedBox(width: 5),
                Expanded(child: Text(address)),
              ],
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F4C5C),
                    ),
                    onPressed: () async {
                      final mapUrl =
                          "https://www.google.com/maps/dir/?api=1"
                          "&destination=$hospitalLat,$hospitalLng";

                      await launchUrl(
                        Uri.parse(mapUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const Icon(Icons.map),
                    label: const Text("Directions"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    onPressed: () {
                      openEmergencyForm(hospitalName);
                    },
                    icon: const Icon(Icons.emergency),
                    label: const Text("Emergency"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// EMERGENCY FORM (UNCHANGED)
  void openEmergencyForm(String hospitalName) {
    TextEditingController nameController = TextEditingController();
    TextEditingController phoneController = TextEditingController();
    TextEditingController problemController = TextEditingController();

    Get.bottomSheet(
      SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Emergency Request",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: "Patient Name",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: "Phone Number",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: problemController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: "Describe Emergency",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () async {
                    String message =
                        "🚨 Emergency Request\n\n"
                        "Hospital: $hospitalName\n"
                        "Patient: ${nameController.text}\n"
                        "Phone: ${phoneController.text}\n"
                        "Problem: ${problemController.text}\n\n"
                        "Location:\n"
                        "https://maps.google.com/?q=$currentLat,$currentLng";

                    String whatsappNumber = "923363059310";

                    final whatsappUrl =
                        "https://wa.me/$whatsappNumber"
                        "?text=${Uri.encodeComponent(message)}";

                    await launchUrl(
                      Uri.parse(whatsappUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: const Text("Send Emergency Request"),
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F4C5C),
        title: const Text("Nearby Hospitals"),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(currentLat, currentLng),
                    zoom: 14,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  markers: _markers,
                  onMapCreated: (controller) {
                    mapController = controller;
                  },
                ),
              ],
            ),
    );
  }
}
