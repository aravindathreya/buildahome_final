import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_http.dart';

/// Staff attendance API (all roles except Client).
class AttendanceService {
  AttendanceService._();

  static const String baseUrl = 'https://office1.buildahome.in';
  static const String _prefPromptPrefix = 'attendance_prompted_date_';

  static Future<String?> _apiToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token')?.trim();
    if (token == null || token.isEmpty || token.toLowerCase() == 'null') {
      return null;
    }
    return token;
  }

  static Future<String?> _userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('userId') ?? prefs.getString('user_id');
  }

  static Map<String, String> _authHeaders(String apiToken) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Api-Token': apiToken,
      'Authorization': 'Bearer $apiToken',
    };
  }

  static Uri _uri(String path, [Map<String, String>? query]) {
    final params = <String, String>{...?query};
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: params.isEmpty ? null : params,
    );
  }

  static Future<AttendanceStatus> getStatus() async {
    final token = await _apiToken();
    if (token == null) throw AttendanceException('Not logged in');

    final response = await ApiHttp.get(
      _uri('/api/attendance/status', {'api_token': token}),
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 25));

    var status = _parseStatus(response.statusCode, response.body);

    // Status sometimes omits assignment rows; workspaces is the source of truth.
    if (status.assignments.isEmpty) {
      try {
        final workspaces = await getWorkspaces();
        if (workspaces.isNotEmpty) {
          status = status.copyWith(
            assignments: workspaces
                .map(
                  (w) => w.toAssignment(
                    coversToday: status.isScheduledToday,
                  ),
                )
                .toList(),
          );
        }
      } catch (_) {
        // Keep status as-is if workspaces fetch fails.
      }
    }

    return status;
  }

  static Future<List<AttendanceWorkspace>> getWorkspaces() async {
    final token = await _apiToken();
    if (token == null) throw AttendanceException('Not logged in');

    final response = await ApiHttp.get(
      _uri('/api/attendance/workspaces', {'api_token': token}),
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 25));

    final body = _decodeMap(response.body);
    if (response.statusCode == 401) {
      throw AttendanceException(
        body['message']?.toString() ?? 'Unauthorized',
      );
    }
    if (response.statusCode != 200 || !_asBool(body['success'])) {
      throw AttendanceException(
        body['message']?.toString() ?? 'Unable to load workspaces',
      );
    }

    final payload = _unwrapPayload(body);
    final list = _asMapList(
      payload['workspaces'] ??
          payload['assignments'] ??
          body['workspaces'] ??
          body['assignments'],
    );
    return list
        .map(AttendanceWorkspace.fromJson)
        .toList();
  }

  static Future<AttendanceRecord> checkIn({
    required double latitude,
    required double longitude,
    int? workspaceId,
    String? notes,
  }) async {
    final token = await _apiToken();
    if (token == null) throw AttendanceException('Not logged in');

    final payload = <String, dynamic>{
      'api_token': token,
      'latitude': latitude,
      'longitude': longitude,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };

    final response = await ApiHttp.post(
      _uri('/api/attendance/check-in'),
      headers: _authHeaders(token),
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 25));

    return _parseActionRecord(response.statusCode, response.body, 'check-in');
  }

  static Future<AttendanceRecord> checkOut({
    required double latitude,
    required double longitude,
    String? notes,
  }) async {
    final token = await _apiToken();
    if (token == null) throw AttendanceException('Not logged in');

    final payload = <String, dynamic>{
      'api_token': token,
      'latitude': latitude,
      'longitude': longitude,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };

    final response = await ApiHttp.post(
      _uri('/api/attendance/check-out'),
      headers: _authHeaders(token),
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 25));

    return _parseActionRecord(response.statusCode, response.body, 'check-out');
  }

  static Future<AttendanceHistory> getHistory({
    String? startDate,
    String? endDate,
  }) async {
    final token = await _apiToken();
    if (token == null) throw AttendanceException('Not logged in');

    final query = <String, String>{
      'api_token': token,
      if (startDate != null && startDate.isNotEmpty) 'start_date': startDate,
      if (endDate != null && endDate.isNotEmpty) 'end_date': endDate,
    };

    final response = await ApiHttp.get(
      _uri('/api/attendance/history', query),
      headers: _authHeaders(token),
    ).timeout(const Duration(seconds: 25));

    final body = _decodeMap(response.body);
    if (response.statusCode == 401) {
      throw AttendanceException(
        body['message']?.toString() ?? 'Unauthorized',
      );
    }
    if (response.statusCode != 200 || !_asBool(body['success'])) {
      throw AttendanceException(
        body['message']?.toString() ?? 'Unable to load attendance history',
      );
    }

    return AttendanceHistory.fromJson(_unwrapPayload(body));
  }

  /// IST calendar date key (yyyy-MM-dd) for daily prompt dedupe.
  static String todayDateKey([DateTime? now]) {
    final utc = (now ?? DateTime.now()).toUtc();
    final ist = utc.add(const Duration(hours: 5, minutes: 30));
    final y = ist.year.toString().padLeft(4, '0');
    final m = ist.month.toString().padLeft(2, '0');
    final d = ist.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<bool> wasPromptedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await _userId() ?? 'anon';
    final stored = prefs.getString('$_prefPromptPrefix$userId');
    return stored == todayDateKey();
  }

  static Future<void> markPromptedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await _userId() ?? 'anon';
    await prefs.setString('$_prefPromptPrefix$userId', todayDateKey());
  }

  static AttendanceStatus _parseStatus(int statusCode, String raw) {
    final body = _decodeMap(raw);
    if (statusCode == 401) {
      throw AttendanceException(
        body['message']?.toString() ?? 'Unauthorized',
      );
    }
    if (statusCode != 200 || !_asBool(body['success'])) {
      throw AttendanceException(
        body['message']?.toString() ?? 'Unable to load attendance status',
      );
    }
    return AttendanceStatus.fromJson(_unwrapPayload(body));
  }

  static AttendanceRecord _parseActionRecord(
    int statusCode,
    String raw,
    String action,
  ) {
    final body = _decodeMap(raw);
    if (statusCode == 401) {
      throw AttendanceException(
        body['message']?.toString() ?? 'Unauthorized',
      );
    }
    if (statusCode != 200 || !_asBool(body['success'])) {
      throw AttendanceException(
        body['message']?.toString() ??
            'Unable to complete $action. Please try again.',
      );
    }
    final payload = _unwrapPayload(body);
    final record = payload['record'] ?? body['record'];
    if (record is Map) {
      return AttendanceRecord.fromJson(Map<String, dynamic>.from(record));
    }
    throw AttendanceException('Invalid $action response');
  }

  static Map<String, dynamic> _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  /// Prefer nested `data` when present (common API envelope).
  static Map<String, dynamic> _unwrapPayload(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is Map) {
      final merged = Map<String, dynamic>.from(body);
      merged.addAll(Map<String, dynamic>.from(data));
      return merged;
    }
    return body;
  }

  static List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value == null) return const [];
    if (value is String) {
      try {
        return _asMapList(jsonDecode(value));
      } catch (_) {
        return const [];
      }
    }
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (value is Map) {
      return value.values
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }
}

class AttendanceException implements Exception {
  final String message;
  AttendanceException(this.message);

  @override
  String toString() => message;
}

class AttendanceStatus {
  final AttendanceUser? user;
  final String date;
  final String dayName;
  final bool isScheduledToday;
  final bool canCheckIn;
  final bool canCheckOut;
  final List<AttendanceAssignment> assignments;
  final AttendanceRecord? record;

  const AttendanceStatus({
    this.user,
    required this.date,
    required this.dayName,
    required this.isScheduledToday,
    required this.canCheckIn,
    required this.canCheckOut,
    required this.assignments,
    this.record,
  });

  AttendanceStatus copyWith({
    AttendanceUser? user,
    String? date,
    String? dayName,
    bool? isScheduledToday,
    bool? canCheckIn,
    bool? canCheckOut,
    List<AttendanceAssignment>? assignments,
    AttendanceRecord? record,
  }) {
    return AttendanceStatus(
      user: user ?? this.user,
      date: date ?? this.date,
      dayName: dayName ?? this.dayName,
      isScheduledToday: isScheduledToday ?? this.isScheduledToday,
      canCheckIn: canCheckIn ?? this.canCheckIn,
      canCheckOut: canCheckOut ?? this.canCheckOut,
      assignments: assignments ?? this.assignments,
      record: record ?? this.record,
    );
  }

  factory AttendanceStatus.fromJson(Map<String, dynamic> json) {
    final assignments = AttendanceService._asMapList(
      json['assignments'] ?? json['workspaces'],
    ).map(AttendanceAssignment.fromJson).toList();

    AttendanceRecord? record;
    final recordRaw = json['record'];
    if (recordRaw is Map) {
      record = AttendanceRecord.fromJson(Map<String, dynamic>.from(recordRaw));
    }

    AttendanceUser? user;
    final userRaw = json['user'];
    if (userRaw is Map) {
      user = AttendanceUser.fromJson(Map<String, dynamic>.from(userRaw));
    }

    return AttendanceStatus(
      user: user,
      date: json['date']?.toString() ?? '',
      dayName: json['day_name']?.toString() ?? '',
      isScheduledToday: _asBool(json['is_scheduled_today']),
      canCheckIn: _asBool(json['can_check_in']),
      canCheckOut: _asBool(json['can_check_out']),
      assignments: assignments,
      record: record,
    );
  }
}

class AttendanceUser {
  final int? userId;
  final String name;
  final String role;
  final String email;

  const AttendanceUser({
    this.userId,
    required this.name,
    required this.role,
    required this.email,
  });

  factory AttendanceUser.fromJson(Map<String, dynamic> json) {
    return AttendanceUser(
      userId: _asInt(json['user_id']),
      name: json['name']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }
}

class AttendanceAssignment {
  final int? id;
  final int? workspaceId;
  final String workspaceName;
  final String? locationLink;
  final double? latitude;
  final double? longitude;
  final double radiusMeters;
  final String workStartTime;
  final String workEndTime;
  final String daysOfWeek;
  final String daysLabel;
  final bool coversToday;

  const AttendanceAssignment({
    this.id,
    this.workspaceId,
    required this.workspaceName,
    this.locationLink,
    this.latitude,
    this.longitude,
    required this.radiusMeters,
    required this.workStartTime,
    required this.workEndTime,
    required this.daysOfWeek,
    required this.daysLabel,
    required this.coversToday,
  });

  factory AttendanceAssignment.fromJson(Map<String, dynamic> json) {
    return AttendanceAssignment(
      id: _asInt(json['id']),
      workspaceId: _asInt(json['workspace_id']),
      workspaceName: json['workspace_name']?.toString() ??
          json['name']?.toString() ??
          'Workspace',
      locationLink: json['location_link']?.toString(),
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      radiusMeters: _asDouble(json['radius_meters']) ?? 200,
      workStartTime: json['work_start_time']?.toString() ?? '',
      workEndTime: json['work_end_time']?.toString() ?? '',
      daysOfWeek: json['days_of_week']?.toString() ?? '',
      daysLabel: json['days_label']?.toString() ?? '',
      coversToday: _asBool(json['covers_today'], defaultValue: true),
    );
  }

  bool get hasCoordinates => latitude != null && longitude != null;
}

class AttendanceWorkspace {
  final int? assignmentId;
  final int? workspaceId;
  final String name;
  final String? locationLink;
  final double? latitude;
  final double? longitude;
  final double radiusMeters;
  final String address;
  final String workStartTime;
  final String workEndTime;
  final String daysOfWeek;
  final String daysLabel;

  const AttendanceWorkspace({
    this.assignmentId,
    this.workspaceId,
    required this.name,
    this.locationLink,
    this.latitude,
    this.longitude,
    required this.radiusMeters,
    required this.address,
    required this.workStartTime,
    required this.workEndTime,
    required this.daysOfWeek,
    required this.daysLabel,
  });

  factory AttendanceWorkspace.fromJson(Map<String, dynamic> json) {
    return AttendanceWorkspace(
      assignmentId: _asInt(json['assignment_id']),
      workspaceId: _asInt(json['workspace_id']),
      name: json['name']?.toString() ?? 'Workspace',
      locationLink: json['location_link']?.toString(),
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      radiusMeters: _asDouble(json['radius_meters']) ?? 200,
      address: json['address']?.toString() ?? '',
      workStartTime: json['work_start_time']?.toString() ?? '',
      workEndTime: json['work_end_time']?.toString() ?? '',
      daysOfWeek: json['days_of_week']?.toString() ?? '',
      daysLabel: json['days_label']?.toString() ?? '',
    );
  }

  AttendanceAssignment toAssignment({bool coversToday = true}) {
    return AttendanceAssignment(
      id: assignmentId,
      workspaceId: workspaceId,
      workspaceName: name,
      locationLink: locationLink,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      workStartTime: workStartTime,
      workEndTime: workEndTime,
      daysOfWeek: daysOfWeek,
      daysLabel: daysLabel,
      coversToday: coversToday,
    );
  }
}

class AttendanceRecord {
  final int? id;
  final int? userId;
  final int? workspaceId;
  final String workspaceName;
  final String attendanceDate;
  final String? checkInAt;
  final String? checkOutAt;
  final String status;
  final double? checkInDistanceM;
  final double? distanceM;

  const AttendanceRecord({
    this.id,
    this.userId,
    this.workspaceId,
    required this.workspaceName,
    required this.attendanceDate,
    this.checkInAt,
    this.checkOutAt,
    required this.status,
    this.checkInDistanceM,
    this.distanceM,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: _asInt(json['id']),
      userId: _asInt(json['user_id']),
      workspaceId: _asInt(json['workspace_id']),
      workspaceName: json['workspace_name']?.toString() ?? '',
      attendanceDate: json['attendance_date']?.toString() ?? '',
      checkInAt: json['check_in_at']?.toString(),
      checkOutAt: json['check_out_at']?.toString(),
      status: json['status']?.toString() ?? '',
      checkInDistanceM: _asDouble(json['check_in_distance_m']),
      distanceM: _asDouble(json['distance_m']),
    );
  }

  bool get hasCheckedIn =>
      checkInAt != null && checkInAt!.trim().isNotEmpty;
  bool get hasCheckedOut =>
      checkOutAt != null && checkOutAt!.trim().isNotEmpty;
}

class AttendanceHistory {
  final Map<String, dynamic> summary;
  final List<AttendanceDailyRow> daily;

  const AttendanceHistory({
    required this.summary,
    required this.daily,
  });

  factory AttendanceHistory.fromJson(Map<String, dynamic> json) {
    final summaryRaw = json['summary'];
    final summary = summaryRaw is Map
        ? Map<String, dynamic>.from(summaryRaw)
        : <String, dynamic>{};

    final daily = <AttendanceDailyRow>[];
    final dailyRaw = json['daily'];
    if (dailyRaw is List) {
      for (final item in dailyRaw) {
        if (item is Map) {
          daily.add(
            AttendanceDailyRow.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return AttendanceHistory(summary: summary, daily: daily);
  }
}

class AttendanceDailyRow {
  final String date;
  final String? dayName;
  final String? status;
  final String? workspaceName;
  final String? checkInAt;
  final String? checkOutAt;

  const AttendanceDailyRow({
    required this.date,
    this.dayName,
    this.status,
    this.workspaceName,
    this.checkInAt,
    this.checkOutAt,
  });

  factory AttendanceDailyRow.fromJson(Map<String, dynamic> json) {
    return AttendanceDailyRow(
      date: json['date']?.toString() ??
          json['attendance_date']?.toString() ??
          '',
      dayName: json['day_name']?.toString(),
      status: json['status']?.toString(),
      workspaceName: json['workspace_name']?.toString(),
      checkInAt: json['check_in_at']?.toString(),
      checkOutAt: json['check_out_at']?.toString(),
    );
  }
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

bool _asBool(dynamic value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return defaultValue;
}
