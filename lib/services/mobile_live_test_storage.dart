import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists Test Device credentials returned once at registration.
abstract class MobileLiveTestStore {
  Future<void> saveCredentials({
    required String deviceToken,
    required String publicId,
    String? displayName,
    String? registeredBy,
  });

  Future<String?> readDeviceToken();
  Future<String?> readPublicId();
  Future<String?> readDisplayName();
  Future<bool> hasCredentials();
  Future<void> clear();
}

class MemoryMobileLiveTestStore implements MobileLiveTestStore {
  final Map<String, String> _data = {};

  @override
  Future<void> saveCredentials({
    required String deviceToken,
    required String publicId,
    String? displayName,
    String? registeredBy,
  }) async {
    _data['device_token'] = deviceToken;
    _data['public_id'] = publicId;
    if (displayName != null) _data['display_name'] = displayName;
    if (registeredBy != null) _data['registered_by'] = registeredBy;
  }

  @override
  Future<String?> readDeviceToken() async => _data['device_token'];

  @override
  Future<String?> readPublicId() async => _data['public_id'];

  @override
  Future<String?> readDisplayName() async => _data['display_name'];

  @override
  Future<bool> hasCredentials() async {
    final token = _data['device_token'];
    return token != null && token.isNotEmpty;
  }

  @override
  Future<void> clear() async => _data.clear();
}

/// Production store: OS keychain / EncryptedSharedPreferences.
class SecureMobileLiveTestStore implements MobileLiveTestStore {
  SecureMobileLiveTestStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const _tokenKey = 'mobile_live_test_device_token';
  static const _publicIdKey = 'mobile_live_test_public_id';
  static const _displayNameKey = 'mobile_live_test_display_name';
  static const _registeredByKey = 'mobile_live_test_registered_by';

  final FlutterSecureStorage _storage;

  @override
  Future<void> saveCredentials({
    required String deviceToken,
    required String publicId,
    String? displayName,
    String? registeredBy,
  }) async {
    await _storage.write(key: _tokenKey, value: deviceToken);
    await _storage.write(key: _publicIdKey, value: publicId);
    if (displayName != null) {
      await _storage.write(key: _displayNameKey, value: displayName);
    }
    if (registeredBy != null) {
      await _storage.write(key: _registeredByKey, value: registeredBy);
    }
  }

  @override
  Future<String?> readDeviceToken() => _storage.read(key: _tokenKey);

  @override
  Future<String?> readPublicId() => _storage.read(key: _publicIdKey);

  @override
  Future<String?> readDisplayName() => _storage.read(key: _displayNameKey);

  @override
  Future<bool> hasCredentials() async {
    final token = await readDeviceToken();
    return token != null && token.trim().isNotEmpty;
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _publicIdKey),
      _storage.delete(key: _displayNameKey),
      _storage.delete(key: _registeredByKey),
    ]);
  }
}

class MobileLiveTestCredentials {
  MobileLiveTestCredentials._();

  static MobileLiveTestStore _store = SecureMobileLiveTestStore();

  static MobileLiveTestStore get store => _store;

  static void bindForTest(MobileLiveTestStore store) {
    _store = store;
  }

  static void resetBinding() {
    _store = SecureMobileLiveTestStore();
  }

  /// Clears Test Device secrets without touching the backend run.
  static Future<void> clearLocal() => _store.clear();
}
