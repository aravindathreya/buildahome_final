import 'package:flutter/material.dart';

get_button_decoration() {
  return BoxDecoration(
      color: Colors.white,
      border: Border.all(color: Colors.grey[300]),
      borderRadius: BorderRadius.circular(5)
  );
}

get_button_text_style() {
  return TextStyle(fontSize: 16,
      fontWeight: FontWeight.normal);
}


get_header_text_style() {
  return TextStyle(fontSize: 22,
      fontWeight: FontWeight.bold);
}