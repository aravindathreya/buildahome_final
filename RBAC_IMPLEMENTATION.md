# RBAC Implementation Guide

## Overview
Role-Based Access Control (RBAC) has been implemented across the application based on the permissions table provided. The system ensures that users only see and can access features they have permissions for.

## Files Created/Modified

### 1. RBAC Service (`lib/services/rbac_service.dart`)
- Central service managing all role-based permissions
- Maps roles to features and their allowed actions (upload, edit, view, complete_task)
- Provides both async and sync methods for permission checks

### 2. AdminDashboard (`lib/AdminDashboard.dart`)
- Updated `getMenuItems()` to filter menu items based on RBAC
- Only shows features the user has view permission for

### 3. UserDashboard (`lib/UserDashboard.dart`)
- Updated `getMenuItems()` to filter menu items based on RBAC
- Stores current role in state for permission checks
- Only shows features the user has view permission for

### 4. Permission Wrapper Widget (`lib/widgets/permission_wrapper.dart`)
- Reusable widgets for conditional rendering based on permissions
- `PermissionWrapper` - async permission checks
- `PermissionWrapperSync` - sync permission checks when role is available

## How to Use RBAC in Feature Screens

### Example 1: Check Upload Permission
```dart
import 'services/rbac_service.dart';

// In your widget
Future<void> _handleUpload() async {
  final rbac = RBACService();
  bool canUpload = await rbac.canUpload(RBACService.gallery);
  
  if (!canUpload) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('You do not have permission to upload')),
    );
    return;
  }
  
  // Proceed with upload
}
```

### Example 2: Conditionally Show Upload Button
```dart
import 'widgets/permission_wrapper.dart';

// In your build method
PermissionWrapper(
  feature: RBACService.gallery,
  permission: RBACService.upload,
  child: FloatingActionButton(
    onPressed: () => _uploadImage(),
    child: Icon(Icons.add),
  ),
)
```

### Example 3: Sync Permission Check (when role is available)
```dart
import 'services/rbac_service.dart';

// In your widget
String? currentRole = 'Site Engineer'; // Get from SharedPreferences

Widget build(BuildContext context) {
  final rbac = RBACService();
  
  return Column(
    children: [
      // Show edit button only if user can edit
      if (rbac.canEditSync(currentRole, RBACService.documents))
        IconButton(
          icon: Icon(Icons.edit),
          onPressed: () => _editDocument(),
        ),
    ],
  );
}
```

## Features and Permission Types

### Features
- `daily_update` - Daily Update
- `indent` - Indents
- `payments` - Payments
- `documents` - Documents
- `scheduler` - Scheduler
- `gallery` - Gallery
- `tasks_and_notes` - Tasks & Notes
- `checklist` - Checklist
- `request_drawing` - Request Drawing
- `add_report_remarks` - Add Report Remarks

### Permission Types
- `upload` - Can upload/create new items
- `edit` - Can edit existing items
- `view` - Can view items
- `complete_task` - Can complete tasks (for Tasks & Notes)

## Role Mappings

The RBAC service automatically normalizes role names:
- "Project Co-ordinator" → "Project Coordinator"
- "Junior Architect" → "Jr. Arch"
- "Senior Architect" → "Sr. Arch"
- "Architect" → "Sr. Arch"

## Admin Role

Admin users have all permissions for all features. This is handled automatically by the RBAC service.

## Next Steps for Feature Screens

To add permission checks in individual feature screens:

1. **Import the RBAC service:**
   ```dart
   import 'services/rbac_service.dart';
   ```

2. **Check permissions before actions:**
   - Before showing upload buttons
   - Before allowing edits
   - Before showing sensitive data

3. **Use PermissionWrapper for UI elements:**
   ```dart
   PermissionWrapper(
     feature: RBACService.payments,
     permission: RBACService.upload,
     child: UploadButton(),
   )
   ```

## Testing

Test with different user roles to ensure:
- Menu items are filtered correctly
- Upload buttons only show when user has upload permission
- Edit buttons only show when user has edit permission
- View-only users can only view content

## Notes

- Site Engineer: Should only see features in assigned projects (handled by project assignment logic)
- Project Coordinator: For all projects assigned under them
- All other roles: Based on their role permissions as defined in the table

