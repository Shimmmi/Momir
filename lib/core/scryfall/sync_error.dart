import 'package:dio/dio.dart';

/// Short Russian text for a failed card sync. Hides Dio's English dump.
String syncErrorMessage(Object error) {
  if (error is StateError && error.message.isNotEmpty) return error.message;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return 'Нет ответа от Scryfall. Проверьте интернет и повторите.';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        if (code == null) return 'Scryfall ответил ошибкой. Повторите позже.';
        return 'Scryfall ответил ошибкой $code. Повторите позже.';
      default:
        return 'Не удалось связаться со Scryfall. Повторите позже.';
    }
  }
  return 'Не удалось обновить карты. Повторите позже.';
}

bool isRetryableSyncError(Object error) {
  if (error is! DioException) return false;
  final code = error.response?.statusCode ?? 0;
  return error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.connectionError ||
      code >= 500;
}
