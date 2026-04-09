import 'usb_bridge_stub.dart'
    if (dart.library.js_interop) 'usb_bridge_web.dart'
    if (dart.library.io) 'usb_bridge_native.dart';

export 'usb_bridge_interface.dart';

final usb = createUSB();
