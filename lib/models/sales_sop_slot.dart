import 'dart:convert';

import 'package:intl/intl.dart';

/// Unified slot payloads from `GET /API/sales_sop_details/{id}/slots`,
/// `GET /api/client_portal/sections/slots`, and
/// `GET /API/mobile/home/slots`.
/// Site inspection and workflow items share the same shape.
class SalesSopSlotOption {
  final int index;
  final String display;
  final String timeLabel;
  final String datetime;
  final bool isAccepted;

  const SalesSopSlotOption({
    required this.index,
    required this.display,
    required this.timeLabel,
    this.datetime = '',
    required this.isAccepted,
  });

  factory SalesSopSlotOption.fromJson(Map<String, dynamic> json, int fallbackIndex) {
    final index = _asInt(json['index']);
    final datetime = _firstString(json, const [
          'datetime',
          'date_time',
        ]) ??
        '';
    final date = _firstString(json, const ['date']) ?? '';
    final time = _firstString(json, const ['time_label', 'time']) ?? '';
    var resolvedDatetime = datetime;
    if (resolvedDatetime.isEmpty && date.isNotEmpty) {
      resolvedDatetime = time.isNotEmpty ? '$date $time' : date;
    }
    return SalesSopSlotOption(
      index: index > 0 ? index : fallbackIndex,
      display: _firstString(json, const [
            'display',
            'datetime',
            'label',
            'value',
          ]) ??
          'Slot $fallbackIndex',
      timeLabel: time,
      datetime: resolvedDatetime,
      isAccepted: _truthy(json['is_accepted']) || _truthy(json['accepted']),
    );
  }

  DateTime? get parsedDateTime =>
      parseHomeSlotDateTime(datetime) ?? parseHomeSlotDateTime(display);
}

class SalesSopSlotTimeOption {
  final String label;
  final String time;

  const SalesSopSlotTimeOption({
    required this.label,
    required this.time,
  });

  factory SalesSopSlotTimeOption.fromJson(Map<String, dynamic> json) {
    return SalesSopSlotTimeOption(
      label: _firstString(json, const ['label', 'time_label', 'name']) ?? '',
      time: _firstString(json, const ['time', 'value']) ?? '',
    );
  }

  String get display {
    if (time.isEmpty) return label;
    return '$label · $time';
  }
}

class SalesSopSlot {
  static const sourceSiteInspection = 'site_inspection';
  static const sourceWorkflow = 'workflow';

  final String source;
  final String title;
  final String status;
  final String statusLabel;
  final String selectionTaskName;
  final String submittedBy;
  final String submittedAt;
  final String confirmedBy;
  final String confirmedAt;
  final String presenceLabel;
  final String virtualConnectionDetails;
  final bool siteCleanedConfirmed;
  final String siteCleanedProofUrl;
  final String clientNote;
  final String confirmationNote;
  final String confirmationTaskName;
  final String heading;
  final String submitButtonLabel;
  final String selectButtonLabel;
  final bool requireNote;
  final bool allowNote;
  final bool canAccept;
  final bool canSelect;
  final String confirmUrl;
  final String selectUrl;
  final String confirmActionId;
  final String selectActionId;
  final String itemRunId;
  final String confirmItemRunId;
  final String selectItemRunId;
  final int slotCount;
  final int minNoticeHours;
  final bool usePredefinedTimes;
  final List<SalesSopSlotTimeOption> timeOptions;
  final List<SalesSopSlotOption> options;
  final SalesSopSlotOption? acceptedSlot;
  final String id;
  final String projectId;
  final String projectName;

  const SalesSopSlot({
    required this.source,
    required this.title,
    required this.status,
    required this.statusLabel,
    required this.selectionTaskName,
    required this.submittedBy,
    required this.submittedAt,
    required this.confirmedBy,
    required this.confirmedAt,
    required this.presenceLabel,
    required this.virtualConnectionDetails,
    required this.siteCleanedConfirmed,
    required this.siteCleanedProofUrl,
    required this.clientNote,
    required this.confirmationNote,
    required this.confirmationTaskName,
    required this.heading,
    required this.submitButtonLabel,
    required this.selectButtonLabel,
    required this.requireNote,
    required this.allowNote,
    required this.canAccept,
    required this.canSelect,
    required this.confirmUrl,
    required this.selectUrl,
    required this.confirmActionId,
    required this.selectActionId,
    required this.itemRunId,
    required this.confirmItemRunId,
    required this.selectItemRunId,
    required this.slotCount,
    required this.minNoticeHours,
    required this.usePredefinedTimes,
    required this.timeOptions,
    required this.options,
    this.acceptedSlot,
    this.id = '',
    this.projectId = '',
    this.projectName = '',
  });

  bool get isSiteInspection =>
      source.trim().toLowerCase() == sourceSiteInspection;

  bool get isWorkflow => source.trim().toLowerCase() == sourceWorkflow;

  bool get isAccepted => _statusKey == 'accepted';

  bool get isAwaitingConfirmation => _statusKey == 'awaiting_confirmation';

  bool get isSubmitted => _statusKey == 'submitted';

  bool get needsSelection =>
      _statusKey == 'needs_selection' ||
      (canSelect && options.isEmpty && !isAccepted);

  /// Home "Choose Slot" uses the backend status + canSelect, not inferred empty options.
  bool get showHomeChooseSlot =>
      statusKey == 'needs_selection' && canSelect && !isAccepted;

  String get statusKey => _statusKey;

  String get _statusKey {
    final value = status.trim().toLowerCase().replaceAll(' ', '_');
    switch (value) {
      case 'need_selection':
      case 'needs_slots':
      case 'pending_selection':
      case 'selection_pending':
      case 'slot_selection':
      case 'selection':
      case 'select':
        return 'needs_selection';
      case 'awaiting':
      case 'pending_confirmation':
      case 'confirmation':
      case 'confirm':
        return 'awaiting_confirmation';
      default:
        return value;
    }
  }

  bool get usesPredefinedTimes =>
      usePredefinedTimes && timeOptions.isNotEmpty;

  int get selectionSlotCount {
    if (slotCount > 0) return slotCount.clamp(1, 12);
    return 3;
  }

  /// Maximum preferred slots the user may submit. Reuses [selectionSlotCount].
  int get maxPreferredSelections => selectionSlotCount;

  String get projectLabel {
    if (projectName.isNotEmpty) return projectName;
    if (projectId.isNotEmpty) return 'Project $projectId';
    return '';
  }

  String get selectionUrl => selectUrl;

  String get confirmationUrl => confirmUrl;

  String get homeStatusLabel {
    switch (statusKey) {
      case 'needs_selection':
        return 'Needs your action';
      case 'submitted':
        return 'Slots submitted';
      case 'awaiting_confirmation':
        return 'Awaiting confirmation';
      case 'accepted':
        return 'Confirmed';
      default:
        return statusLabel.isNotEmpty
            ? statusLabel
            : _defaultStatusLabel(statusKey);
    }
  }

  bool occursOnDate(DateTime day) {
    return scheduleDates.any(
      (d) => d.year == day.year && d.month == day.month && d.day == day.day,
    );
  }

  List<DateTime> get scheduleDates {
    final dates = <DateTime>{};
    void add(DateTime? value) {
      if (value == null) return;
      dates.add(DateTime(value.year, value.month, value.day));
    }

    for (final option in options) {
      add(option.parsedDateTime);
    }
    add(acceptedSlot?.parsedDateTime);
    return dates.toList()..sort();
  }

  String get homeIdentity {
    if (id.isNotEmpty) return id;
    if (selectRunId.isNotEmpty) return selectRunId;
    if (itemRunId.isNotEmpty) return itemRunId;
    return '$source|$title|$projectId';
  }

  SalesSopSlot copyWith({
    String? source,
    String? title,
    String? status,
    String? statusLabel,
    String? selectionTaskName,
    String? submittedBy,
    String? submittedAt,
    String? confirmedBy,
    String? confirmedAt,
    String? presenceLabel,
    String? virtualConnectionDetails,
    bool? siteCleanedConfirmed,
    String? siteCleanedProofUrl,
    String? clientNote,
    String? confirmationNote,
    String? confirmationTaskName,
    String? heading,
    String? submitButtonLabel,
    String? selectButtonLabel,
    bool? requireNote,
    bool? allowNote,
    bool? canAccept,
    bool? canSelect,
    String? confirmUrl,
    String? selectUrl,
    String? confirmActionId,
    String? selectActionId,
    String? itemRunId,
    String? confirmItemRunId,
    String? selectItemRunId,
    int? slotCount,
    int? minNoticeHours,
    bool? usePredefinedTimes,
    List<SalesSopSlotTimeOption>? timeOptions,
    List<SalesSopSlotOption>? options,
    SalesSopSlotOption? acceptedSlot,
    bool clearAcceptedSlot = false,
    String? id,
    String? projectId,
    String? projectName,
  }) {
    return SalesSopSlot(
      source: source ?? this.source,
      title: title ?? this.title,
      status: status ?? this.status,
      statusLabel: statusLabel ?? this.statusLabel,
      selectionTaskName: selectionTaskName ?? this.selectionTaskName,
      submittedBy: submittedBy ?? this.submittedBy,
      submittedAt: submittedAt ?? this.submittedAt,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      presenceLabel: presenceLabel ?? this.presenceLabel,
      virtualConnectionDetails:
          virtualConnectionDetails ?? this.virtualConnectionDetails,
      siteCleanedConfirmed: siteCleanedConfirmed ?? this.siteCleanedConfirmed,
      siteCleanedProofUrl: siteCleanedProofUrl ?? this.siteCleanedProofUrl,
      clientNote: clientNote ?? this.clientNote,
      confirmationNote: confirmationNote ?? this.confirmationNote,
      confirmationTaskName: confirmationTaskName ?? this.confirmationTaskName,
      heading: heading ?? this.heading,
      submitButtonLabel: submitButtonLabel ?? this.submitButtonLabel,
      selectButtonLabel: selectButtonLabel ?? this.selectButtonLabel,
      requireNote: requireNote ?? this.requireNote,
      allowNote: allowNote ?? this.allowNote,
      canAccept: canAccept ?? this.canAccept,
      canSelect: canSelect ?? this.canSelect,
      confirmUrl: confirmUrl ?? this.confirmUrl,
      selectUrl: selectUrl ?? this.selectUrl,
      confirmActionId: confirmActionId ?? this.confirmActionId,
      selectActionId: selectActionId ?? this.selectActionId,
      itemRunId: itemRunId ?? this.itemRunId,
      confirmItemRunId: confirmItemRunId ?? this.confirmItemRunId,
      selectItemRunId: selectItemRunId ?? this.selectItemRunId,
      slotCount: slotCount ?? this.slotCount,
      minNoticeHours: minNoticeHours ?? this.minNoticeHours,
      usePredefinedTimes: usePredefinedTimes ?? this.usePredefinedTimes,
      timeOptions: timeOptions ?? this.timeOptions,
      options: options ?? this.options,
      acceptedSlot: clearAcceptedSlot ? null : (acceptedSlot ?? this.acceptedSlot),
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
    );
  }

  String get selectRunId =>
      selectItemRunId.isNotEmpty ? selectItemRunId : itemRunId;

  String get confirmRunId =>
      confirmItemRunId.isNotEmpty ? confirmItemRunId : itemRunId;

  String get headerPillLabel {
    if (isSiteInspection) return 'Site inspection';
    if (selectionTaskName.isNotEmpty) return selectionTaskName;
    return 'Workflow';
  }

  String get givenMeta {
    final parts = <String>[
      if (submittedBy.isNotEmpty) 'Given by $submittedBy',
      if (submittedAt.isNotEmpty) submittedAt,
    ];
    return parts.join(' · ');
  }

  String get selectedMeta {
    final parts = <String>[
      if (confirmedBy.isNotEmpty) 'Selected by $confirmedBy',
      if (confirmedAt.isNotEmpty) confirmedAt,
    ];
    return parts.join(' · ');
  }

  String get waitingBannerText {
    if (needsSelection) {
      return 'Waiting for preferred slots';
    }
    if (confirmationTaskName.isNotEmpty) {
      return 'Waiting for confirmation in $confirmationTaskName';
    }
    return 'Waiting for confirmation';
  }

  String get selectionHelperText {
    final parts = <String>[
      if (heading.isNotEmpty) heading,
      if (minNoticeHours > 0)
        'Choose ${selectionSlotCount == 1 ? 'a slot' : '$selectionSlotCount unique slots'} at least $minNoticeHours hours from now.',
      if (minNoticeHours <= 0 && heading.isEmpty)
        'Choose ${selectionSlotCount == 1 ? 'a preferred time' : '$selectionSlotCount preferred times'}.',
    ];
    return parts.join(' ');
  }

  factory SalesSopSlot.fromJson(Map<String, dynamic> json) {
    final options = _parseOptions(json);

    SalesSopSlotOption? accepted;
    final acceptedRaw = json['accepted_slot'] ?? json['confirmed_slot'];
    if (acceptedRaw is Map) {
      accepted = SalesSopSlotOption.fromJson(
        Map<String, dynamic>.from(acceptedRaw),
        _asInt(acceptedRaw['index']),
      );
    }

    var status = _normalizedStatus(json);
    final statusLabel = _firstString(json, const ['status_label']) ??
        _defaultStatusLabel(status);
    final genericAction = _firstString(json, const ['action_id']) ?? '';
    final genericRunId = _firstString(json, const [
          'item_run_id',
          'workflow_item_run_id',
          'source_item_run_id',
        ]) ??
        '';
    final selectUrl = _firstString(json, const [
          'select_url',
          'selection_url',
        ]) ??
        '';
    final confirmUrl = _firstString(json, const [
          'confirm_url',
          'confirmation_url',
        ]) ??
        '';
    final selectActionId =
        _firstString(json, const ['select_action_id']) ?? '';
    final selectItemRunId =
        _firstString(json, const ['select_item_run_id']) ?? '';
    final confirmActionId =
        _firstString(json, const ['confirm_action_id']) ?? '';
    final confirmItemRunId =
        _firstString(json, const ['confirm_item_run_id']) ?? '';
    final actionType = (_firstString(json, const [
              'action_type',
              'type',
              'kind',
              'card_type',
            ]) ??
            '')
        .toLowerCase();
    final timeOptions = _parseTimeOptions(
      json['time_options'] ?? json['predefined_times'] ?? json['time_choices'],
    );
    final submitLabel =
        _firstString(json, const ['submit_button_label']) ?? '';

    var canSelect = json.containsKey('can_select')
        ? _truthy(json['can_select'])
        : _truthy(json['canSelect']);
    final canAccept = json.containsKey('can_accept')
        ? _truthy(json['can_accept'])
        : _truthy(json['canAccept']);
    if (!canSelect &&
        (selectActionId.isNotEmpty ||
            selectItemRunId.isNotEmpty ||
            selectUrl.isNotEmpty) &&
        options.isEmpty &&
        status != 'accepted' &&
        status != 'awaiting_confirmation' &&
        status != 'submitted') {
      canSelect = true;
    }
    if (!canSelect &&
        actionType.contains('slot_selection') &&
        _truthy(json['can_update']) &&
        options.isEmpty) {
      canSelect = true;
    }
    if (canSelect && status.isEmpty && options.isEmpty) {
      status = 'needs_selection';
    }
    if (canAccept && options.isNotEmpty && status.isEmpty) {
      status = 'awaiting_confirmation';
    }
    final selecting = canSelect || status == 'needs_selection';
    final project = _parseProject(json);
    final id = _firstString(json, const [
          'id',
          'slot_id',
          'home_slot_id',
          'home_item_id',
        ]) ??
        genericRunId;

    return SalesSopSlot(
      source: (_firstString(json, const ['source']) ?? sourceWorkflow)
          .toLowerCase(),
      title: _firstString(json, const ['title', 'task_name', 'name']) ??
          'Slot',
      status: status,
      statusLabel: statusLabel,
      selectionTaskName: _firstString(json, const [
            'selection_task_name',
            'source_task_name',
            'task_name',
          ]) ??
          '',
      submittedBy: _firstString(json, const ['submitted_by', 'given_by']) ?? '',
      submittedAt: _firstString(json, const ['submitted_at', 'given_at']) ?? '',
      confirmedBy:
          _firstString(json, const ['confirmed_by', 'accepted_by']) ?? '',
      confirmedAt:
          _firstString(json, const ['confirmed_at', 'accepted_at']) ?? '',
      presenceLabel: _firstString(json, const ['presence_label']) ?? '',
      virtualConnectionDetails: _virtualDetails(json['virtual_connection_details']),
      siteCleanedConfirmed: _truthy(json['site_cleaned_confirmed']),
      siteCleanedProofUrl:
          _firstString(json, const ['site_cleaned_proof_url']) ?? '',
      clientNote: _firstString(json, const [
            'client_note',
            'client_comment',
          ]) ??
          '',
      confirmationNote: _firstString(json, const [
            'confirmation_note',
            'confirmation_comment',
            'confirmed_comment',
            'confirm_note',
          ]) ??
          '',
      confirmationTaskName:
          _firstString(json, const ['confirmation_task_name']) ?? '',
      heading: _firstString(json, const ['heading', 'helper_text']) ?? '',
      submitButtonLabel:
          submitLabel.isNotEmpty ? submitLabel : 'Accept slot',
      selectButtonLabel: _firstString(json, const [
            'select_button_label',
          ]) ??
          (selecting && submitLabel.isNotEmpty
              ? submitLabel
              : 'Submit slots'),
      requireNote: _truthy(json['require_note']),
      allowNote: !_falsey(json['allow_note']),
      canAccept: canAccept,
      canSelect: canSelect,
      confirmUrl: confirmUrl,
      selectUrl: selectUrl,
      confirmActionId: confirmActionId.isNotEmpty
          ? confirmActionId
          : (selecting && !canAccept ? '' : genericAction),
      selectActionId: selectActionId.isNotEmpty
          ? selectActionId
          : (selecting ? genericAction : ''),
      itemRunId: genericRunId,
      confirmItemRunId: confirmItemRunId.isNotEmpty
          ? confirmItemRunId
          : (selecting && !canAccept ? '' : genericRunId),
      selectItemRunId: selectItemRunId.isNotEmpty
          ? selectItemRunId
          : (selecting ? genericRunId : ''),
      slotCount: _asInt(
        json['slot_count'] ??
            json['number_of_slots'] ??
            json['max_selections'] ??
            json['max_preferred_slots'],
      ),
      minNoticeHours: _asInt(json['min_notice_hours']),
      usePredefinedTimes: _truthy(json['use_predefined_times']) &&
          timeOptions.isNotEmpty,
      timeOptions: timeOptions,
      options: options,
      acceptedSlot: accepted,
      id: id,
      projectId: project.id,
      projectName: project.name,
    );
  }

  static String _normalizedStatus(Map<String, dynamic> json) {
    var status = (_firstString(json, const [
              'status',
              'state',
              'slot_status',
            ]) ??
            '')
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_');
    if (status.isEmpty) {
      status = (_firstString(json, const ['status_label']) ?? '')
          .toLowerCase()
          .replaceAll(' ', '_')
          .replaceAll('-', '_');
    }
    final type = (_firstString(json, const [
              'action_type',
              'type',
              'kind',
              'card_type',
            ]) ??
            '')
        .toLowerCase();
    switch (status) {
      case 'need_selection':
      case 'needs_slots':
      case 'pending_selection':
      case 'selection_pending':
      case 'slot_selection':
      case 'selection':
      case 'select':
        status = 'needs_selection';
        break;
      case 'awaiting':
      case 'pending_confirmation':
      case 'confirmation':
      case 'confirm':
        status = 'awaiting_confirmation';
        break;
    }
    if (status.isEmpty || status == 'pending') {
      if (type.contains('slot_selection')) return 'needs_selection';
      if (type.contains('slot_confirm')) return 'awaiting_confirmation';
    }
    return status;
  }

  static List<SalesSopSlotOption> _parseOptions(Map<String, dynamic> json) {
    const keys = [
      'options',
      'slot_options',
      'available_slots',
      'preferred_slots',
      'slots',
    ];
    for (final key in keys) {
      final raw = json[key];
      if (raw is! List || raw.isEmpty) continue;
      if (!_looksLikeConfirmOptions(raw)) continue;
      final options = <SalesSopSlotOption>[];
      for (var i = 0; i < raw.length; i++) {
        final row = raw[i];
        if (row is Map) {
          options.add(
            SalesSopSlotOption.fromJson(
              Map<String, dynamic>.from(row),
              i + 1,
            ),
          );
        }
      }
      if (options.isNotEmpty) return options;
    }
    return const [];
  }

  static _HomeProject _parseProject(Map<String, dynamic> json) {
    final nested = json['project'];
    if (nested is Map) {
      final map = Map<String, dynamic>.from(nested);
      return _HomeProject(
        id: _firstString(map, const ['id', 'project_id']) ?? '',
        name: _firstString(map, const [
              'name',
              'title',
              'project_name',
              'client_name',
            ]) ??
            '',
      );
    }
    return _HomeProject(
      id: _firstString(json, const ['project_id', 'sales_sop_id']) ?? '',
      name: _firstString(json, const [
            'project_name',
            'project',
            'client_name',
          ]) ??
          '',
    );
  }

  static bool _looksLikeConfirmOptions(List<dynamic> raw) {
    for (final row in raw) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      if (map.containsKey('display') ||
          map.containsKey('index') ||
          map.containsKey('is_accepted') ||
          map.containsKey('datetime')) {
        return true;
      }
      if (map.containsKey('date') &&
          map.containsKey('time_label') &&
          !map.containsKey('index')) {
        return false;
      }
    }
    return false;
  }

  static List<SalesSopSlotTimeOption> _parseTimeOptions(dynamic value) {
    dynamic normalized = value;
    if (value is String && value.trim().isNotEmpty) {
      try {
        normalized = jsonDecode(value);
      } catch (_) {
        normalized = value;
      }
    }
    if (normalized is! List) return const [];
    final options = <SalesSopSlotTimeOption>[];
    for (final row in normalized) {
      if (row is! Map) continue;
      final option = SalesSopSlotTimeOption.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (option.label.isEmpty) continue;
      options.add(option);
    }
    return options;
  }

  static String _defaultStatusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'awaiting_confirmation':
        return 'Awaiting confirmation';
      case 'submitted':
        return 'Submitted';
      case 'needs_selection':
        return 'Needs selection';
      default:
        return status.isEmpty ? '' : status.replaceAll('_', ' ');
    }
  }

  static String _virtualDetails(dynamic value) {
    if (value == null) return '';
    if (value is Map) {
      final lines = <String>[];
      for (final entry in value.entries) {
        final text = _asString(entry.value);
        if (text.isEmpty) continue;
        lines.add('${_prettyKey(entry.key.toString())}: $text');
      }
      return lines.join('\n');
    }
    return _asString(value);
  }

  static String _prettyKey(String key) {
    return key
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class SalesSopSlotsResult {
  final int salesSopId;
  final int slotCount;
  final int needsSelectionCount;
  final int awaitingCount;
  final int acceptedCount;
  final List<SalesSopSlot> slots;
  final bool hasMore;

  const SalesSopSlotsResult({
    required this.salesSopId,
    required this.slotCount,
    required this.needsSelectionCount,
    required this.awaitingCount,
    required this.acceptedCount,
    required this.slots,
    this.hasMore = false,
  });

  factory SalesSopSlotsResult.fromJson(Map<String, dynamic> json) {
    final merged = _unwrapSlotsPayload(json);
    final slots = <SalesSopSlot>[];
    final raw = merged['slots'] ??
        merged['items'] ??
        merged['cards'] ??
        merged['slot_cards'];
    if (raw is List) {
      for (final row in raw) {
        if (row is Map) {
          slots.add(SalesSopSlot.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    return SalesSopSlotsResult(
      salesSopId: _asInt(merged['sales_sop_id'] ?? json['sales_sop_id']),
      slotCount: slots.length,
      needsSelectionCount: _countOr(
        merged['needs_selection_count'],
        slots.where((slot) => slot.needsSelection).length,
      ),
      awaitingCount: _countOr(
        merged['awaiting_count'] ?? merged['awaiting_confirmation_count'],
        slots.where((slot) => slot.isAwaitingConfirmation).length,
      ),
      acceptedCount: _countOr(
        merged['accepted_count'],
        slots.where((slot) => slot.isAccepted).length,
      ),
      slots: slots,
      hasMore: _truthy(merged['has_more']) || _truthy(merged['hasMore']),
    );
  }

  static int _countOr(dynamic value, int fallback) {
    if (value == null) return fallback;
    return _asInt(value);
  }
}

class SalesSopSlotsException implements Exception {
  final String message;
  final int? statusCode;

  const SalesSopSlotsException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

Map<String, dynamic> _unwrapSlotsPayload(Map<String, dynamic> json) {
  final merged = Map<String, dynamic>.from(json);
  void mergeIfSlots(dynamic raw) {
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    if (map['slots'] is List ||
        map['items'] is List ||
        map['cards'] is List ||
        map['schedule'] is List ||
        map['home_slots'] is List) {
      merged.addAll(map);
    }
  }

  mergeIfSlots(json['section']);
  mergeIfSlots(json['data']);
  mergeIfSlots(json['result']);
  mergeIfSlots(json['home']);
  merged['slots'] ??=
      merged['schedule'] ?? merged['home_slots'] ?? json['schedule'];
  return merged;
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final text = _asString(json[key]);
    if (text.isNotEmpty) return text;
  }
  return null;
}

String _asString(dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _truthy(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}

bool _falsey(dynamic value) {
  if (value is bool) return !value;
  if (value is num) return value == 0;
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == '0' || text == 'false' || text == 'no';
}

class _HomeProject {
  final String id;
  final String name;

  const _HomeProject({required this.id, required this.name});
}

/// Home aggregated schedule item. Reuses [SalesSopSlot] so slot selection
/// can call the existing select API without a second slot mechanism.
typedef HomeScheduleItem = SalesSopSlot;

DateTime? parseHomeSlotDateTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;
  const patterns = [
    "yyyy-MM-dd'T'HH:mm:ss",
    "yyyy-MM-dd'T'HH:mm",
    'yyyy-MM-dd HH:mm:ss',
    'yyyy-MM-dd HH:mm',
    'yyyy-MM-dd',
    'EEE, d MMM yyyy hh:mm a',
    'EEE, dd MMM yyyy hh:mm a',
    'd MMM yyyy hh:mm a',
    'dd MMM yyyy hh:mm a',
    'EEE, d MMM yyyy',
    'd MMM yyyy',
    'dd MMM yyyy',
  ];
  for (final pattern in patterns) {
    try {
      return DateFormat(pattern).parseLoose(text);
    } catch (_) {}
  }
  return null;
}

