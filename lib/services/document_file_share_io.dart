import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Saves the file, then opens the system sheet so the user can keep a copy.
Future<void> shareDocumentBytes({
  required Uint8List bytes,
  required String fileName,
  String? mimeType,
  Rect? sharePositionOrigin,
}) async {
  final dir = await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[\\/]+'), '_');
  final file = File('${dir.path}${Platform.pathSeparator}$safeName');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: mimeType, name: safeName)],
    subject: safeName,
    sharePositionOrigin: sharePositionOrigin,
  );
}
