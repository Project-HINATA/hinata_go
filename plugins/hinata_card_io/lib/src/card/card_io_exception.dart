class CardIoException implements Exception {
  final CardIoErrorType type;
  final String message;
  final dynamic originalError;

  CardIoException({
    required this.type,
    required this.message,
    this.originalError,
  });

  @override
  String toString() => 'CardIoException($type): $message';
}

enum CardIoErrorType {
  timeout,
  authFailed,
  readError,
  writeError,
  unsupportedCard,
  deviceDisconnected,
  unknown,
}
