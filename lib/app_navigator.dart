import 'package:flutter/material.dart';

/// Shared navigation / snackbar keys for app-wide flows (e.g. session logout).
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> globalScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
