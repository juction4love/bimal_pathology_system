// lib/core/errors/app_error.dart
class AppError implements Exception {
  final String message;
  AppError(this.message);
  @override
  String toString() => 'AppError: $message';
}
