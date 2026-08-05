import 'package:flutter/material.dart';
import 'widgets/skeleton_loader.dart';

class Loader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 280,
        child: SkeletonBlockLoader(),
      ),
    );
  }
}
