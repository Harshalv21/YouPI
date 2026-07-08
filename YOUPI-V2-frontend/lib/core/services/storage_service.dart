import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyToken = 'auth_token';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyMpin = 'user_mpin_hash';
  static const _keyUserId = 'user_id';
  static const _keyKycStatus = 'kyc_status';
  static const _keyFirstLaunch = 'first_launch';
  static const _keyBiometric = 'biometric_enabled';

  // ── Access token ──
  static Future<void> saveToken(String token) async =>
      await _storage.write(key: _keyToken, value: token);

  static Future<String?> getToken() async =>
      await _storage.read(key: _keyToken);

  static Future<void> deleteToken() async =>
      await _storage.delete(key: _keyToken);

  static Future<bool> hasToken() async =>
      (await _storage.read(key: _keyToken)) != null;

  // ── Refresh token ──
  static Future<void> saveRefreshToken(String refreshToken) async =>
      await _storage.write(key: _keyRefreshToken, value: refreshToken);

  static Future<String?> getRefreshToken() async =>
      await _storage.read(key: _keyRefreshToken);

  static Future<void> deleteRefreshToken() async =>
      await _storage.delete(key: _keyRefreshToken);

  /// Save both tokens together after login / refresh.
  static Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await saveToken(accessToken);
    if (refreshToken != null) await saveRefreshToken(refreshToken);
  }

  // ── MPIN — stored as SHA-256 hash only ──
  static Future<void> saveMpin(String mpin) async {
    final hash = sha256.convert(utf8.encode(mpin)).toString();
    await _storage.write(key: _keyMpin, value: hash);
  }

  static Future<bool> verifyMpin(String mpin) async {
    final stored = await _storage.read(key: _keyMpin);
    if (stored == null) return false;
    final hash = sha256.convert(utf8.encode(mpin)).toString();
    return stored == hash;
  }

  static Future<bool> hasMpin() async =>
      (await _storage.read(key: _keyMpin)) != null;

  // ── KYC ──
  static Future<void> setKycStatus(String status) async =>
      await _storage.write(key: _keyKycStatus, value: status);

  static Future<String?> getKycStatus() async =>
      await _storage.read(key: _keyKycStatus);

  static Future<bool> isKycVerified() async =>
      (await _storage.read(key: _keyKycStatus)) == 'verified';

  // ── First launch ──
  static Future<bool> isFirstLaunch() async =>
      (await _storage.read(key: _keyFirstLaunch)) == null;

  static Future<void> markLaunched() async =>
      await _storage.write(key: _keyFirstLaunch, value: 'false');

  // ── Biometric ──
  static Future<void> setBiometric(bool enabled) async =>
      await _storage.write(key: _keyBiometric, value: enabled.toString());

  static Future<bool> isBiometricEnabled() async =>
      (await _storage.read(key: _keyBiometric)) == 'true';

  // ── Clear all (sign out) ──
  static Future<void> clearAll() async => await _storage.deleteAll();
}