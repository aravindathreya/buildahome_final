import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'services/app_logout.dart';
import 'services/data_provider.dart';
import 'services/location_service.dart';
import 'services/profile_picture_service.dart';
import 'services/theme_service.dart';
import 'widgets/profile_picture_dialog.dart';

/// Account profile: phone, photo, and location permission controls.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
  String _displayName = '';
  String _role = '';
  String _phone = '';
  String _projectNumber = '';
  String? _picturePath;
  bool? _backgroundLocationOn;
  bool _loading = true;

  /// Fallback matches pubspec `version:` when PackageInfo is unavailable
  /// (e.g. before a full rebuild after adding the plugin).
  String _appVersion = 'Version 3.0.1';

  bool get _isClient => _role.trim().toLowerCase() == 'client';

  bool get _showLocationControls {
    final role = _role.trim().toLowerCase();
    return role.isNotEmpty && role != 'client';
  }

  bool get _showProjectNumber => _isClient && _projectNumber.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLocationPermission());
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final picture = await ProfilePictureService.getStoredPath();
    final role = (prefs.getString('role') ?? '').trim();
    final username = (prefs.getString('username') ?? '').trim();
    final clientName = (prefs.getString('client_name') ?? '').trim();
    final phone = (prefs.getString('phone') ??
            prefs.getString('phone_number') ??
            prefs.getString('mobile') ??
            '')
        .trim();
    // Prefer human-facing project_code/number — never display ERP project_id.
    var projectNumber = (prefs.getString('project_number') ??
            prefs.getString('project_code') ??
            '')
        .trim();
    if (role.toLowerCase() == 'client' && projectNumber.isEmpty) {
      projectNumber =
          (await DataProvider().ensureClientProjectNumber())?.trim() ?? '';
    }

    String displayName;
    if (role.toLowerCase() == 'client' && clientName.isNotEmpty) {
      displayName = clientName;
    } else if (username.isNotEmpty) {
      displayName =
          username.contains('-') ? username.split('-').first.trim() : username;
    } else {
      displayName = 'User';
    }

    bool? backgroundOn;
    if (role.isNotEmpty && role.toLowerCase() != 'client') {
      backgroundOn = await LocationService.hasBackgroundAccess();
    }

    String appVersion = _appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (version.isNotEmpty) {
        appVersion =
            build.isNotEmpty ? 'Version $version ($build)' : 'Version $version';
      }
    } catch (_) {
      // Keep any previously loaded version label.
    }

    if (!mounted) return;
    setState(() {
      _displayName = displayName;
      _role = role;
      _phone = phone;
      _projectNumber = projectNumber;
      _picturePath = picture;
      _backgroundLocationOn = backgroundOn;
      _appVersion = appVersion;
      _loading = false;
    });
  }

  Future<void> _refreshLocationPermission() async {
    if (!_showLocationControls) return;
    final backgroundOn = await LocationService.hasBackgroundAccess();
    if (!mounted) return;
    setState(() => _backgroundLocationOn = backgroundOn);
  }

  Future<void> _changeProfilePicture() async {
    final path = await showProfilePictureDialog(
      context,
      currentPicturePath: _picturePath,
    );
    if (!mounted) return;
    if (path != null && path.isNotEmpty) {
      ProfilePictureService.picturePathNotifier.value = path;
      setState(() => _picturePath = path);
      return;
    }
    final stored = await ProfilePictureService.getStoredPath();
    if (!mounted) return;
    if (stored != _picturePath) {
      setState(() => _picturePath = stored);
    }
  }

  Future<void> _openLocationSettings() async {
    await LocationService.openBackgroundLocationSettings();
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.backgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Log out?',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          content: Text(
            'Are you sure you want to log out of this account?',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Log out',
                style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (shouldLogout == true && mounted) {
      await AppLogout.logoutAndGoToLogin(context: context);
    }
  }

  Future<void> _confirmTurnOffLocation() async {
    final turnOff = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.backgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Turn off background location?',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          content: Text(
            'Attendance monitoring uses background location. Turning this off may flag your attendance within the company.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Keep on',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Turn off',
                style: TextStyle(
                  color: Color(0xFFFBBF24),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (turnOff != true || !mounted) return;
    await LocationService.openBackgroundLocationSettings();
  }

  String get _displayPhone {
    final raw = _phone.trim();
    if (raw.isEmpty) return 'Not available';
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.modeNotifier,
      builder: (context, themeMode, _) {
        final isDark = themeMode != ThemeMode.light;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value:
              isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: AppTheme.backgroundPrimary,
            appBar: AppBar(
              backgroundColor: AppTheme.backgroundSecondary,
              foregroundColor: AppTheme.textPrimary,
              elevation: 0,
              systemOverlayStyle: isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              title: Text(
                'Profile',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            body: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppTheme.accentBlue),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          color: AppTheme.accentBlue,
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                            children: [
                              _buildIdentityCard(),
                              const SizedBox(height: 16),
                              _buildPhoneCard(),
                              if (_showProjectNumber) ...[
                                const SizedBox(height: 16),
                                _buildProjectNumberCard(),
                              ],
                              if (_showLocationControls) ...[
                                const SizedBox(height: 16),
                                _buildLocationCard(),
                              ],
                              const SizedBox(height: 16),
                              _buildAppearanceCard(isDark),
                              const SizedBox(height: 16),
                              _buildLogoutButton(),
                            ],
                          ),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: Center(
                            child: Text(
                              _appVersion,
                              style: const TextStyle(
                                color: AppTheme.mutedGrey,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildAppearanceCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.backgroundPrimaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              color: AppTheme.accentBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dark mode',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isDark ? 'Using dark appearance' : 'Using light appearance',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: isDark,
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              // Off state stays obvious on a white card so dark mode is easy
              // to turn back on.
              return isDark ? const Color(0xFFF4F4F5) : AppTheme.navy;
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppTheme.accentBlue;
              }
              return isDark ? const Color(0xFF3F3F46) : const Color(0xFFE4E4E7);
            }),
            trackOutlineColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppTheme.accentBlue;
              }
              return isDark ? const Color(0xFF71717A) : const Color(0xFFA1A1AA);
            }),
            onChanged: (value) {
              unawaited(ThemeService.instance.setDark(value));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _confirmLogout,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text(
          'Log out',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFDC2626),
          side: const BorderSide(color: Color(0xFF7F1D1D)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        children: [
          ProfileAvatar(
            displayName: _displayName,
            picturePath: _picturePath,
            size: 84,
            backgroundColor: AppTheme.backgroundPrimaryLight,
            borderColor: AppTheme.borderColor,
            showEditBadge: true,
            onTap: _changeProfilePicture,
          ),
          const SizedBox(height: 14),
          Text(
            _displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (_role.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _role,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _changeProfilePicture,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(
                (_picturePath == null || _picturePath!.isEmpty)
                    ? 'Add profile picture'
                    : 'Change profile picture',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.borderColor),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.backgroundPrimaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.phone_iphone_rounded,
              color: AppTheme.accentBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logged-in phone number',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _displayPhone,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectNumberCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.backgroundPrimaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.home_work_outlined,
              color: AppTheme.accentBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Project number',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _projectNumber,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    final backgroundOn = _backgroundLocationOn;
    final isOn = backgroundOn == true;
    final statusColor =
        isOn ? const Color(0xFF34D399) : const Color(0xFFFBBF24);
    final statusBg = isOn
        ? (AppTheme.isDark ? const Color(0xFF14352B) : const Color(0xFFD1FAE5))
        : (AppTheme.isDark ? const Color(0xFF3A2F14) : const Color(0xFFFEF3C7));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isOn
                      ? Icons.my_location_rounded
                      : Icons.location_disabled_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Background location',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      backgroundOn == null
                          ? 'Checking permission…'
                          : isOn
                              ? 'Allowed all the time'
                              : 'Not allowed for background use',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isOn
                ? 'Attendance monitoring uses background location after check-in. You can reset or turn this off in system settings.'
                : 'Allow location all the time so attendance can update after you check in.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: backgroundOn == null
                      ? null
                      : (isOn
                          ? _confirmTurnOffLocation
                          : _openLocationSettings),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: BorderSide(color: AppTheme.borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isOn ? 'Turn off' : 'Allow in settings',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _openLocationSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColorConstLight,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Reset permission',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
