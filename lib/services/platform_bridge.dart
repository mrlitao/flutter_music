export 'platform_bridge_stub.dart'
    if (dart.library.io) 'platform_bridge_io.dart'
    if (dart.library.js_interop) 'platform_bridge_web.dart';
