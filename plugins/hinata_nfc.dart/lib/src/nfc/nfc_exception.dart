class NfcException implements Exception {
  final NfcErrorType type;
  final String message;
  final dynamic originalError;

  NfcException({required this.type, required this.message, this.originalError});

  @override
  String toString() => 'NfcException($type): $message';
}

enum NfcErrorType {
  timeout,
  authFailed,
  readError,
  writeError,
  unsupportedCard,
  deviceDisconnected,
  unknown,
}
