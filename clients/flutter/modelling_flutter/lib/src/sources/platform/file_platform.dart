// file_platform.dart: picks the file half for the platform, so the package
// builds for the web (no dart:io) and desktop (design §7.6).

export 'file_platform_stub.dart'
    if (dart.library.io) 'file_platform_io.dart'
    if (dart.library.js_interop) 'file_platform_web.dart';
