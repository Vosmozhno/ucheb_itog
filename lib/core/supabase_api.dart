import 'package:dio/dio.dart';
import 'api_error.dart';
import 'config.dart';

class SupabaseApi {
  SupabaseApi({Dio? dio})
    : dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.supabaseUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'apikey': AppConfig.publicKey,
                'Content-Type': 'application/json',
              },
            ),
          );
  final Dio dio;
  Future<String?> Function()? accessToken;
  Future<bool> Function()? refreshSession;
  Future<void> Function()? sessionExpired;

  Future<Response<dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
    bool authenticated = true,
    bool retryGet = true,
  }) async {
    var refreshed = false, retried = false;
    while (true) {
      if (cancelToken?.isCancelled ?? false) {
        throw const ApiError(ApiErrorKind.cancelled, 'Запрос отменён');
      }
      final token = authenticated ? await accessToken?.call() : null;
      try {
        return await dio.request<dynamic>(
          path,
          data: data,
          queryParameters: query,
          cancelToken: cancelToken,
          options: Options(
            method: method,
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
              ...?(headers),
            },
          ),
        );
      } on DioException catch (error) {
        final mapped = ApiError.fromDio(error);
        if (authenticated &&
            error.response?.statusCode == 401 &&
            !refreshed &&
            refreshSession != null) {
          refreshed = true;
          if (await refreshSession!.call()) continue;
          await sessionExpired?.call();
        }
        if (method == 'GET' && retryGet && !retried && mapped.canRetry) {
          retried = true;
          await Future<void>.delayed(const Duration(milliseconds: 300));
          continue;
        }
        throw mapped;
      }
    }
  }

  Future<dynamic> rpc(
    String name,
    Map<String, dynamic> data, {
    CancelToken? cancelToken,
  }) async => (await request(
    '/rest/v1/rpc/$name',
    method: 'POST',
    data: data,
    cancelToken: cancelToken,
  )).data;
  void close() => dio.close(force: true);
}
