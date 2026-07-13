import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api_client.g.dart';

// 10.0.2.2 — стандартный адрес хост-машины из Android-эмулятора
const _baseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://192.168.1.109:8002/api/v1/');

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
    final token = await _storage.read(key: 'access_token');
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
        final newAccess = resp.data['access_token'] as String;
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
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.connectionError) {
      return 'Нет соединения. Проверьте интернет и попробуйте снова.';
    }
    return 'Что-то пошло не так. Попробуйте ещё раз.';
  }
}

String extractUserMessage(Object e) {
  if (e is DioException) return e.userMessage;
  return 'Что-то пошло не так. Попробуйте ещё раз.';
}
