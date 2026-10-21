import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [bytes] into the app documents directory as [filename], then opens
/// the platform share sheet so the user can send it on.
///
/// [subject] is the share-sheet subject line (used by mail clients); on web it
/// has no equivalent and is ignored.
Future<void> saveAndShare({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  required String subject,
}) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes);

  await Share.shareXFiles(
    [XFile(file.path, mimeType: mimeType)],
    subject: subject,
    sharePositionOrigin: _popoverAnchor(),
  );
}

/// iPad presents the share sheet as a popover and UIKit requires an anchor
/// rect; omitting it throws. There is no BuildContext here, so anchor to the
/// upper middle of the window, which is where a popover reads naturally.
/// Returns null when no view is attached (and on phones, where it is ignored).
Rect? _popoverAnchor() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return null;
  final view = views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 3),
    width: 1,
    height: 1,
  );
}
