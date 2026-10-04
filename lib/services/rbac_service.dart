import 'package:shared_preferences/shared_preferences.dart';

/// Role-Based Access Control Service
/// Manages permissions for different user roles based on the permissions table
class RBACService {
  static final RBACService _instance = RBACService._internal();
  factory RBACService() => _instance;
  RBACService._internal();

  // Permission types
  static const String upload = 'upload';
  static const String edit = 'edit';
  static const String view = 'view';
  static const String delete = 'delete';
  static const String completeTask = 'complete_task';

  // Feature names
  static const String dailyUpdate = 'daily_update';
  static const String indent = 'indent';
  static const String payments = 'payments';
  static const String documents = 'documents';
  static const String scheduler = 'scheduler';
  static const String gallery = 'gallery';
  static const String tasksAndNotes = 'tasks_and_notes';
  static const String checklist = 'checklist';
  static const String requestDrawing = 'request_drawing';
  static const String addReportRemarks = 'add_report_remarks';
  static const String inspectionRequest = 'inspection_request';

  // Role mappings (normalized to match stored role values)
  // Note: Case-insensitive matching is handled by _normalizeRoleString
  // These explicit mappings are for common variations and faster lookups
  static const Map<String, String> roleMapping = {
    'Site Engineer': 'Site Engineer',
    'site engineer': 'Site Engineer',
    'SITE ENGINEER': 'Site Engineer',
    'Project Co-ordinator': 'Project Coordinator',
    'Project Coordinator': 'Project Coordinator',
    'project coordinator': 'Project Coordinator',
    'PROJECT COORDINATOR': 'Project Coordinator',
    'Project Head': 'Project Head',
    'project head': 'Project Head',
    'PROJECT HEAD': 'Project Head',
    'PH': 'Project Head',
    'ph': 'Project Head',
    'Project Manager': 'Project Manager',
    'project manager': 'Project Manager',
    'PROJECT MANAGER': 'Project Manager',
    'PM': 'Project Manager',
    'pm': 'Project Manager',
    'Assistant Project Coordinator': 'Assistant Project Coordinator',
    'assistant project coordinator': 'Assistant Project Coordinator',
    'ASSISTANT PROJECT COORDINATOR': 'Assistant Project Coordinator',
    'APCC': 'Assistant Project Coordinator',
    'apcc': 'Assistant Project Coordinator',
    'Sr Manager': 'Sr Manager',
    'sr manager': 'Sr Manager',
    'SR MANAGER': 'Sr Manager',
    'Structural Engineer': 'Structural Engineer',
    'structural engineer': 'Structural Engineer',
    'STRUCTURAL ENGINEER': 'Structural Engineer',
    'Structural head': 'Structural Engineer',
    'structural head': 'Structural Engineer',
    'Structural designer': 'Structural Engineer',
    'structural designer': 'Structural Engineer',
    'Quality Engineer': 'Quality Engineer',
    'quality engineer': 'Quality Engineer',
    'QUALITY ENGINEER': 'Quality Engineer',
    'QA/QC': 'Quality Engineer',
    'qa/qc': 'Quality Engineer',
    'MEP engineer': 'MEP engineer',
    'mep engineer': 'MEP engineer',
    'MEP ENGINEER': 'MEP engineer',
    'MEP Head': 'MEP engineer',
    'mep head': 'MEP engineer',
    'Electrical Engineer': 'MEP engineer',
    'electrical engineer': 'MEP engineer',
    'PHE Engineer': 'MEP engineer',
    'phe engineer': 'MEP engineer',
    'Jr. Arch': 'Jr. Arch',
    'jr. arch': 'Jr. Arch',
    'Junior Architect': 'Jr. Arch',
    'junior architect': 'Jr. Arch',
    'Sr. Arch': 'Sr. Arch',
    'sr. arch': 'Sr. Arch',
    'Senior Architect': 'Sr. Arch',
    'senior architect': 'Sr. Arch',
    'Architect': 'Sr. Arch', // Default architect to Sr. Arch
    'architect': 'Sr. Arch',
    'Safety': 'Safety',
    'safety': 'Safety',
    'SAFETY': 'Safety',
    'Client': 'Client',
    'client': 'Client',
    'CLIENT': 'Client',
    'Billing': 'Billing',
    'billing': 'Billing',
    'BILLING': 'Billing',
    'QS Head': 'QS Head',
    'qs head': 'QS Head',
    'QS HEAD': 'QS Head',
    'QS Engineer': 'QS Engineer',
    'qs engineer': 'QS Engineer',
    'QS ENGINEER': 'QS Engineer',
    'QS Engineer (QS INFO)': 'QS Engineer',
    'qs engineer (qs info)': 'QS Engineer',
    'QS & Contracts': 'QS & Contracts',
    'qs & contracts': 'QS & Contracts',
    'QS & CONTRACTS': 'QS & Contracts',
    'QS & Contracts (QS Engineer)': 'QS & Contracts',
    'Purchase Head': 'Purchase Head',
    'purchase head': 'Purchase Head',
    'PURCHASE HEAD': 'Purchase Head',
    'Purchase executive': 'Purchase Head',
    'purchase executive': 'Purchase Head',
    'PURCHASE EXECUTIVE': 'Purchase Head',
    'Material management': 'Material management',
    'material management': 'Material management',
    'MATERIAL MANAGEMENT': 'Material management',
    'Admin': 'Admin', // Admin has all permissions
    'admin': 'Admin',
    'ADMIN': 'Admin',
  };

  // Permissions matrix based on the table
  // Format: role -> feature -> [permissions]
  static const Map<String, Map<String, List<String>>> permissions = {
    'Site Engineer': {
      dailyUpdate: [upload, edit, view],
      indent: [upload, view], // Edit: N
      payments: [], // All N
      documents: [view],
      scheduler: [view],
      gallery: [upload, edit, view],
      tasksAndNotes: [completeTask, upload, view], // Edit: N
      checklist: [upload, edit, view],
      requestDrawing: [upload, view], // Edit: N
      addReportRemarks: [],
      inspectionRequest: [upload], // Create only - no view permission
    },
    'Project Coordinator': {
      dailyUpdate: [upload, edit, view],
      indent: [upload, edit, view],
      payments: [view],
      documents: [view],
      scheduler: [view],
      gallery: [upload, view], // Edit: N
      tasksAndNotes: [completeTask, edit, view], // Upload: N
      checklist: [upload, edit, view],
      requestDrawing: [upload, view], // Edit: N
      addReportRemarks: [upload], // Y
      inspectionRequest: [upload, view, edit, delete], // C/V/E/D of their team but not assigned by PH
    },
    'Sr Manager': {
      dailyUpdate: [view],
      indent: [edit, view],
      payments: [view],
      documents: [view],
      scheduler: [edit, view],
      gallery: [view],
      tasksAndNotes: [completeTask, upload, edit, view],
      checklist: [view],
      requestDrawing: [view],
      addReportRemarks: [upload], // Y
      inspectionRequest: [view], // View only
    },
    'Structural Engineer': {
      dailyUpdate: [view],
      indent: [],
      payments: [],
      documents: [],
      scheduler: [],
      gallery: [view],
      tasksAndNotes: [upload, edit, view], // Complete task: N
      checklist: [upload, edit, view],
      requestDrawing: [view],
      addReportRemarks: [upload], // Y
      inspectionRequest: [view], // V (whatever is assigned to them/ their team)
    },
    'Quality Engineer': {
      dailyUpdate: [view],
      indent: [],
      payments: [],
      documents: [],
      scheduler: [],
      gallery: [view],
      tasksAndNotes: [upload, edit, view], // Complete task: N
      checklist: [upload, edit, view],
      requestDrawing: [],
      addReportRemarks: [upload], // Y
      inspectionRequest: [view], // V (whatever is assigned to them)
    },
    'MEP engineer': {
      dailyUpdate: [view],
      indent: [],
      payments: [],
      documents: [],
      scheduler: [],
      gallery: [view],
      tasksAndNotes: [upload, edit, view], // Complete task: N
      checklist: [upload, edit, view],
      requestDrawing: [view],
      addReportRemarks: [upload], // Y
      inspectionRequest: [view], // V (whatever is assigned to them/ their team)
    },
    'Jr. Arch': {
      dailyUpdate: [view],
      indent: [],
      payments: [],
      documents: [upload, edit, view],
      scheduler: [],
      gallery: [view],
      tasksAndNotes: [completeTask, upload, edit, view],
      checklist: [],
      requestDrawing: [view],
      addReportRemarks: [upload], // Y
    },
    'Sr. Arch': {
      dailyUpdate: [view],
      indent: [],
      payments: [],
      documents: [upload, edit, view],
      scheduler: [],
      gallery: [view],
      tasksAndNotes: [completeTask, upload, edit, view],
      checklist: [],
      requestDrawing: [view],
      addReportRemarks: [upload], // Y
      inspectionRequest: [view], // V (whatever is assigned to them/ their team)
    },
    'Safety': {
      dailyUpdate: [],
      indent: [],
      payments: [],
      documents: [],
      scheduler: [],
      gallery: [],
      tasksAndNotes: [upload, edit, view], // Complete task: N
      checklist: [],
      requestDrawing: [],
      addReportRemarks: [upload], // Y
      inspectionRequest: [view], // V (whatever is assigned to them)
    },
    'Client': {
      dailyUpdate: [view],
      indent: [],
      payments: [view],
      documents: [view],
      scheduler: [view],
      gallery: [view],
      tasksAndNotes: [completeTask, upload, edit, view],
      checklist: [view],
      requestDrawing: [upload, edit, view],
      addReportRemarks: [],
      inspectionRequest: [upload, view], // C/V tasks created by client only
    },
    'Billing': {
      dailyUpdate: [],
      indent: [], // Hidden for billing role
      payments: [view], // Billing role should have access to payments
      documents: [],
      scheduler: [],
      gallery: [],
      tasksAndNotes: [], // Hidden for billing role
      checklist: [],
      requestDrawing: [],
      addReportRemarks: [],
      inspectionRequest: [], // No access
    },
    // Project Head - C/V/E/D of their team
    'Project Head': {
      dailyUpdate: [upload, edit, view],
      indent: [upload, edit, view],
      payments: [view],
      documents: [view],
      scheduler: [view],
      gallery: [upload, edit, view],
      tasksAndNotes: [completeTask, upload, edit, view],
      checklist: [upload, edit, view],
      requestDrawing: [upload, edit, view],
      addReportRemarks: [upload],
      inspectionRequest: [upload, view, edit, delete], // C/V/E/D of their team
    },
    // Project Manager - Same permissions as Project Head
    'Project Manager': {
      dailyUpdate: [upload, edit, view],
      indent: [upload, edit, view],
      payments: [view],
      documents: [view],
      scheduler: [view],
      gallery: [upload, edit, view],
      tasksAndNotes: [completeTask, upload, edit, view],
      checklist: [upload, edit, view],
      requestDrawing: [upload, edit, view],
      addReportRemarks: [upload],
      inspectionRequest: [upload, view, edit, delete], // C/V/E/D of their team
    },
    // Assistant Project Coordinator - C/V/E of their team but not assigned by PH, PC
    'Assistant Project Coordinator': {
      dailyUpdate: [upload, edit, view],
      indent: [upload, view],
      payments: [view],
      documents: [view],
      scheduler: [view],
      gallery: [upload, view],
      tasksAndNotes: [completeTask, upload, view],
      checklist: [upload, edit, view],
      requestDrawing: [upload, view],
      addReportRemarks: [upload],
      inspectionRequest: [upload, view, edit], // C/V/E of their team but not assigned by PH, PC
    },
    // QS Head - No access
    'QS Head': {
      dailyUpdate: [],
      indent: [],
      payments: [],
      documents: [],
      scheduler: [],
      gallery: [],
      tasksAndNotes: [],
      checklist: [],
      requestDrawing: [],
      addReportRemarks: [],
      inspectionRequest: [], // NA
    },
    // QS Engineer - No access
    'QS Engineer': {
      dailyUpdate: [],
      indent: [],
      payments: [],
      documents: [],
      scheduler: [],
      gallery: [],
      tasksAndNotes: [],
      checklist: [],
      requestDrawing: [],
      addReportRemarks: [],
      inspectionRequest: [], // NA
    },
    // QS & Contracts - V (whatever is assigned to them)
    'QS & Contracts': {
      dailyUpdate: [],
      indent: [],
      payments: [],
      documents: [],
      scheduler: [],
      gallery: [],
      tasksAndNotes: [],
      checklist: [],
      requestDrawing: [],
      addReportRemarks: [],
      inspectionRequest: [view], // V (whatever is assigned to them)
    },
    // Purchase Head - No access
    'Purchase Head': {
      dailyUpdate: [],
      indent: [],
      payments: [],
      documents: [],
      scheduler: [],
      gallery: [],
      tasksAndNotes: [],
      checklist: [],
      requestDrawing: [],
      addReportRemarks: [],
      inspectionRequest: [], // NA
    },
    // Material management - No access
    'Material management': {
      dailyUpdate: [],
      indent: [],
      payments: [],
      documents: [],
      scheduler: [],
      gallery: [],
      tasksAndNotes: [],
      checklist: [],
      requestDrawing: [],
      addReportRemarks: [],
      inspectionRequest: [], // NA
    },
    // Admin has all permissions
    'Admin': {
      dailyUpdate: [upload, edit, view],
      indent: [upload, edit, view],
      payments: [upload, edit, view],
      documents: [upload, edit, view],
      scheduler: [upload, edit, view],
      gallery: [upload, edit, view],
      tasksAndNotes: [completeTask, upload, edit, view],
      checklist: [upload, edit, view],
      requestDrawing: [upload, edit, view],
      addReportRemarks: [upload],
      inspectionRequest: [upload, view, edit, delete],
    },
  };

  /// Normalize a role string for comparison (lowercase, trim spaces, collapse multiple spaces)
  String _normalizeRoleString(String role) {
    return role.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Create a case-insensitive lookup map from roleMapping
  static final Map<String, String> _normalizedRoleMapping = () {
    final Map<String, String> normalized = {};
    roleMapping.forEach((key, value) {
      // Normalize the key for case-insensitive lookup
      final normalizedKey = key.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
      normalized[normalizedKey] = value;
    });
    return normalized;
  }();

  /// Get the normalized role name (case and space insensitive)
  String? _normalizeRole(String? role) {
    if (role == null || role.isEmpty) return null;
    
    // First try direct lookup (for backward compatibility)
    if (roleMapping.containsKey(role)) {
      return roleMapping[role];
    }
    
    // Then try case-insensitive lookup
    final normalizedInput = _normalizeRoleString(role);
    return _normalizedRoleMapping[normalizedInput] ?? role;
  }

  /// Get current user role from SharedPreferences
  Future<String?> getCurrentRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? role = prefs.getString('role');
    return _normalizeRole(role);
  }

  /// Find role key in permissions map (case-insensitive)
  String? _findRoleKey(String role) {
    // First try direct lookup
    if (permissions.containsKey(role)) {
      return role;
    }
    
    // Then try case-insensitive lookup
    final normalizedRole = _normalizeRoleString(role);
    for (final key in permissions.keys) {
      if (_normalizeRoleString(key) == normalizedRole) {
        return key;
      }
    }
    
    return null;
  }

  /// Check if user has a specific permission for a feature
  Future<bool> hasPermission(String feature, String permission) async {
    String? role = await getCurrentRole();
    if (role == null) return false;

    // Admin has all permissions (case-insensitive check)
    if (_normalizeRoleString(role) == _normalizeRoleString('Admin')) return true;

    final roleKey = _findRoleKey(role);
    if (roleKey == null) return false;

    final rolePermissions = permissions[roleKey];
    if (rolePermissions == null) return false;

    final featurePermissions = rolePermissions[feature];
    if (featurePermissions == null) return false;

    return featurePermissions.contains(permission);
  }

  /// Check if user can view a feature (at minimum)
  Future<bool> canView(String feature) async {
    return hasPermission(feature, view);
  }

  /// Check if user can upload for a feature
  Future<bool> canUpload(String feature) async {
    return hasPermission(feature, upload);
  }

  /// Check if user can edit for a feature
  Future<bool> canEdit(String feature) async {
    return hasPermission(feature, edit);
  }

  /// Check if user can complete tasks
  Future<bool> canCompleteTask() async {
    return hasPermission(tasksAndNotes, completeTask);
  }

  /// Check if user can add report remarks
  Future<bool> canAddReportRemarks() async {
    return hasPermission(addReportRemarks, upload);
  }

  /// Check if user can delete for a feature
  Future<bool> canDelete(String feature) async {
    return hasPermission(feature, delete);
  }

  /// Get all permissions for a feature (for the current user)
  Future<List<String>> getFeaturePermissions(String feature) async {
    String? role = await getCurrentRole();
    if (role == null) return [];

    // Admin has all permissions (case-insensitive check)
    if (_normalizeRoleString(role) == _normalizeRoleString('Admin')) {
      return [upload, edit, view, delete, completeTask];
    }

    final roleKey = _findRoleKey(role);
    if (roleKey == null) return [];

    final rolePermissions = permissions[roleKey];
    if (rolePermissions == null) return [];

    return rolePermissions[feature] ?? [];
  }

  /// Check if a feature should be visible in the menu (user has at least view permission)
  Future<bool> isFeatureVisible(String feature) async {
    return canView(feature);
  }

  /// Synchronous version - requires role to be passed
  bool hasPermissionSync(String? role, String feature, String permission) {
    if (role == null) return false;
    
    // Normalize role first
    final normalizedRole = _normalizeRole(role);
    if (normalizedRole == null) return false;

    // Admin has all permissions (case-insensitive check)
    if (_normalizeRoleString(normalizedRole) == _normalizeRoleString('Admin')) return true;

    final roleKey = _findRoleKey(normalizedRole);
    if (roleKey == null) return false;

    final rolePermissions = permissions[roleKey];
    if (rolePermissions == null) return false;

    final featurePermissions = rolePermissions[feature];
    if (featurePermissions == null) return false;

    return featurePermissions.contains(permission);
  }

  /// Synchronous version - check if user can view
  bool canViewSync(String? role, String feature) {
    return hasPermissionSync(role, feature, view);
  }

  /// Synchronous version - check if user can upload
  bool canUploadSync(String? role, String feature) {
    return hasPermissionSync(role, feature, upload);
  }

  /// Synchronous version - check if user can edit
  bool canEditSync(String? role, String feature) {
    return hasPermissionSync(role, feature, edit);
  }

  /// Synchronous version - check if user can complete tasks
  bool canCompleteTaskSync(String? role) {
    return hasPermissionSync(role, tasksAndNotes, completeTask);
  }

  /// Synchronous version - check if user can delete
  bool canDeleteSync(String? role, String feature) {
    return hasPermissionSync(role, feature, delete);
  }

  /// Public method to normalize a role (for use in other classes)
  String? normalizeRole(String? role) {
    return _normalizeRole(role);
  }
}

