import 'dart:async';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

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

/// Outcome of a site-proximity check. [distanceMeters] is omitted when a
/// silent last-known fallback was used, so callers can render the normal
/// on-site UI with no extra hint.
class SiteProximityResult {
  final bool ok;
  final String? error;
  final bool openSettings;
  final Position? position;
  final double? distanceMeters;
  final bool usedSilentLastKnown;

  const SiteProximityResult({
    required this.ok,
    this.error,
    this.openSettings = false,
    this.position,
    this.distanceMeters,
    this.usedSilentLastKnown = false,
  });

  double? get latitude => position?.latitude;
  double? get longitude => position?.longitude;
}

/// Pure on-site decision so the radius and silent-fallback rules live in one place.
class SiteProximityDecision {
  final bool ok;
  final double? visibleDistanceMeters;
  final String? error;
  final bool usedSilentLastKnown;

  const SiteProximityDecision({
    required this.ok,
    this.visibleDistanceMeters,
    this.error,
    this.usedSilentLastKnown = false,
  });
}

/// Shared GPS helpers for attendance geofencing and site-proof checks.
class LocationService {
  LocationService._();

  /// When a fresh GPS fix is unavailable, a last-known position within this
  /// distance of the site pin is accepted as on-site with no special UI.
  static const double weakSignalLastKnownAllowanceMeters = 3000;

  static const Duration recentLastKnownMaxAge = Duration(minutes: 5);
  static const Duration mediumAccuracyTimeout = Duration(seconds: 6);
  static const Duration highAccuracyTimeout = Duration(seconds: 12);
  static const Duration _lastKnownTimeout = Duration(seconds: 2);
  static const Duration _highAccuracyDartTimeout = Duration(seconds: 13);

  static Future<LocationResult> ensurePermission({
    String actionLabel = 'mark attendance',
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationResult(
        ok: false,
        error:
            'Location services are turned off. Turn them on to $actionLabel.',
        openSettings: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return LocationResult(
        ok: false,
        error: 'Location permission is required to $actionLabel.',
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

  /// Asks for background ("always") location after when-in-use is granted.
  /// Returns whether background access was granted. When-in-use can still be
  /// used for a manual check-in when this returns false.
  static Future<bool> requestBackgroundAccess() async {
    final current = await ensurePermission();
    if (!current.ok) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) return true;

    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.always) return true;

    final always = await Permission.locationAlways.request();
    if (always.isGranted) return true;

    permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always;
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

  static Future<bool> hasBackgroundAccess() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  /// Opens this app's system settings so background location can be changed.
  /// iOS uses the `app-settings:` link. Android opens the app details screen.
  static Future<bool> openBackgroundLocationSettings() async {
    if (Platform.isIOS) {
      try {
        final opened = await launchUrl(
          Uri.parse('app-settings:'),
          mode: LaunchMode.externalApplication,
        );
        if (opened) return true;
      } catch (_) {}
    }
    return Geolocator.openAppSettings();
  }

  static Future<void> openAppSettings() => Geolocator.openAppSettings();

  /// Opens the right settings page: device Location (GPS) settings when
  /// location services are off, otherwise this app's permission settings.
  static Future<void> openRelevantLocationSettings() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        final opened = await Geolocator.openLocationSettings();
        if (opened) return;
      }
    } catch (_) {}
    await Geolocator.openAppSettings();
  }

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

  static bool isLastKnownRecent(Position position, {DateTime? now}) {
    final age =
        (now ?? DateTime.now()).toUtc().difference(position.timestamp.toUtc());
    return age.isNegative || age <= recentLastKnownMaxAge;
  }

  /// Apply the normal radius for a fresh fix, or the silent last-known
  /// allowance when only a stale fix is available.
  static SiteProximityDecision decideProximity({
    required bool hasFreshFix,
    required double distanceMeters,
    required int radiusMeters,
  }) {
    if (hasFreshFix) {
      final onSite = distanceMeters <= radiusMeters;
      return SiteProximityDecision(
        ok: onSite,
        visibleDistanceMeters: distanceMeters,
        error: onSite
            ? null
            : 'Go to the project site to continue. You are about ${distanceMeters.round()} m away.',
      );
    }
    if (distanceMeters <= weakSignalLastKnownAllowanceMeters) {
      return const SiteProximityDecision(
        ok: true,
        usedSilentLastKnown: true,
      );
    }
    return const SiteProximityDecision(
      ok: false,
      error: 'Unable to get your current location.',
    );
  }

  /// Fast position for site checks: recent last-known, then medium accuracy,
  /// then high accuracy, then one retry. Every native call has a Dart timeout
  /// so the UI can never hang.
  static Future<LocationResult> getSiteCheckPosition({
    String actionLabel = 'continue',
  }) async {
    final permission = await ensurePermission(actionLabel: actionLabel);
    if (!permission.ok) return permission;

    final fresh = await _acquireFreshPosition();
    if (fresh != null) {
      return LocationResult(ok: true, position: fresh);
    }

    return const LocationResult(
      ok: false,
      error: 'Unable to get your current location.',
      openSettings: true,
    );
  }

  /// Permission + position + on-site decision, including the silent
  /// last-known allowance when a fresh fix cannot be obtained.
  static Future<SiteProximityResult> checkProximityToSite({
    double? siteLatitude,
    double? siteLongitude,
    int radiusMeters = 500,
    bool requireNearSite = true,
    String actionLabel = 'continue',
  }) async {
    final permission = await ensurePermission(actionLabel: actionLabel);
    if (!permission.ok) {
      return SiteProximityResult(
        ok: false,
        error: permission.error,
        openSettings: permission.openSettings,
      );
    }

    final fresh = await _acquireFreshPosition();
    if (fresh != null) {
      return _resultForCapturedPosition(
        position: fresh,
        isFresh: true,
        requireNearSite: requireNearSite,
        siteLatitude: siteLatitude,
        siteLongitude: siteLongitude,
        radiusMeters: radiusMeters,
      );
    }

    final lastKnown = await getLastKnownPositionSafe();
    if (lastKnown != null) {
      final result = _resultForCapturedPosition(
        position: lastKnown,
        isFresh: false,
        requireNearSite: requireNearSite,
        siteLatitude: siteLatitude,
        siteLongitude: siteLongitude,
        radiusMeters: radiusMeters,
      );
      if (result.ok) return result;
    }

    return SiteProximityResult(
      ok: false,
      error: 'Unable to get your current location.',
      openSettings: true,
      position: lastKnown,
    );
  }

  static SiteProximityResult _resultForCapturedPosition({
    required Position position,
    required bool isFresh,
    required bool requireNearSite,
    double? siteLatitude,
    double? siteLongitude,
    required int radiusMeters,
  }) {
    final siteLat = siteLatitude;
    final siteLng = siteLongitude;
    if (!requireNearSite || siteLat == null || siteLng == null) {
      return SiteProximityResult(
        ok: true,
        position: position,
        distanceMeters: isFresh ? 0 : null,
      );
    }
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      siteLat,
      siteLng,
    );
    final decision = decideProximity(
      hasFreshFix: isFresh,
      distanceMeters: distance,
      radiusMeters: radiusMeters,
    );
    if (!decision.ok) {
      return SiteProximityResult(
        ok: false,
        error: decision.error,
        position: position,
        distanceMeters: decision.visibleDistanceMeters,
        openSettings: !isFresh,
      );
    }
    return SiteProximityResult(
      ok: true,
      position: position,
      distanceMeters: decision.visibleDistanceMeters,
      usedSilentLastKnown: decision.usedSilentLastKnown,
    );
  }

  static Future<Position?> getLastKnownPositionSafe() async {
    try {
      return await Geolocator.getLastKnownPosition()
          .timeout(_lastKnownTimeout);
    } catch (_) {
      return null;
    }
  }

  static Future<Position?> _acquireFreshPosition() async {
    final recent = await getLastKnownPositionSafe();
    if (recent != null && isLastKnownRecent(recent)) {
      return recent;
    }

    final first = await _currentPositionAttempt();
    if (first != null) return first;
    return _currentPositionAttempt();
  }

  static Future<Position?> _currentPositionAttempt() async {
    final medium = await _getCurrentPositionWithTimeout(
      accuracy: LocationAccuracy.medium,
      timeout: mediumAccuracyTimeout,
    );
    if (medium != null) return medium;
    return _getCurrentPositionWithTimeout(
      accuracy: LocationAccuracy.high,
      timeout: _highAccuracyDartTimeout,
      pluginTimeLimit: highAccuracyTimeout,
    );
  }

  static Future<Position?> _getCurrentPositionWithTimeout({
    required LocationAccuracy accuracy,
    required Duration timeout,
    Duration? pluginTimeLimit,
  }) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: pluginTimeLimit ?? timeout,
        ),
      ).timeout(timeout);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
