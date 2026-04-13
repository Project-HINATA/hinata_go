import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../../models/card/scanned_card.dart';

/// Represents connection state of the hardware device
enum DeviceConnectionState { disconnected, connecting, connected, error }

/// Abstract base class for physical or internal card readers.
abstract class DeviceInterface {
  /// Unique identifier or path for the device
  String get deviceId;

  /// Human readable product name
  String get productName;

  /// Current connection state
  ValueNotifier<DeviceConnectionState> get connectionState;

  /// Connects to the device
  Future<void> connect();

  /// Disconnects from the device
  Future<void> disconnect();

  /// Subscribe to NFC/Cardio input events.
  /// Implementations will listen to their respective hardware APIs (NFCKit, USB HID)
  /// and stream arrays of bytes representing card data.
  Stream<List<int>> get cardioInputStream;

  // -----------------------------------------------------
  // HINATA Specific Hardware API Configuration Methods
  // (Optional or throws UnsupportedError for non-HINATA devices like raw phone NFC)
  // -----------------------------------------------------

  /// Enters bootloader mode for firmware flashing
  Future<void> enterBootloader() async =>
      throw UnsupportedError('Not supported');

  /// Set device indicator LEDs
  Future<void> setLed(Color color) async =>
      throw UnsupportedError('Not supported');

  /// Retrieve the firmware version timestamp
  Future<int> getFirmTimeStamp() async =>
      throw UnsupportedError('Not supported');

  /// Retrieve internal chip ID
  Future<List<int>> getChipId() async =>
      throw UnsupportedError('Not supported');

  /// Write lower-level command configurations
  Future<void> setConfig(int index, int value) async =>
      throw UnsupportedError('Not supported');

  /// Read lower-level command configurations
  Future<int> getConfig(int index) async =>
      throw UnsupportedError('Not supported');

  /// Low level req/res byte sending (mainly for firmware and PN532 wrapper)
  Future<List<int>> sendCommand(
    int command,
    List<int> payload, {
    int timeoutMs = 1000,
  }) async => throw UnsupportedError('Not supported');

  /// Unified polling for NFC cards.
  Future<ScannedCard?> poll() async =>
      throw UnsupportedError('Polling not supported');

  /// Close and clean up resources
  void dispose();
}
