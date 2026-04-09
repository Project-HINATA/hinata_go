import 'dart:typed_data';

abstract class NfcTransceiver {
  /// Sends raw data and receives a response.
  Future<Uint8List> transceive(Uint8List data, {Duration? timeout});

  /// Authenticate a Mifare sector or block.
  Future<void> authenticateMifare({
    required Uint8List uid,
    required int block,
    Uint8List? keyA,
    Uint8List? keyB,
  });

  /// Reads a single block from a Mifare card.
  Future<Uint8List> readMifareBlock(int block);

  /// Closes the connection (if applicable).
  Future<void> close();
}
