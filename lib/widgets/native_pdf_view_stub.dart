import 'package:flutter/widgets.dart';

/// Phones and tests use the in-app PDF renderer unless a platform file replaces this.
bool preferNativePdfStream() => false;

Widget buildNativePdfView({
  required String url,
  required Map<String, String> headers,
}) {
  return const SizedBox.shrink();
}

Widget? buildCachedPdfView(List<int> bytes) => null;
