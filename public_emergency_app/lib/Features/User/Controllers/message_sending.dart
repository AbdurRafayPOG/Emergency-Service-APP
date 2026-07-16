import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class MessageController extends GetxController {
  static MessageController get instance => Get.find();

  // Reactive state variables
  final RxString currentAddress = RxString('');
  final Rx<Position?> currentPosition = Rx<Position?>(null);

  @override
  void onInit() {
    super.onInit();
    // Initialize permissions when controller starts
    _initializePermissions();
  }

  // Initialize necessary permissions
  Future<void> _initializePermissions() async {
    await handleLocationPermission();
  }

  Future<bool> handleLocationPermission() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Get.snackbar(
          'Location Disabled',
          'Please enable location services',
          backgroundColor: Colors.orange,
        );
        return false;
      }

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          Get.snackbar(
            'Permission Denied',
            'Location permissions are required for emergency alerts',
            backgroundColor: Colors.red,
          );
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        Get.snackbar(
          'Permission Permanently Denied',
          'Please enable location permissions in app settings',
          backgroundColor: Colors.red,
        );
        return false;
      }

      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      debugPrint('Location permission error: $e');
      return false;
    }
  }

  Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await handleLocationPermission();
      if (!hasPermission) return null;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );

      currentPosition.value = position;
      await getAddressFromLatLng(position);

      return position;
    } catch (e) {
      debugPrint('Error getting position: $e');
      Get.snackbar(
        'Location Error',
        'Unable to get current location',
        backgroundColor: Colors.red,
      );
      return null;
    }
  }

  Future<void> getAddressFromLatLng(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        currentAddress.value = [
          place.street,
          place.subLocality,
          place.locality,
          place.administrativeArea,
          place.postalCode,
        ].where((part) => part?.isNotEmpty == true).join(', ');
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
      currentAddress.value = 'Address unavailable';
    }
  }
}