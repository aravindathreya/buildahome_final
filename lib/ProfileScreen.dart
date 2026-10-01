import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'services/location_service.dart';
import 'services/profile_picture_service.dart';
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
  String? _picturePath;
  bool? _backgroundLocationOn;
  bool _loading = true;

  bool get _showLocationControls {
    final role = _role.trim().toLowerCase();
    return role.isNotEmpty && role != 'client';
  }

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

    String displayName;
    if (role.toLowerCase() == 'client' && clientName.isNotEmpty) {
      displayName = clientName;
    } else if (username.isNotEmpty) {
      displayName = username.contains('-')
          ? username.split('-').first.trim()
          : username;
    } else {
      displayName = 'User';
    }

    bool? backgroundOn;
    if (role.isNotEmpty && role.toLowerCase() != 'client') {
      backgroundOn = await LocationService.hasBackgroundAccess();
    }

    if (!mounted) return;
    setState(() {
      _displayName = displayName;
      _role = role;
      _phone = phone;
      _picturePath = picture;
      _backgroundLocationOn = backgroundOn;
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

  Future<void> _confirmTurnOffLocation() async {
    final turnOff = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.darkBackgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Turn off background location?',
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          content: const Text(
            'Attendance monitoring uses background location. Turning this off may flag your attendance within the company.',
            style: TextStyle(
              color: AppTheme.darkTextSecondary,
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.darkBackgroundPrimary,
        appBar: AppBar(
          backgroundColor: AppTheme.darkBackgroundSecondary,
          foregroundColor: AppTheme.darkTextPrimary,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          title: const Text(
            'Profile',
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.accentBlue),
              )
            : RefreshIndicator(
                color: AppTheme.accentBlue,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    _buildIdentityCard(),
                    const SizedBox(height: 16),
                    _buildPhoneCard(),
                    if (_showLocationControls) ...[
                      const SizedBox(height: 16),
                      _buildLocationCard(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildIdentityCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          ProfileAvatar(
            displayName: _displayName,
            picturePath: _picturePath,
            size: 84,
            backgroundColor: AppTheme.darkBackgroundPrimaryLight,
            borderColor: AppTheme.border,
            showEditBadge: true,
            onTap: _changeProfilePicture,
          ),
          const SizedBox(height: 14),
          Text(
            _displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.darkTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (_role.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _role,
              style: const TextStyle(
                color: AppTheme.darkTextSecondary,
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
                foregroundColor: AppTheme.darkTextPrimary,
                side: const BorderSide(color: AppTheme.border),
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
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.darkBackgroundPrimaryLight,
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
                const Text(
                  'Logged-in phone number',
                  style: TextStyle(
                    color: AppTheme.darkTextSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _displayPhone,
                  style: const TextStyle(
                    color: AppTheme.darkTextPrimary,
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
    final statusBg =
        isOn ? const Color(0xFF14352B) : const Color(0xFF3A2F14);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
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
                    const Text(
                      'Background location',
                      style: TextStyle(
                        color: AppTheme.darkTextPrimary,
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
            style: const TextStyle(
              color: AppTheme.darkTextSecondary,
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
                      : (isOn ? _confirmTurnOffLocation : _openLocationSettings),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.darkTextPrimary,
                    side: const BorderSide(color: AppTheme.border),
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
