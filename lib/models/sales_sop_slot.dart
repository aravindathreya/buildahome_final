/// Unified slot payloads from `GET /API/sales_sop_details/{id}/slots`.
/// Site inspection and workflow items share the same shape.
class SalesSopSlotOption {
  final int index;
  final String display;
  final String timeLabel;
  final bool isAccepted;

  const SalesSopSlotOption({
    required this.index,
    required this.display,
    required this.timeLabel,
    required this.isAccepted,
  });

  factory SalesSopSlotOption.fromJson(Map<String, dynamic> json, int fallbackIndex) {
    final index = _asInt(json['index']);
    return SalesSopSlotOption(
      index: index > 0 ? index : fallbackIndex,
      display: _firstString(json, const [
            'display',
            'datetime',
            'label',
            'value',
          ]) ??
          'Slot $fallbackIndex',
      timeLabel: _firstString(json, const ['time_label', 'time']) ?? '',
      isAccepted: _truthy(json['is_accepted']) || _truthy(json['accepted']),
    );
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
  final String submitButtonLabel;
  final bool requireNote;
  final bool canAccept;
  final String confirmUrl;
  final String confirmActionId;
  final String itemRunId;
  final List<SalesSopSlotOption> options;
  final SalesSopSlotOption? acceptedSlot;

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
    required this.submitButtonLabel,
    required this.requireNote,
    required this.canAccept,
    required this.confirmUrl,
    required this.confirmActionId,
    required this.itemRunId,
    required this.options,
    this.acceptedSlot,
  });

  bool get isSiteInspection =>
      source.trim().toLowerCase() == sourceSiteInspection;

  bool get isWorkflow => source.trim().toLowerCase() == sourceWorkflow;

  bool get isAccepted => status.trim().toLowerCase() == 'accepted';

  bool get isAwaitingConfirmation =>
      status.trim().toLowerCase() == 'awaiting_confirmation';

  bool get isSubmitted => status.trim().toLowerCase() == 'submitted';

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
    if (confirmationTaskName.isNotEmpty) {
      return 'Waiting for confirmation in $confirmationTaskName';
    }
    return 'Waiting for confirmation';
  }

  factory SalesSopSlot.fromJson(Map<String, dynamic> json) {
    final options = <SalesSopSlotOption>[];
    final rawOptions = json['options'];
    if (rawOptions is List) {
      for (var i = 0; i < rawOptions.length; i++) {
        final row = rawOptions[i];
        if (row is Map) {
          options.add(
            SalesSopSlotOption.fromJson(
              Map<String, dynamic>.from(row),
              i + 1,
            ),
          );
        }
      }
    }

    SalesSopSlotOption? accepted;
    final acceptedRaw = json['accepted_slot'] ?? json['confirmed_slot'];
    if (acceptedRaw is Map) {
      accepted = SalesSopSlotOption.fromJson(
        Map<String, dynamic>.from(acceptedRaw),
        _asInt(acceptedRaw['index']),
      );
    }

    final status = (_firstString(json, const ['status']) ?? '').toLowerCase();
    final statusLabel = _firstString(json, const ['status_label']) ??
        _defaultStatusLabel(status);

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
      submitButtonLabel:
          _firstString(json, const ['submit_button_label']) ?? 'Accept slot',
      requireNote: _truthy(json['require_note']),
      canAccept: _truthy(json['can_accept']),
      confirmUrl: _firstString(json, const ['confirm_url']) ?? '',
      confirmActionId: _firstString(json, const [
            'confirm_action_id',
            'action_id',
          ]) ??
          '',
      itemRunId: _firstString(json, const [
            'item_run_id',
            'workflow_item_run_id',
            'source_item_run_id',
          ]) ??
          '',
      options: options,
      acceptedSlot: accepted,
    );
  }

  static String _defaultStatusLabel(String status) {
    switch (status) {
      case 'accepted':
        return 'Accepted';
      case 'awaiting_confirmation':
        return 'Awaiting confirmation';
      case 'submitted':
        return 'Submitted';
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
  final List<SalesSopSlot> slots;

  const SalesSopSlotsResult({
    required this.salesSopId,
    required this.slotCount,
    required this.slots,
  });

  factory SalesSopSlotsResult.fromJson(Map<String, dynamic> json) {
    final slots = <SalesSopSlot>[];
    final raw = json['slots'];
    if (raw is List) {
      for (final row in raw) {
        if (row is Map) {
          slots.add(SalesSopSlot.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    final count = _asInt(json['slot_count']);
    return SalesSopSlotsResult(
      salesSopId: _asInt(json['sales_sop_id']),
      slotCount: count > 0 ? count : slots.length,
      slots: slots,
    );
  }
}

class SalesSopSlotsException implements Exception {
  final String message;
  final int? statusCode;

  const SalesSopSlotsException(this.message, {this.statusCode});

  @override
  String toString() => message;
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
