import 'dart:convert';
import 'package:dio/dio.dart';

enum ApiErrorKind {
  network,
  timeout,
  cancelled,
  validation,
  conflict,
  unauthorized,
  forbidden,
  notFound,
  server,
  unknown,
}

class ApiError implements Exception {
  const ApiError(
    this.kind,
    this.message, {
    this.status,
    this.fields = const {},
  });
  final ApiErrorKind kind;
  final String message;
  final int? status;
  final Map<String, String> fields;
  bool get canRetry => [
    ApiErrorKind.network,
    ApiErrorKind.timeout,
    ApiErrorKind.server,
  ].contains(kind);
  factory ApiError.fromDio(DioException error) {
    if (CancelToken.isCancel(error)) {
      return const ApiError(ApiErrorKind.cancelled, 'Запрос отменён');
    }
    if ([
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ].contains(error.type)) {
      return const ApiError(
        ApiErrorKind.timeout,
        'Сервер не ответил вовремя. Проверьте соединение и повторите запрос.',
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return const ApiError(
        ApiErrorKind.network,
        'Нет соединения с сервером. Проверьте доступ к интернету.',
      );
    }
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final data = body is Map ? body : <String, dynamic>{};
    var details = data['details'];
    if (details is String) {
      try {
        details = jsonDecode(details);
      } on FormatException {
        details = null;
      }
    }
    final fields = details is Map
        ? details.map((k, v) => MapEntry('$k', '$v'))
        : <String, String>{};
    final code = data['error_code'] ?? data['code'];
    var message = 'Не удалось выполнить запрос. Повторите попытку.';
    if (code == 'invalid_credentials') {
      message = 'Неверная почта или пароль.';
    } else if (code == 'email_not_confirmed') {
      message = 'Подтвердите почту по ссылке из письма.';
    } else if (code == 'user_already_exists' || code == 'email_exists') {
      message = 'Этот адрес уже зарегистрирован. Войдите в аккаунт.';
      fields['email'] = 'Этот адрес уже зарегистрирован';
    } else if (code == 'weak_password') {
      message =
          'Пароль недостаточно надёжен. Используйте более длинный пароль.';
      fields['password'] = 'Используйте более надёжный пароль';
    } else if (code == 'email_address_invalid') {
      message = 'Проверьте адрес электронной почты.';
      fields['email'] = 'Некорректный адрес';
    } else if (status == 429) {
      message = 'Слишком много попыток. Подождите и повторите.';
    } else if (code is String && code.startsWith('TR')) {
      message = '${data['message']}';
    } else if (status == 403) {
      message =
          'Доступ запрещён сервером. У вашей учётной записи нет нужных прав.';
    } else if (status == 401) {
      message = 'Сессия истекла. Войдите снова.';
    } else if (status == 404) {
      message = 'Запись не найдена или недоступна.';
    } else if (status == 409) {
      message = 'Запись уже существует или связана с другими данными.';
    } else if (status == 422 || status == 400) {
      message = 'Проверьте введённые данные и параметры фильтров.';
    } else if (status != null && status >= 500) {
      message = 'Сервис временно недоступен. Повторите запрос позднее.';
    }
    return ApiError(
      switch (status) {
        401 => ApiErrorKind.unauthorized,
        403 => ApiErrorKind.forbidden,
        404 => ApiErrorKind.notFound,
        409 => ApiErrorKind.conflict,
        422 => ApiErrorKind.validation,
        _ =>
          status != null && status >= 500
              ? ApiErrorKind.server
              : ApiErrorKind.unknown,
      },
      message,
      status: status,
      fields: fields,
    );
  }
  @override
  String toString() => message;
}
