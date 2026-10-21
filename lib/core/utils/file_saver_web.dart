import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [bytes] named [filename].
///
/// There is no filesystem and no share sheet in a browser, so the bytes become
/// an object URL behind a synthetic anchor click. The anchor is attached to the
/// document before clicking because Safari — including iOS Safari, the main
/// target here — ignores clicks on anchors that are not in the DOM. The object
/// URL is revoked straight after so the blob is not pinned for the life of the
/// tab.
///
/// [subject] exists only to match the io signature; a download has no subject.
Future<void> saveAndShare({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  required String subject,
}) async {
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  web.URL.revokeObjectURL(url);
}
