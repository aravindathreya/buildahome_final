import 'package:flutter/material.dart';
import '../app_theme.dart';

get_button_decoration() {
  return BoxDecoration(
    color: Colors.white,
    border: Border.all(color: AppTheme.border),
    borderRadius: BorderRadius.circular(12),
    boxShadow: const [
      BoxShadow(
        color: AppTheme.softShadow,
        blurRadius: 10,
        offset: Offset(0, 4),
      ),
    ],
  );
}

get_button_text_style() {
  return const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppTheme.navy,
  );
}

get_header_text_style() {
  return const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: AppTheme.navy,
    letterSpacing: -0.2,
  );
}
