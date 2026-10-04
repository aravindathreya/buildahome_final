import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/mobile_live_test.dart';

/// Device location for Mobile Live Test uploads.
/// Outside the site radius (or if GPS is unavailable), site coordinates are used
/// so Test Mode never blocks on being physically on site.
class MobileLiveTestLocationResult {
  final bool ok;
  final double? latitude;
  final double? longitude;
  final double? distanceMeters;
  final String? error;
  final bool openSettings;

  const MobileLiveTestLocationResult({
    required this.ok,
    this.latitude,
    this.longitude,
    this.distanceMeters,
    this.error,
    this.openSettings = false,
  });
}

Future<MobileLiveTestLocationResult> ensureMobileLiveTestLocationPermission() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return const MobileLiveTestLocationResult(
      ok: false,
      error:
          'Location services are turned off. Turn them on to continue this task.',
      openSettings: true,
    );
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied) {
    return const MobileLiveTestLocationResult(
      ok: false,
      error: 'Location permission is required to continue this task.',
      openSettings: true,
    );
  }

  if (permission == LocationPermission.deniedForever) {
    return const MobileLiveTestLocationResult(
      ok: false,
      error:
          'Location permission is permanently denied. Enable it in app settings.',
      openSettings: true,
    );
  }

  return const MobileLiveTestLocationResult(ok: true);
}

Future<MobileLiveTestLocationResult> fetchMobileLiveTestPosition({
  MobileLiveTestSiteLocation? siteLocation,
  int nearSiteRadiusMeters = 500,
  bool requireNearSite = false,
}) async {
  MobileLiveTestLocationResult siteFallback() {
    final site = siteLocation;
    if (site != null && site.isValid) {
      return MobileLiveTestLocationResult(
        ok: true,
        latitude: site.latitude,
        longitude: site.longitude,
        distanceMeters: 0,
      );
    }
    return const MobileLiveTestLocationResult(
      ok: true,
      latitude: 12.9716,
      longitude: 77.5946,
      distanceMeters: 0,
    );
  }

  final permission = await ensureMobileLiveTestLocationPermission();
  if (!permission.ok) return siteFallback();

  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    ).timeout(const Duration(seconds: 15));

    final site = siteLocation;
    final distance = site == null || !site.isValid
        ? 0.0
        : Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            site.latitude,
            site.longitude,
          );

    if (requireNearSite &&
        site != null &&
        site.isValid &&
        distance > nearSiteRadiusMeters) {
      return siteFallback();
    }

    return MobileLiveTestLocationResult(
      ok: true,
      latitude: position.latitude,
      longitude: position.longitude,
      distanceMeters: site == null || !site.isValid ? null : distance,
    );
  } on TimeoutException {
    return siteFallback();
  } catch (_) {
    return siteFallback();
  }
}
