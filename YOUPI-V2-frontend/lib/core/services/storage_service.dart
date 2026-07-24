import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';

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
  static const _keyGuestMode = 'guest_mode';
  static const _keyDeviceId = 'device_id';
  static const _keyLastMobile = 'last_mobile';
  static const _keyLastRechargeMobile = 'last_recharge_mobile';

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

  // ── Guest mode ──
  // Set when the user taps "Continue as Guest" on the Welcome screen. No
  // token exists for a guest, so the router redirect must special-case this
  // flag to avoid bouncing them straight back to /auth/mobile. Any screen
  // that performs a real operation (wallet, BNPL, KYC, etc.) should check
  // this via GuestGuard.requireAuth() before proceeding.
  static Future<void> setGuestMode(bool value) async =>
      await _storage.write(key: _keyGuestMode, value: value.toString());

  static Future<bool> isGuestMode() async =>
      (await _storage.read(key: _keyGuestMode)) == 'true';

  static Future<void> clearGuestMode() async =>
      await _storage.delete(key: _keyGuestMode);

  // ── Device ID ──
  // A stable, random per-install identifier -- NOT tied to hardware serials
  // or Android/iOS IDs (no extra permissions/packages needed for that).
  // Generated once and persisted in secure storage; a fresh app install
  // (or clearing app data) generates a new one, which correctly means that
  // "install" has to earn device-trust again via OTP. Sent as `deviceId` on
  // every /mpin/verify and /firebase/verify call so the backend can tell
  // devices apart for the trusted-device check.
  static Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: _keyDeviceId);
    if (existing != null) return existing;

    final random = Random.secure();
    final seed = List<int>.generate(32, (_) => random.nextInt(256));
    final id = sha256.convert(seed).toString();
    await _storage.write(key: _keyDeviceId, value: id);
    return id;
  }

  // ── Last known mobile number ──
  // Remembered after any successful login/registration so the "Existing
  // User" screen can skip straight to the MPIN pad on this device instead
  // of asking for the mobile number every single time. Only the mobile
  // -entry (recovery) step re-asks for it -- on 5 wrong MPIN attempts or a
  // "Forgot MPIN?" tap -- so it can be corrected if this device is ever
  // shared/reused for a different account.
  static Future<void> saveLastMobile(String mobile) async =>
      await _storage.write(key: _keyLastMobile, value: mobile);

  static Future<String?> getLastMobile() async =>
      await _storage.read(key: _keyLastMobile);

  static Future<void> clearLastMobile() async =>
      await _storage.delete(key: _keyLastMobile);

  // ── Last recharge-target mobile number ──
  // DIFFERENT from _keyLastMobile above -- that one is the logged-in
  // user's OWN mobile (used e.g. for Razorpay prefill). This one is
  // whatever number the recharge screen currently has selected, which
  // could be someone else's (recharging for a family member). Kept
  // separate so the two never accidentally overwrite each other.
  //
  // Exists because the recharge number was previously pure in-memory
  // viewmodel state -- when the OS reclaims memory after the app is
  // backgrounded/switched away from, Flutter can recreate the widget tree
  // (and the viewmodel) from scratch, silently losing whatever the user
  // had typed or selected. Persisting here survives that.
  static Future<void> saveLastRechargeMobile(String mobile) async =>
      await _storage.write(key: _keyLastRechargeMobile, value: mobile);

  static Future<String?> getLastRechargeMobile() async =>
      await _storage.read(key: _keyLastRechargeMobile);

  // ── Clear all (sign out) ──
  // Deliberately preserves device_id AND last_mobile -- signing out
  // shouldn't un-trust this device or make it forget which account it's
  // for. Only a genuine reinstall/app-data-clear should reset these (which
  // wipes secure storage at the OS level, outside our control anyway).
  static Future<void> clearAll() async {
    final deviceId = await _storage.read(key: _keyDeviceId);
    final lastMobile = await _storage.read(key: _keyLastMobile);
    await _storage.deleteAll();
    if (deviceId != null) {
      await _storage.write(key: _keyDeviceId, value: deviceId);
    }
    if (lastMobile != null) {
      await _storage.write(key: _keyLastMobile, value: lastMobile);
    }
  }
}