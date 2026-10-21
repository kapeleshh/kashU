/// Hands a generated file (backup JSON, tax CSV, tax PDF) to the user.
///
/// The two implementations differ only in what "hand over" means. On
/// mobile/desktop the bytes become a real file in the documents directory and
/// then go into the OS share sheet. In a browser there is no filesystem to
/// write to, so they become a blob the browser downloads.
///
/// This split exists because `dart:io` and `path_provider` *compile* on web
/// and then throw at runtime — `getApplicationDocumentsDirectory()` has no web
/// implementation and `File` writes raise `UnsupportedError` under dart2js.
/// That is precisely how web export used to fail, silently, into a
/// "Export failed:" SnackBar. Keep both imports confined to `file_saver_io`.
library;

export 'file_saver_io.dart'
    if (dart.library.js_interop) 'file_saver_web.dart';
