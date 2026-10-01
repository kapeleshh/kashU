import 'dart:io';
import 'dart:typed_data';

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
  );
}
