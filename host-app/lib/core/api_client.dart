import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api_client.g.dart';

// Продакшн по умолчанию — так release-сборка работает без --dart-define.
// Для локальной разработки: --dart-define=API_URL=http://192.168.1.109:8002/api/v1/
const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'https://impomento.pro/api/v1/');

@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(_AuthInterceptor(dio, ref));
  return dio;
}

class _AuthInterceptor extends QueuedInterceptorsWrapper {
  final Dio _dio;
  // ignore: unused_field
  final Ref _ref;
  static const _storage = FlutterSecureStorage();

  _AuthInterceptor(this._dio, this._ref);

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // FlutterSecureStorage может бросать PlatformException при апгрейде APK
    // с другой подписью — ловим и продолжаем без токена.
    String? token;
    try {
      token = await _storage.read(key: 'access_token');
    } catch (_) {
      try { await _storage.deleteAll(); } catch (_) {}
    }
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final path = err.requestOptions.path;
    final isAuthPath = path.startsWith('auth/') || path.startsWith('/auth/');
    if (err.response?.statusCode == 401 && !isAuthPath) {
      try {
        final refresh = await _storage.read(key: 'refresh_token');
        if (refresh == null) return handler.next(err);

        final resp = await _dio.post('auth/refresh', data: {'refresh_token': refresh});
        // При частичном ответе backend (например 5xx с фрагментом JSON) cast может
        // упасть — не даём приложению крашнуться, логаутим пользователя.
        final data = resp.data;
        final newAccess = (data is Map ? data['access_token'] : null) as String?;
        if (newAccess == null || newAccess.isEmpty) {
          await _storage.deleteAll();
          return handler.next(err);
        }
        await _storage.write(key: 'access_token', value: newAccess);

        err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
        final retried = await _dio.fetch(err.requestOptions);
        return handler.resolve(retried);
      } catch (_) {
        await _storage.deleteAll();
        handler.next(err);
      }
    } else {
      handler.next(err);
    }
  }
}

extension DioErrorMessage on DioException {
  String get userMessage {
    final data = response?.data;
    if (data is Map) {
      // Backend format: {"error": {"message": "..."}}
      final error = data['error'];
      if (error is Map && error['message'] != null) return error['message'].toString();
      // FastAPI validation format: {"detail": "..."}
      if (data['detail'] != null) return data['detail'].toString();
    }
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.sendTimeout) {
      return 'Нет соединения. Проверьте интернет и попробуйте снова.';
    }
    // Для connectionError / badCertificate / unknown — показываем тип+underlying error,
    // чтобы был виден реальный тип ошибки (HandshakeException, SocketException и т.п.).
    final inner = error?.toString() ?? message ?? 'unknown';
    return '${type.name}: $inner';
  }

  /// Backend посылает {"error": {"code": "PIN_REQUIRED", ...}}. Возвращает код
  /// или null, если это не структурированная app-ошибка (сетевая, timeout).
  String? get errorCode {
    final data = response?.data;
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['code'] != null) return error['code'].toString();
    }
    return null;
  }
}

/// Утилита: возвращает код ошибки из любого исключения (DioException / others).
String? extractErrorCode(Object e) {
  if (e is DioException) return e.errorCode;
  return null;
}

String extractUserMessage(Object e) {
  if (e is DioException) return e.userMessage;
  // Показываем реальный тип+сообщение — так пользователь может увидеть,
  // что именно сломалось (PlatformException, StateError и т.п.), а не немую
  // «что-то пошло не так».
  final type = e.runtimeType.toString();
  final msg = e.toString();
  return '$type: $msg';
}
