import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class MyApp extends StatelessWidget {
  final fontName = 'Mulish-Regular';
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';

    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: fontName),
      home: Scaffold(),
    );
  }
}
