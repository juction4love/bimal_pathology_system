// lib/core/errors/errors.dart

class AppError implements Exception {
  final String message;
  AppError(this.message);
  @override
  String toString() => 'AppError: $message';
}
