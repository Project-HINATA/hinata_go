# quick_usb

A cross-platform (Android/Windows/macOS/Linux) USB plugin for Flutter, with **background-thread streaming support** for high-performance, non-blocking bulk transfers.

## Features

- 📱 **Android** — via Android USB Host API (MethodChannel + EventChannel)
- 🖥️ **Desktop** (Windows/macOS/Linux) — via libusb FFI bindings
- 🚀 **Streaming Bulk Transfer** — dedicated native background thread for continuous USB reads without blocking the UI
- 🔌 Standard USB operations: device enumeration, permissions, open/close, configuration, bulk transfer

## Installation

```yaml
dependencies:
  quick_usb:
    path: ../quick.flutter/packages/quick_usb  # or your local path
```

## Quick Start

```dart
import 'package:quick_usb/quick_usb.dart';

// Initialize
await QuickUsb.init();

// List devices
final devices = await QuickUsb.getDeviceList();
print('Found ${devices.length} USB devices');

// Open a device
final device = devices.first;
await QuickUsb.openDevice(device);

// Clean up
await QuickUsb.closeDevice();
await QuickUsb.exit();
```

## API Reference

### Device Management

#### `QuickUsb.init()`
Initialize the USB subsystem. Call this before any other operations.

```dart
final success = await QuickUsb.init();
```

#### `QuickUsb.exit()`
Clean up and release USB resources.

```dart
await QuickUsb.exit();
```

#### `QuickUsb.getDeviceList()`
Enumerate all connected USB devices.

```dart
final List<UsbDevice> devices = await QuickUsb.getDeviceList();
for (final device in devices) {
  print('VID: 0x${device.vendorId.toRadixString(16)}, '
        'PID: 0x${device.productId.toRadixString(16)}');
}
```

#### `QuickUsb.getDeviceDescription(device)`
Get human-readable device information (manufacturer, product name, serial).

```dart
final desc = await QuickUsb.getDeviceDescription(device);
print('${desc.manufacturer} - ${desc.product} (${desc.serialNumber})');
```

#### `QuickUsb.hasPermission(device)` / `QuickUsb.requestPermission(device)`
Check and request USB permissions (Android only; always returns `true` on desktop).

```dart
if (!await QuickUsb.hasPermission(device)) {
  await QuickUsb.requestPermission(device);
}
```

#### `QuickUsb.openDevice(device)` / `QuickUsb.closeDevice()`
Open/close a USB device connection.

```dart
final opened = await QuickUsb.openDevice(device);
// ... use device ...
await QuickUsb.closeDevice();
```

---

### Configuration & Interfaces

#### `QuickUsb.getConfiguration(index)`
Get a device's USB configuration by index.

```dart
final config = await QuickUsb.getConfiguration(0);
for (final intf in config.interfaces) {
  print('Interface ${intf.id}, class: ${intf.interfaceClass}');
  for (final ep in intf.endpoints) {
    final dir = ep.direction == UsbEndpoint.DIRECTION_IN ? 'IN' : 'OUT';
    print('  Endpoint ${ep.endpointNumber} ($dir)');
  }
}
```

#### `QuickUsb.claimInterface(interface)` / `QuickUsb.releaseInterface(interface)`
Claim/release exclusive access to an interface.

```dart
final config = await QuickUsb.getConfiguration(0);
final intf = config.interfaces.first;
await QuickUsb.claimInterface(intf);
// ... transfer data ...
await QuickUsb.releaseInterface(intf);
```

---

### Bulk Transfers (One-Shot)

For single request-response patterns.

#### `QuickUsb.bulkTransferIn(endpoint, maxLength, {timeout})`
Read data from a bulk IN endpoint.

```dart
final UsbEndpoint inEndpoint = ...;  // direction == DIRECTION_IN
final Uint8List data = await QuickUsb.bulkTransferIn(inEndpoint, 64, timeout: 1000);
print('Received ${data.length} bytes');
```

#### `QuickUsb.bulkTransferOut(endpoint, data, {timeout})`
Write data to a bulk OUT endpoint.

```dart
final UsbEndpoint outEndpoint = ...;  // direction == DIRECTION_OUT
final bytes = Uint8List.fromList([0x01, 0x02, 0x03]);
final written = await QuickUsb.bulkTransferOut(outEndpoint, bytes, timeout: 1000);
print('Wrote $written bytes');
```

---

### 🚀 Streaming Bulk Transfer (Background Thread)

**This is the key feature for high-performance USB communication.**

When you need to continuously read from a USB device (e.g., HID input reports, sensor data, card reader events), the standard `bulkTransferIn` approach requires a polling loop that blocks the Flutter UI thread on Android, causing severe lag and frame drops.

`bulkTransferInStream` solves this by running USB reads on a **dedicated native background thread** and pushing data to Dart via an `EventChannel`.

#### `QuickUsb.bulkTransferInStream(endpoint, maxLength, {timeout})`
Start a background bulk read loop and return a `Stream<Uint8List>`.

```dart
final UsbEndpoint readEndpoint = ...;  // direction == DIRECTION_IN

// Start streaming — USB reads happen on a native background thread
final Stream<Uint8List> usbStream = QuickUsb.bulkTransferInStream(
  readEndpoint,
  64,        // max packet size
  timeout: 50, // native read timeout in ms (controls responsiveness)
);

// Listen for data — callbacks run on Dart's main isolate, safe for UI updates
final subscription = usbStream.listen((Uint8List data) {
  print('Received ${data.length} bytes: $data');
  // Safe to call setState(), update providers, etc.
});
```

#### `QuickUsb.stopBulkTransferInStream()`
Stop the background read thread and clean up resources.

```dart
await subscription.cancel();
await QuickUsb.stopBulkTransferInStream();
```

#### How It Works

| Platform | Mechanism | UI Thread Blocked? |
|----------|-----------|-------------------|
| **Android** | `ExecutorService` background thread + `EventChannel` | ❌ Never |
| **Desktop** | Async polling loop with libusb (FFI is non-blocking) | ❌ Never |

**Android architecture:**

```
┌─────────────────────────────────────────┐
│          Kotlin (Native Side)           │
│                                         │
│  ExecutorService (background thread)    │
│  ┌─────────────────────────────────┐    │
│  │  while (reading) {              │    │
│  │    bytes = bulkTransfer(ep,     │    │
│  │              buffer, timeout);  │    │
│  │    if (bytes > 0)               │    │
│  │      handler.post {             │    │
│  │        eventSink.success(data)  │──────► EventChannel
│  │      }                          │    │
│  │  }                              │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│           Dart (Flutter Side)           │
│                                         │
│  EventChannel.receiveBroadcastStream()  │
│       │                                 │
│       ▼                                 │
│  Stream<Uint8List> ──► your .listen()   │
│                         callback        │
└─────────────────────────────────────────┘
```

#### Timeout Parameter

The `timeout` parameter controls the native `bulkTransfer` read timeout in milliseconds:

| Value | Behavior |
|-------|----------|
| **`50` (default)** | Good balance of responsiveness and CPU usage. Recommended for HID devices. |
| `10-30` | Lower latency, slightly higher CPU. Use for real-time applications. |
| `100-500` | Lower CPU usage, but higher latency when device stops sending. |
| `0` | Infinite wait — thread blocks until data arrives. Only use if you're sure the device will always send data. |

---

## Complete Example: HID Device Reader

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:quick_usb/quick_usb.dart';

class UsbHidReader {
  UsbEndpoint? _readEndpoint;
  UsbEndpoint? _writeEndpoint;
  StreamSubscription<Uint8List>? _readSubscription;

  Future<bool> connect(int vendorId) async {
    await QuickUsb.init();

    final devices = await QuickUsb.getDeviceList();
    final device = devices.firstWhere(
      (d) => d.vendorId == vendorId,
      orElse: () => throw Exception('Device not found'),
    );

    // Request permission (Android)
    if (!await QuickUsb.hasPermission(device)) {
      await QuickUsb.requestPermission(device);
    }

    // Open device
    if (!await QuickUsb.openDevice(device)) {
      throw Exception('Failed to open device');
    }

    // Probe endpoints
    final config = await QuickUsb.getConfiguration(0);
    for (final intf in config.interfaces) {
      if (await QuickUsb.claimInterface(intf)) {
        for (final ep in intf.endpoints) {
          if (ep.direction == UsbEndpoint.DIRECTION_IN) {
            _readEndpoint = ep;
          } else if (ep.direction == UsbEndpoint.DIRECTION_OUT) {
            _writeEndpoint = ep;
          }
        }
      }
    }

    if (_readEndpoint == null || _writeEndpoint == null) {
      throw Exception('Could not find suitable endpoints');
    }

    return true;
  }

  /// Start listening for HID input reports via background thread stream.
  void startListening(void Function(Uint8List data) onData) {
    final stream = QuickUsb.bulkTransferInStream(
      _readEndpoint!,
      64,
      timeout: 50,
    );

    _readSubscription = stream.listen(onData);
  }

  /// Send a HID output report.
  Future<void> sendReport(Uint8List data) async {
    if (_writeEndpoint != null) {
      await QuickUsb.bulkTransferOut(_writeEndpoint!, data);
    }
  }

  /// Clean up everything.
  Future<void> disconnect() async {
    _readSubscription?.cancel();
    _readSubscription = null;
    await QuickUsb.stopBulkTransferInStream();
    await QuickUsb.closeDevice();
  }
}

// Usage:
void main() async {
  final reader = UsbHidReader();
  await reader.connect(0xF822); // Your device's vendor ID

  reader.startListening((data) {
    print('Report: ${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
  });

  // Send a command
  await reader.sendReport(Uint8List.fromList([0x01, 0x00, 0x00]));

  // Later...
  // await reader.disconnect();
}
```

## Migration Guide

### From polling loop to streaming

**Before (blocks UI thread on Android):**
```dart
// ❌ Bad: blocks Flutter UI thread
void _startReadLoop() {
  Future.doWhile(() async {
    final data = await QuickUsb.bulkTransferIn(endpoint, 64, timeout: 500);
    if (data.isNotEmpty) processData(data);
    return _running;
  });
}
```

**After (background thread, zero UI impact):**
```dart
// ✅ Good: reads happen on native background thread
void _startReadStream() {
  _subscription = QuickUsb.bulkTransferInStream(endpoint, 64, timeout: 50)
    .listen((data) {
      processData(data); // runs on main isolate, safe for UI
    });
}

// Don't forget to clean up
void _stopReadStream() async {
  await _subscription?.cancel();
  await QuickUsb.stopBulkTransferInStream();
}
```

### Key differences

| Aspect | `bulkTransferIn` (polling) | `bulkTransferInStream` |
|--------|---------------------------|----------------------|
| Thread | Flutter UI thread (Android) | Native background thread |
| Pattern | Pull (you call it in a loop) | Push (data comes to you) |
| UI impact | ⚠️ Blocks rendering | ✅ Zero impact |
| CPU usage | High (tight loop + MethodChannel overhead) | Low (thread sleeps during timeout) |
| Best for | Single request-response | Continuous reading |

## Data Types

### `UsbDevice`
```dart
class UsbDevice {
  String identifier;
  int vendorId;
  int productId;
  int configurationCount;
}
```

### `UsbEndpoint`
```dart
class UsbEndpoint {
  int endpointNumber;
  int direction;     // DIRECTION_IN (0x80) or DIRECTION_OUT (0x00)
  int type;
  int maxPacketSize;
}
```

### `UsbConfiguration`
```dart
class UsbConfiguration {
  int id;
  int index;
  List<UsbInterface> interfaces;
}
```

### `UsbInterface`
```dart
class UsbInterface {
  int id;
  int alternateSetting;
  int interfaceClass;
  int interfaceSubclass;
  int interfaceProtocol;
  List<UsbEndpoint> endpoints;
}
```

## Platform Notes

### Android
- Requires `<uses-feature android:name="android.hardware.usb.host" />` in `AndroidManifest.xml`
- USB permissions are handled via `hasPermission()` / `requestPermission()`  
- For auto-open on USB attach, add an intent filter + `usb_device_filter.xml`
- `bulkTransferInStream` uses `java.util.concurrent.ExecutorService` for true multi-threading

### Desktop (Windows/macOS/Linux)
- Uses libusb 1.0.23 via FFI
- Permissions are always granted (`hasPermission()` returns `true`)
- `bulkTransferInStream` uses an async polling loop (libusb FFI doesn't block the platform thread)

## License

See [LICENSE](LICENSE) file.
