import 'dart:typed_data';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// Browser share / download. There is no app documents folder on web.
Future<void> shareDocumentBytes({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
  Rect? sharePositionOrigin,
}) async {
  await Share.shareXFiles(
    [
      XFile.fromData(
        bytes,
        name: fileName,
        mimeType: mimeType,
      ),
    ],
    subject: fileName,
    sharePositionOrigin: sharePositionOrigin,
  );
}
