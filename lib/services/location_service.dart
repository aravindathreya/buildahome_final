import 'package:geolocator/geolocator.dart';

import 'attendance_service.dart';

class LocationResult {
  final bool ok;
  final String? error;
  final bool openSettings;
  final Position? position;

  const LocationResult({
    required this.ok,
    this.error,
    this.openSettings = false,
    this.position,
  });
}

class GeofenceMatch {
  final AttendanceAssignment assignment;
  final double distanceMeters;
  final bool withinRadius;

  const GeofenceMatch({
    required this.assignment,
    required this.distanceMeters,
    required this.withinRadius,
  });
}

/// Shared GPS helpers for attendance geofencing.
class LocationService {
  LocationService._();

  static Future<LocationResult> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationResult(
        ok: false,
        error:
            'Location services are turned off. Turn them on to mark attendance.',
        openSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const LocationResult(
        ok: false,
        error: 'Location permission is required to mark attendance.',
        openSettings: true,
      );
    }

    if (permission == LocationPermission.deniedForever) {
      return const LocationResult(
        ok: false,
        error:
            'Location permission is permanently denied. Enable it in app settings.',
        openSettings: true,
      );
    }

    return const LocationResult(ok: true);
  }

  static Future<LocationResult> getCurrentPosition() async {
    final permission = await ensurePermission();
    if (!permission.ok) return permission;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationResult(ok: true, position: position);
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return LocationResult(ok: true, position: last);
        }
      } catch (_) {}
      return const LocationResult(
        ok: false,
        error: 'Unable to get your current location. Please try again.',
      );
    }
  }

  static Future<void> openAppSettings() => Geolocator.openAppSettings();

  static Future<void> openLocationSettings() =>
      Geolocator.openLocationSettings();

  /// Distance from [lat]/[lng] to each assignment that has coordinates.
  static List<GeofenceMatch> matchAssignments({
    required double latitude,
    required double longitude,
    required List<AttendanceAssignment> assignments,
  }) {
    final matches = <GeofenceMatch>[];
    for (final assignment in assignments) {
      if (!assignment.hasCoordinates) continue;
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        assignment.latitude!,
        assignment.longitude!,
      );
      matches.add(
        GeofenceMatch(
          assignment: assignment,
          distanceMeters: distance,
          withinRadius: distance <= assignment.radiusMeters,
        ),
      );
    }
    matches.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return matches;
  }

  static GeofenceMatch? nearestInRange(List<GeofenceMatch> matches) {
    for (final match in matches) {
      if (match.withinRadius) return match;
    }
    return null;
  }
}
