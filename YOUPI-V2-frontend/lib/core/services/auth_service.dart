// import 'storage_service.dart';
//
// class AuthService {
//   static bool _isAuthenticated = false;
//   static bool _isGuest = false;
//
//   static bool get isAuthenticated => _isAuthenticated;
//   static bool get isGuest => _isGuest;
//
//   static Future<void> initialize() async {
//     _isAuthenticated = await StorageService.hasToken();
//   }
//
//   static Future<bool> login(String mobile, String otp) async {
//     // Mock auth — any 6-digit OTP works
//     if (otp.length == 6) {
//       await StorageService.saveToken('mock_token_${DateTime.now().millisecondsSinceEpoch}');
//       _isAuthenticated = true;
//       _isGuest = false;
//       return true;
//     }
//     return false;
//   }
//
//   static Future<void> continueAsGuest() async {
//     _isGuest = true;
//     _isAuthenticated = false;
//   }
//
//   static Future<void> signOut() async {
//     await StorageService.clearAll();
//     _isAuthenticated = false;
//     _isGuest = false;
//   }
//
//   static Future<bool> checkFirstLaunch() async =>
//       StorageService.isFirstLaunch();
//
//   static Future<void> markLaunched() async =>
//       StorageService.markLaunched();
// }
