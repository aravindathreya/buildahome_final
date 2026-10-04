import 'package:flutter/material.dart';
import '../services/rbac_service.dart';

/// A widget that shows its child only if the user has the required permission
class PermissionWrapper extends StatelessWidget {
  final String feature;
  final String permission;
  final Widget child;
  final Widget? fallback;

  const PermissionWrapper({
    Key? key,
    required this.feature,
    required this.permission,
    required this.child,
    this.fallback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _checkPermission(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox.shrink(); // Or a loading indicator
        }
        if (snapshot.data == true) {
          return child;
        }
        return fallback ?? SizedBox.shrink();
      },
    );
  }

  Future<bool> _checkPermission() async {
    final rbac = RBACService();
    return await rbac.hasPermission(feature, permission);
  }
}

/// A widget that conditionally shows content based on sync permission check
/// Use this when you already have the role available
class PermissionWrapperSync extends StatelessWidget {
  final String? role;
  final String feature;
  final String permission;
  final Widget child;
  final Widget? fallback;

  const PermissionWrapperSync({
    Key? key,
    required this.role,
    required this.feature,
    required this.permission,
    required this.child,
    this.fallback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final rbac = RBACService();
    if (rbac.hasPermissionSync(role, feature, permission)) {
      return child;
    }
    return fallback ?? SizedBox.shrink();
  }
}

/// Helper extension for easy permission checks
extension PermissionCheck on BuildContext {
  Future<bool> canUpload(String feature) async {
    final rbac = RBACService();
    return await rbac.canUpload(feature);
  }

  Future<bool> canEdit(String feature) async {
    final rbac = RBACService();
    return await rbac.canEdit(feature);
  }

  Future<bool> canView(String feature) async {
    final rbac = RBACService();
    return await rbac.canView(feature);
  }
}

