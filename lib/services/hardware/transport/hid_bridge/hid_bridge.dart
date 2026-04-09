import 'hid_bridge_stub.dart'
    if (dart.library.js_interop) 'hid_bridge_web.dart'
    if (dart.library.io) 'hid_bridge_native.dart';

export 'hid_bridge_interface.dart';

final hid = createHID();

const bridgeVendorId = 0xF822;
