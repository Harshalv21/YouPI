import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'package:flutter/foundation.dart';
/// Central HTTP client for all YOUPI backend calls.
///
/// Key feature: on a 401, it tries to silently refresh the access token using
/// the stored refresh token, then retries the original request. The user stays
/// logged in seamlessly. Only if refresh itself fails do we clear the session.
class ApiService {
  // Defaults to the real Cloud Run backend. For local testing against your
  // machine instead, run with:
  //   flutter run --dart-define=API_BASE_URL=http://<your-local-ip>:8082/api
  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://youpi-api-887162129478.asia-south1.run.app/api',
  );
  static final Dio _dio = Dio();
  static Dio get instance => _dio;

  // Separate Dio for refresh, so the refresh call doesn't loop through the
  // auth interceptor.
  static final Dio _refreshDio = Dio(BaseOptions(baseUrl: _baseUrl));

  // Prevents concurrent refreshes: many 401s share one refresh.
  static Future<bool>? _ongoingRefresh;

  static void initialize() {
    debugPrint('🔵 BASE URL: $_baseUrl');
    _dio.options = BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    );
    _dio.interceptors.add(_AuthInterceptor());
  }

  static dynamic unwrap(Response res) {
    final body = res.data;
    if (body is Map && body['success'] == true) {
      return body['data'];
    }
    // Was previously a silent, generic "Request failed" with no way to tell
    // what actually went wrong. This logs the real status/body so the cause
    // (auth issue, validation error, unexpected response shape, etc.) is
    // visible in the console on the next occurrence instead of guessing.
    debugPrint('🔴 unwrap() fallback -- statusCode: ${res.statusCode}, '
        'bodyType: ${body.runtimeType}');
    debugPrint('🔴 unwrap() raw body: $body');
    throw Exception(_extractError(res.data) ??
        'Request failed (status ${res.statusCode})');
  }

  static String? _extractError(dynamic data) {
    if (data is Map && data['error'] is Map) {
      return data['error']['message'] as String?;
    }
    return null;
  }

  static Exception toException(DioException e) {
    debugPrint('🔴 DioException -- status: ${e.response?.statusCode}, '
        'path: ${e.requestOptions.path}');
    debugPrint('🔴 DioException raw body: ${e.response?.data}');
    final msg =
        _extractError(e.response?.data) ?? e.message ?? 'Network error';
    return Exception(msg);
  }

  /// Get a new access token via refresh token. De-duplicated across callers.
  static Future<bool> refreshTokens() {
    return _ongoingRefresh ??= _doRefresh().whenComplete(() {
      _ongoingRefresh = null;
    });
  }

  static Future<bool> _doRefresh() async {
    final refreshToken = await StorageService.getRefreshToken();
    if (refreshToken == null) return false;
    try {
      final res = await _refreshDio.post('/v1/auth/token/refresh', data: {
        'refreshToken': refreshToken,
      });
      if (res.data is Map && res.data['success'] == true) {
        final data = res.data['data'];
        await StorageService.saveTokens(
          accessToken: data['accessToken'],
          refreshToken: data['refreshToken'], // rotation
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

// Add this import at the top of api_service.dart if not already present:
// import 'package:flutter/foundation.dart' show kDebugMode;

class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await StorageService.getToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
      // TEMPORARY, testing-only -- lets you copy the current JWT out of the
      // console to hit the API manually from Postman without re-doing
      // login/MPIN each time. Guarded by kDebugMode so it's physically
      // impossible for this to compile into a release build and leak a
      // live session token (15-min TTL, but still) into device logs/logcat.
      // Remove this line entirely once no longer needed for testing --
      // don't leave it around "just in case" the way AUTH_DUMMY_ENABLED was.
      if (kDebugMode) {
        debugPrint('🔑 TOKEN: $token');
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final is401 = err.response?.statusCode == 401;
    final isRefreshCall =
    err.requestOptions.path.contains('/auth/token/refresh');
    final alreadyRetried = err.requestOptions.extra['__retried'] == true;
    if (is401 && !isRefreshCall && !alreadyRetried) {
      final refreshed = await ApiService.refreshTokens();
      if (refreshed) {
        final newToken = await StorageService.getToken();
        final opts = err.requestOptions;
        opts.headers['Authorization'] = 'Bearer $newToken';
        opts.extra['__retried'] = true;
        try {
          final clone = await ApiService.instance.fetch(opts);
          return handler.resolve(clone);
        } catch (e) {
          if (e is DioException) return handler.next(e);
        }
      } else {
        // Refresh failed → session expired. Clear.
        await StorageService.deleteToken();
        await StorageService.deleteRefreshToken();
      }
    }
    handler.next(err);
  }
}