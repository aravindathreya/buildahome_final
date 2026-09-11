import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'models/sales_sop_slot.dart';
import 'services/sales_sop_slots_service.dart';
import 'services/session_manager.dart';
import 'widgets/skeleton_loader.dart';
import 'widgets/themed_scaffold.dart';

class SlotsScreen extends StatelessWidget {
  final bool embedded;

  const SlotsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    if (embedded) return const SlotsView();
    return const ThemedScaffold(
      title: 'Slots',
      body: SlotsView(showInlineTitle: false),
    );
  }
}

class SlotsView extends StatefulWidget {
  final bool showInlineTitle;

  const SlotsView({super.key, this.showInlineTitle = true});

  @override
  State<SlotsView> createState() => SlotsViewState();
}

enum _VisitFilter { all, pending, selected }

enum _VisitSort { visitOrder, name, pendingFirst }

class _PreferredSlotRow {
  DateTime? date;
  DateTime? dateTime;
  SalesSopSlotTimeOption? timeOption;
}

class SlotsViewState extends State<SlotsView> {
  static const _draftPicksKey = 'sales_sop_slot_draft_picks';
  static const _draftNotesKey = 'sales_sop_slot_draft_notes';

  bool _loading = true;
  bool _confirming = false;
  String? _submittingSelectId;
  String? _error;
  List<SalesSopSlot> _slots = const [];
  int _needsSelectionCount = 0;
  int _awaitingCount = 0;
  int _acceptedCount = 0;
  final Map<String, int> _picks = {};
  final Map<String, String> _notes = {};
  final Map<String, String> _errors = {};
  final Map<String, TextEditingController> _noteCtrls = {};
  final Map<String, List<_PreferredSlotRow>> _selectRows = {};
  final Map<String, TextEditingController> _selectNoteCtrls = {};
  final Map<String, Map<int, String>> _selectRowErrors = {};
  final Set<String> _collapsed = {};
  _VisitFilter _filter = _VisitFilter.all;
  _VisitSort _sort = _VisitSort.visitOrder;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    for (final controller in _noteCtrls.values) {
      controller.dispose();
    }
    for (final controller in _selectNoteCtrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _restoreDrafts();
      final result = await SalesSopSlotsService().fetchSlots();
      if (!mounted) return;
      setState(() {
        _applyResult(result);
        _loading = false;
      });
      await _persistDrafts();
    } on SessionInvalidatedException {
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _applyResult(SalesSopSlotsResult result) {
    _slots = result.slots;
    _needsSelectionCount = result.needsSelectionCount;
    _awaitingCount = result.awaitingCount;
    _acceptedCount = result.acceptedCount;
    _syncPicksToSlots();
    _syncSelectRows();
    print(
      '[Slots] loaded ${result.slots.length} cards '
      'needs=${result.needsSelectionCount} '
      'awaiting=${result.awaitingCount} '
      'accepted=${result.acceptedCount}',
    );
    for (final slot in result.slots) {
      print(
        '[Slots] "${slot.title}" status=${slot.status} '
        'can_select=${slot.canSelect} can_accept=${slot.canAccept} '
        'options=${slot.options.length} select_run=${slot.selectRunId} '
        'select_action=${slot.selectActionId} slot_count=${slot.selectionSlotCount} '
        'predefined=${slot.usesPredefinedTimes}',
      );
    }
  }

  Future<void> _restoreDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final picksRaw = prefs.getString(_draftPicksKey);
    final notesRaw = prefs.getString(_draftNotesKey);
    if (picksRaw != null && picksRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(picksRaw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            final index = value is int ? value : int.tryParse('$value');
            if (index != null) _picks['$key'] = index;
          });
        }
      } catch (_) {}
    }
    if (notesRaw != null && notesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(notesRaw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            _notes['$key'] = '$value';
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _persistDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_draftPicksKey, jsonEncode(_picks));
    await prefs.setString(_draftNotesKey, jsonEncode(_notes));
  }

  void _syncPicksToSlots() {
    final valid = <String>{};
    for (final slot in _slots) {
      final id = _idFor(slot);
      valid.add(id);
      final acceptedIndex = _acceptedIndex(slot);
      if (acceptedIndex != null) {
        _picks[id] = acceptedIndex;
      } else if (!_canPick(slot)) {
        _picks.remove(id);
      }
      // Keep every visit accordion open by default.
      _collapsed.remove(id);
    }
    _picks.removeWhere((key, _) => !valid.contains(key));
    _notes.removeWhere((key, _) => !valid.contains(key));
  }

  void _syncSelectRows() {
    final valid = <String>{};
    for (final slot in _slots) {
      if (!_canSelectPreferred(slot)) continue;
      final id = _idFor(slot);
      valid.add(id);
      final count = slot.selectionSlotCount;
      final existing = _selectRows[id];
      if (existing == null || existing.length != count) {
        _selectRows[id] = List.generate(count, (_) => _PreferredSlotRow());
      }
    }
    _selectRows.removeWhere((key, _) => !valid.contains(key));
    _selectRowErrors.removeWhere((key, _) => !valid.contains(key));
  }

  String _idFor(SalesSopSlot slot) {
    return [
      slot.source,
      slot.selectItemRunId,
      slot.confirmItemRunId,
      slot.itemRunId,
      slot.selectActionId,
      slot.confirmActionId,
      slot.confirmUrl,
      slot.selectUrl,
      slot.title,
    ].where((part) => part.trim().isNotEmpty).join('|');
  }

  int? _acceptedIndex(SalesSopSlot slot) {
    if (slot.acceptedSlot != null) return slot.acceptedSlot!.index;
    for (final option in slot.options) {
      if (option.isAccepted) return option.index;
    }
    return slot.isAccepted ? _picks[_idFor(slot)] : null;
  }

  int? _pickedIndex(SalesSopSlot slot) => _picks[_idFor(slot)];

  bool _isSelected(SalesSopSlot slot) {
    if (slot.isAccepted || slot.isSubmitted) return true;
    return _canPick(slot) && _pickedIndex(slot) != null;
  }

  bool _isPending(SalesSopSlot slot) {
    if (_canSelectPreferred(slot) || slot.needsSelection) return true;
    if (slot.canAccept && !_isSelected(slot)) return true;
    if (slot.isAwaitingConfirmation && !_isSelected(slot)) return true;
    return false;
  }

  bool _isLocked(SalesSopSlot slot) =>
      slot.isAccepted || slot.isSubmitted || !_canPick(slot);

  bool _canPick(SalesSopSlot slot) =>
      slot.canAccept && slot.options.isNotEmpty && !slot.isAccepted;

  bool _canSelectPreferred(SalesSopSlot slot) =>
      slot.canSelect &&
      !slot.isAccepted &&
      !(slot.canAccept && slot.options.isNotEmpty);

  bool get _busy => _confirming || _submittingSelectId != null;

  SalesSopSlotOption? _optionFor(SalesSopSlot slot, int? index) {
    if (index == null) return null;
    for (final option in slot.options) {
      if (option.index == index) return option;
    }
    return null;
  }

  List<SalesSopSlot> get _visibleSlots {
    Iterable<SalesSopSlot> items = _slots;
    switch (_filter) {
      case _VisitFilter.pending:
        items = items.where(_isPending);
        break;
      case _VisitFilter.selected:
        items = items.where(_isSelected);
        break;
      case _VisitFilter.all:
        break;
    }
    final list = items.toList();
    switch (_sort) {
      case _VisitSort.name:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case _VisitSort.pendingFirst:
        list.sort((a, b) {
          final pending = (_isSelected(a) ? 1 : 0).compareTo(_isSelected(b) ? 1 : 0);
          if (pending != 0) return pending;
          return 0;
        });
        break;
      case _VisitSort.visitOrder:
        break;
    }
    return list;
  }

  int get _selectedCount => _slots.where(_isSelected).length;

  int get _pendingCount => _slots.where(_isPending).length;

  bool get _showConfirmBar => _slots.any(_canPick);

  List<SalesSopSlot> get _submittableSlots {
    return _slots.where((slot) {
      if (!_canPick(slot)) return false;
      final picked = _pickedIndex(slot);
      if (picked == null) return false;
      if (_acceptedIndex(slot) == picked && slot.isAccepted) return false;
      return true;
    }).toList();
  }

  TextEditingController _noteController(String id) {
    return _noteCtrls.putIfAbsent(
      id,
      () => TextEditingController(text: _notes[id] ?? ''),
    );
  }

  TextEditingController _selectNoteController(String id) {
    return _selectNoteCtrls.putIfAbsent(id, () => TextEditingController());
  }

  List<_PreferredSlotRow> _rowsFor(SalesSopSlot slot) {
    final id = _idFor(slot);
    return _selectRows.putIfAbsent(
      id,
      () => List.generate(slot.selectionSlotCount, (_) => _PreferredSlotRow()),
    );
  }

  DateTime _minSelectable(SalesSopSlot slot) {
    final now = DateTime.now();
    if (slot.minNoticeHours <= 0) {
      return DateTime(now.year, now.month, now.day);
    }
    return now.add(Duration(hours: slot.minNoticeHours));
  }

  DateTime _combineDateAndTime(DateTime date, String time) {
    final parts = time.split(':');
    final hour = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  Future<void> _selectSlot(SalesSopSlot slot, int index) async {
    if (!_canPick(slot) || _busy) return;
    HapticFeedback.selectionClick();
    final id = _idFor(slot);
    setState(() {
      _picks[id] = index;
      _errors.remove(id);
      _collapsed.remove(id);
    });
    await _persistDrafts();
  }

  Future<void> _pickPreferredDate(SalesSopSlot slot, int index) async {
    if (!_canSelectPreferred(slot) || _busy) return;
    final row = _rowsFor(slot)[index];
    final min = _minSelectable(slot);
    final firstDate = DateTime(min.year, min.month, min.day);
    final initial = row.date != null && !row.date!.isBefore(firstDate)
        ? row.date!
        : firstDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (selected == null || !mounted) return;
    setState(() {
      row.date = selected;
      _selectRowErrors[_idFor(slot)]?.remove(index);
      _errors.remove(_idFor(slot));
    });
  }

  Future<void> _pickPreferredDateTime(SalesSopSlot slot, int index) async {
    if (!_canSelectPreferred(slot) || _busy) return;
    final row = _rowsFor(slot)[index];
    final min = _minSelectable(slot);
    final firstDate = DateTime(min.year, min.month, min.day);
    final current = row.dateTime ?? min;
    final initialDate = current.isBefore(firstDate) ? firstDate : current;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(initialDate.year, initialDate.month, initialDate.day),
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (selectedDate == null || !mounted) return;
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (!mounted) return;
    setState(() {
      if (selectedTime == null) {
        row.date = selectedDate;
        row.dateTime = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          current.hour,
          current.minute,
        );
      } else {
        row.date = selectedDate;
        row.dateTime = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          selectedTime.hour,
          selectedTime.minute,
        );
      }
      _selectRowErrors[_idFor(slot)]?.remove(index);
      _errors.remove(_idFor(slot));
    });
  }

  Future<void> _pickPreferredTimeOption(SalesSopSlot slot, int index) async {
    if (!_canSelectPreferred(slot) || _busy) return;
    final row = _rowsFor(slot)[index];
    final selected = await showModalBottomSheet<SalesSopSlotTimeOption>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _TimeOptionSheet(
        options: slot.timeOptions,
        selected: row.timeOption,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      row.timeOption = selected;
      _selectRowErrors[_idFor(slot)]?.remove(index);
      _errors.remove(_idFor(slot));
    });
  }

  Map<int, String> _validatePreferredRows(SalesSopSlot slot) {
    final errors = <int, String>{};
    final seen = <String>{};
    final now = DateTime.now();
    final rows = _rowsFor(slot);
    final validLabels = slot.timeOptions.map((option) => option.label).toSet();

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      late final DateTime selectedAt;
      late final String duplicateKey;

      if (slot.usesPredefinedTimes) {
        if (row.date == null || row.timeOption == null) {
          errors[index] = 'Choose a date and time option.';
          continue;
        }
        if (!validLabels.contains(row.timeOption!.label)) {
          errors[index] = 'Choose one of the available time options.';
          continue;
        }
        selectedAt = row.timeOption!.time.isNotEmpty
            ? _combineDateAndTime(row.date!, row.timeOption!.time)
            : DateTime(row.date!.year, row.date!.month, row.date!.day);
        duplicateKey =
            '${DateFormat('yyyy-MM-dd').format(row.date!)} ${row.timeOption!.label}';
      } else {
        if (row.dateTime == null) {
          errors[index] = 'Choose a date and time.';
          continue;
        }
        selectedAt = row.dateTime!;
        duplicateKey = DateFormat("yyyy-MM-dd'T'HH:mm").format(row.dateTime!);
      }

      if (slot.minNoticeHours > 0 &&
          selectedAt.isBefore(now.add(Duration(hours: slot.minNoticeHours)))) {
        errors[index] =
            'Slot must be at least ${slot.minNoticeHours} hours away.';
        continue;
      }
      if (!seen.add(duplicateKey)) {
        errors[index] = 'This date and time is already selected.';
      }
    }
    return errors;
  }

  Future<void> _submitPreferredSlots(SalesSopSlot slot) async {
    if (!_canSelectPreferred(slot) || _busy) return;
    final id = _idFor(slot);
    final rowErrors = _validatePreferredRows(slot);
    final note = slot.allowNote ? _selectNoteController(id).text.trim() : '';
    if (slot.requireNote && note.isEmpty) {
      setState(() {
        _selectRowErrors[id] = rowErrors;
        _errors[id] = 'A comment is required.';
        _collapsed.remove(id);
      });
      return;
    }
    if (rowErrors.isNotEmpty) {
      setState(() {
        _selectRowErrors[id] = rowErrors;
        _collapsed.remove(id);
      });
      return;
    }

    final payload = <Map<String, dynamic>>[];
    for (final row in _rowsFor(slot)) {
      if (slot.usesPredefinedTimes) {
        payload.add({
          'date': DateFormat('yyyy-MM-dd').format(row.date!),
          'time_label': row.timeOption!.label,
        });
      } else {
        payload.add({
          'value': DateFormat("yyyy-MM-dd'T'HH:mm").format(row.dateTime!),
        });
      }
    }

    setState(() {
      _submittingSelectId = id;
      _selectRowErrors.remove(id);
      _errors.remove(id);
    });

    try {
      final result = await SalesSopSlotsService().selectSlots(
        slot: slot,
        slots: payload,
        note: note,
      );
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _applyResult(result);
          _submittingSelectId = null;
        });
      } else {
        setState(() => _submittingSelectId = null);
        await reload();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferred slots submitted')),
      );
    } on SessionInvalidatedException {
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submittingSelectId = null;
        _errors[id] = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _saveAndContinueLater() async {
    await _persistDrafts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _selectedCount == 0
              ? 'Progress saved. You can finish later.'
              : 'Saved $_selectedCount selected date${_selectedCount == 1 ? '' : 's'}.',
        ),
      ),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _confirmSelected() async {
    if (_busy) return;
    final items = _submittableSlots;
    if (items.isEmpty) return;

    for (final slot in items) {
      if (!slot.requireNote) continue;
      final note = _noteController(_idFor(slot)).text.trim();
      if (note.isEmpty) {
        setState(() {
          _errors[_idFor(slot)] = 'A comment is required.';
          _collapsed.remove(_idFor(slot));
          _filter = _VisitFilter.all;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add a comment for ${slot.title}.')),
        );
        return;
      }
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ConfirmSheet(
        visits: items,
        pickedIndex: _pickedIndex,
        optionFor: _optionFor,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _confirming = true);
    var accepted = 0;
    String? lastError;
    SalesSopSlotsResult? latest;
    for (final slot in items) {
      try {
        latest = await SalesSopSlotsService().confirmSlot(
          slot: slot,
          acceptedSlotIndex: _pickedIndex(slot)!,
          note: _noteController(_idFor(slot)).text.trim(),
        );
        accepted++;
      } on SessionInvalidatedException {
        return;
      } catch (e) {
        lastError = e.toString().replaceFirst('Exception: ', '');
        setState(() => _errors[_idFor(slot)] = lastError ?? 'Could not confirm');
      }
    }

    await _persistDrafts();
    if (!mounted) return;
    setState(() {
      _confirming = false;
      if (latest != null) _applyResult(latest);
    });
    if (accepted > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted == 1
                ? '1 visit date confirmed'
                : '$accepted visit dates confirmed',
          ),
        ),
      );
    }
    if (lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lastError)),
      );
    }
    await reload();
  }

  void _showHowItWorks() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const _HowItWorksSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _slots.isEmpty) {
      return const SkeletonListLoader(
        showSummary: true,
        cardCount: 4,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
      );
    }

    if (_error != null && _slots.isEmpty) {
      return _SlotsMessage(
        icon: Icons.error_outline_rounded,
        title: 'Could not load visits',
        message: _error!,
        actionLabel: 'Retry',
        onAction: reload,
      );
    }

    if (_slots.isEmpty) {
      return RefreshIndicator(
        color: AppTheme.navy,
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: const _SlotsEmptyState(),
            ),
          ],
        ),
      );
    }

    final visible = _visibleSlots;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.navy,
            onRefresh: reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _buildHeader(),
                const SizedBox(height: 14),
                _ProgressSummary(
                  selected: _selectedCount,
                  pending: _pendingCount,
                  total: _slots.length,
                  needsSelection: _needsSelectionCount,
                  awaiting: _awaitingCount,
                  accepted: _acceptedCount,
                  onNudge: _pendingCount > 0
                      ? () => setState(() => _filter = _VisitFilter.pending)
                      : null,
                ),
                const SizedBox(height: 14),
                _FilterRow(
                  filter: _filter,
                  sort: _sort,
                  total: _slots.length,
                  pending: _pendingCount,
                  selected: _selectedCount,
                  onFilter: (value) => setState(() => _filter = value),
                  onSort: (value) => setState(() => _sort = value),
                ),
                const SizedBox(height: 8),
                if (visible.isEmpty)
                  _FilterEmptyState(
                    filter: _filter,
                    onShowAll: () =>
                        setState(() => _filter = _VisitFilter.all),
                  )
                else
                  ...List.generate(visible.length, (index) {
                    final slot = visible[index];
                    final originalIndex = _slots.indexOf(slot);
                    return _VisitTimelineItem(
                      step: originalIndex >= 0 ? originalIndex + 1 : index + 1,
                      isLast: index == visible.length - 1,
                      slot: slot,
                      selected: _isSelected(slot),
                      expanded: !_collapsed.contains(_idFor(slot)),
                      pickedIndex: _pickedIndex(slot),
                      canPick: _canPick(slot),
                      canSelectPreferred: _canSelectPreferred(slot),
                      locked: _isLocked(slot),
                      confirming: _busy,
                      submittingSelect: _submittingSelectId == _idFor(slot),
                      error: _errors[_idFor(slot)],
                      noteController: (_canPick(slot) &&
                              (slot.requireNote || slot.allowNote))
                          ? _noteController(_idFor(slot))
                          : null,
                      selectNoteController: (_canSelectPreferred(slot) &&
                              (slot.requireNote || slot.allowNote))
                          ? _selectNoteController(_idFor(slot))
                          : null,
                      preferredRows: _canSelectPreferred(slot)
                          ? _rowsFor(slot)
                          : const [],
                      preferredRowErrors:
                          _selectRowErrors[_idFor(slot)] ?? const {},
                      onToggle: () {
                        if (_canSelectPreferred(slot) || _canPick(slot)) {
                          return;
                        }
                        setState(() {
                          final id = _idFor(slot);
                          if (_collapsed.contains(id)) {
                            _collapsed.remove(id);
                          } else {
                            _collapsed.add(id);
                          }
                        });
                      },
                      onPick: (optionIndex) => _selectSlot(slot, optionIndex),
                      onChange: () {
                        setState(() => _collapsed.remove(_idFor(slot)));
                      },
                      onNoteChanged: (value) {
                        _notes[_idFor(slot)] = value;
                        if (_errors.containsKey(_idFor(slot))) {
                          setState(() => _errors.remove(_idFor(slot)));
                        }
                        _persistDrafts();
                      },
                      onSelectNoteChanged: (_) {
                        if (_errors.containsKey(_idFor(slot))) {
                          setState(() => _errors.remove(_idFor(slot)));
                        }
                      },
                      onPickPreferredDate: (rowIndex) =>
                          _pickPreferredDate(slot, rowIndex),
                      onPickPreferredDateTime: (rowIndex) =>
                          _pickPreferredDateTime(slot, rowIndex),
                      onPickPreferredTime: (rowIndex) =>
                          _pickPreferredTimeOption(slot, rowIndex),
                      onSubmitPreferred: () => _submitPreferredSlots(slot),
                    );
                  }),
              ],
            ),
          ),
        ),
        if (_showConfirmBar)
          _BottomActionBar(
            selectedCount: _submittableSlots.length,
            submittableCount: _submittableSlots.length,
            confirming: _confirming,
            bottomInset: bottomInset,
            onSaveLater: _saveAndContinueLater,
            onConfirm: _confirmSelected,
          ),
      ],
    );
  }

  Widget _buildHeader() {
    final hasSelect = _slots.any((slot) => slot.needsSelection);
    final hasConfirm = _slots.any((slot) => slot.isAwaitingConfirmation);
    final subtitle = hasSelect && hasConfirm
        ? 'Pick preferred times where assigned, or confirm one option when you can accept.'
        : hasSelect
            ? 'Choose preferred dates and times for visits that still need selection.'
            : 'Each visit has preferred dates. Choose one date to confirm.';
    final title = widget.showInlineTitle
        ? const Text(
            'Slots',
            style: TextStyle(
              color: AppTheme.navy,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.15,
            ),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 8),
              _HowItWorksChip(onTap: _showHowItWorks),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.mutedGrey,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _HowItWorksChip(onTap: _showHowItWorks),
            ],
          ),
      ],
    );
  }
}

class _HowItWorksChip extends StatelessWidget {
  final VoidCallback onTap;

  const _HowItWorksChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEFF4FF),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_outlined, size: 14, color: AppTheme.accentBlue),
              SizedBox(width: 5),
              Text(
                'How it works?',
                style: TextStyle(
                  color: AppTheme.accentBlue,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressSummary extends StatelessWidget {
  final int selected;
  final int pending;
  final int total;
  final int needsSelection;
  final int awaiting;
  final int accepted;
  final VoidCallback? onNudge;

  const _ProgressSummary({
    required this.selected,
    required this.pending,
    required this.total,
    required this.needsSelection,
    required this.awaiting,
    required this.accepted,
    this.onNudge,
  });

  @override
  Widget build(BuildContext context) {
    final safeTotal = math.max(total, 1);
    final percent = (accepted / safeTotal).clamp(0.0, 1.0);
    final done = pending == 0 && total > 0;
    final title = needsSelection > 0
        ? 'Pick preferred times'
        : awaiting > 0
            ? 'Confirm visit dates'
            : selected == 0
                ? 'Get started'
                : 'Almost there';
    final subtitle = needsSelection > 0
        ? '$needsSelection visit${needsSelection == 1 ? '' : 's'} need preferred slots'
        : awaiting > 0
            ? '$awaiting visit${awaiting == 1 ? '' : 's'} waiting for confirmation'
            : 'Select dates for $pending more visit${pending == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircularPercentIndicator(
            radius: 26,
            lineWidth: 5,
            percent: percent,
            animation: true,
            animationDuration: 700,
            circularStrokeCap: CircularStrokeCap.round,
            progressColor: const Color(0xFF16A34A),
            backgroundColor: const Color(0xFFE8ECF1),
            center: Text(
              '$accepted/$total',
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$accepted accepted · $pending pending',
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (needsSelection > 0)
                      '$needsSelection to pick',
                    if (awaiting > 0) '$awaiting to confirm',
                  ].isEmpty
                      ? '$pending visit${pending == 1 ? '' : 's'} pending'
                      : [
                          if (needsSelection > 0)
                            '$needsSelection to pick',
                          if (awaiting > 0) '$awaiting to confirm',
                        ].join(' · '),
                  style: const TextStyle(
                    color: AppTheme.mutedGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (!done) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Material(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onNudge,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event_available_outlined,
                          size: 16,
                          color: Color(0xFF047857),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Color(0xFF047857),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF166534),
                                  fontSize: 10.5,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (onNudge != null)
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Color(0xFF047857),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final _VisitFilter filter;
  final _VisitSort sort;
  final int total;
  final int pending;
  final int selected;
  final ValueChanged<_VisitFilter> onFilter;
  final ValueChanged<_VisitSort> onSort;

  const _FilterRow({
    required this.filter,
    required this.sort,
    required this.total,
    required this.pending,
    required this.selected,
    required this.onFilter,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterPill(
                  label: 'All ($total)',
                  selected: filter == _VisitFilter.all,
                  onTap: () => onFilter(_VisitFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: 'Pending ($pending)',
                  selected: filter == _VisitFilter.pending,
                  onTap: () => onFilter(_VisitFilter.pending),
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: 'Selected ($selected)',
                  selected: filter == _VisitFilter.selected,
                  onTap: () => onFilter(_VisitFilter.selected),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_VisitSort>(
          tooltip: 'Sort visits',
          onSelected: onSort,
          offset: const Offset(0, 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _VisitSort.visitOrder,
              child: Text('Visit order'),
            ),
            PopupMenuItem(
              value: _VisitSort.pendingFirst,
              child: Text('Pending first'),
            ),
            PopupMenuItem(
              value: _VisitSort.name,
              child: Text('Name A–Z'),
            ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_vert_rounded, size: 16, color: AppTheme.navy),
              const SizedBox(width: 4),
              Text(
                sort == _VisitSort.name
                    ? 'Name'
                    : sort == _VisitSort.pendingFirst
                        ? 'Pending'
                        : 'Visit order',
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Icon(Icons.expand_more_rounded, size: 16, color: AppTheme.navy),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.navy : const Color(0xFFEEF2F7),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTheme.navy,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _VisitTimelineItem extends StatelessWidget {
  final int step;
  final bool isLast;
  final SalesSopSlot slot;
  final bool selected;
  final bool expanded;
  final int? pickedIndex;
  final bool canPick;
  final bool canSelectPreferred;
  final bool locked;
  final bool confirming;
  final bool submittingSelect;
  final String? error;
  final TextEditingController? noteController;
  final TextEditingController? selectNoteController;
  final List<_PreferredSlotRow> preferredRows;
  final Map<int, String> preferredRowErrors;
  final VoidCallback onToggle;
  final ValueChanged<int> onPick;
  final VoidCallback onChange;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<String> onSelectNoteChanged;
  final ValueChanged<int> onPickPreferredDate;
  final ValueChanged<int> onPickPreferredDateTime;
  final ValueChanged<int> onPickPreferredTime;
  final VoidCallback onSubmitPreferred;

  const _VisitTimelineItem({
    required this.step,
    required this.isLast,
    required this.slot,
    required this.selected,
    required this.expanded,
    required this.pickedIndex,
    required this.canPick,
    required this.canSelectPreferred,
    required this.locked,
    required this.confirming,
    required this.submittingSelect,
    required this.error,
    required this.noteController,
    required this.selectNoteController,
    required this.preferredRows,
    required this.preferredRowErrors,
    required this.onToggle,
    required this.onPick,
    required this.onChange,
    required this.onNoteChanged,
    required this.onSelectNoteChanged,
    required this.onPickPreferredDate,
    required this.onPickPreferredDateTime,
    required this.onPickPreferredTime,
    required this.onSubmitPreferred,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                _StepBadge(step: step, selected: selected),
                if (!isLast)
                  Expanded(
                    child: CustomPaint(
                      painter: _TimelineLinePainter(
                        color: selected
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFD5DCE6),
                        dashed: !selected,
                      ),
                      child: const SizedBox(width: 28),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 4 : 12),
              child: _VisitCard(
                slot: slot,
                selected: selected,
                expanded: expanded,
                pickedIndex: pickedIndex,
                canPick: canPick,
                canSelectPreferred: canSelectPreferred,
                locked: locked,
                confirming: confirming,
                submittingSelect: submittingSelect,
                error: error,
                noteController: noteController,
                selectNoteController: selectNoteController,
                preferredRows: preferredRows,
                preferredRowErrors: preferredRowErrors,
                onToggle: onToggle,
                onPick: onPick,
                onChange: onChange,
                onNoteChanged: onNoteChanged,
                onSelectNoteChanged: onSelectNoteChanged,
                onPickPreferredDate: onPickPreferredDate,
                onPickPreferredDateTime: onPickPreferredDateTime,
                onPickPreferredTime: onPickPreferredTime,
                onSubmitPreferred: onSubmitPreferred,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  final int step;
  final bool selected;

  const _StepBadge({required this.step, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF16A34A) : AppTheme.navy,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (selected ? const Color(0xFF16A34A) : AppTheme.navy)
                .withValues(alpha: 0.22),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$step',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _TimelineLinePainter extends CustomPainter {
  final Color color;
  final bool dashed;

  const _TimelineLinePainter({required this.color, required this.dashed});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    if (!dashed) {
      canvas.drawLine(Offset(x, 2), Offset(x, size.height), paint);
      return;
    }
    const dash = 3.0;
    const gap = 3.0;
    var y = 2.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dash, size.height)),
        paint,
      );
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineLinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.dashed != dashed;
  }
}

class _VisitCard extends StatelessWidget {
  final SalesSopSlot slot;
  final bool selected;
  final bool expanded;
  final int? pickedIndex;
  final bool canPick;
  final bool canSelectPreferred;
  final bool locked;
  final bool confirming;
  final bool submittingSelect;
  final String? error;
  final TextEditingController? noteController;
  final TextEditingController? selectNoteController;
  final List<_PreferredSlotRow> preferredRows;
  final Map<int, String> preferredRowErrors;
  final VoidCallback onToggle;
  final ValueChanged<int> onPick;
  final VoidCallback onChange;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<String> onSelectNoteChanged;
  final ValueChanged<int> onPickPreferredDate;
  final ValueChanged<int> onPickPreferredDateTime;
  final ValueChanged<int> onPickPreferredTime;
  final VoidCallback onSubmitPreferred;

  const _VisitCard({
    required this.slot,
    required this.selected,
    required this.expanded,
    required this.pickedIndex,
    required this.canPick,
    required this.canSelectPreferred,
    required this.locked,
    required this.confirming,
    required this.submittingSelect,
    required this.error,
    required this.noteController,
    required this.selectNoteController,
    required this.preferredRows,
    required this.preferredRowErrors,
    required this.onToggle,
    required this.onPick,
    required this.onChange,
    required this.onNoteChanged,
    required this.onSelectNoteChanged,
    required this.onPickPreferredDate,
    required this.onPickPreferredDateTime,
    required this.onPickPreferredTime,
    required this.onSubmitPreferred,
  });

  @override
  Widget build(BuildContext context) {
    final look = _visitLook(slot.title);
    final picked = _optionByIndex(slot, pickedIndex);
    final location = _locationFor(slot);
    final status = _statusLook(slot, selected: selected, canPick: canPick);

    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFF4FBF6) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? const Color(0xFF86EFAC) : AppTheme.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: look.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(look.icon, size: 20, color: look.foreground),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slot.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.navy,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: AppTheme.mutedGrey,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.mutedGrey,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _StatusPill(look: status),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.mutedGrey,
                  ),
                ],
              ),
            ),
          ),
          if (slot.givenMeta.isNotEmpty && expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                slot.givenMeta,
                style: const TextStyle(
                  color: AppTheme.accentBlue,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (expanded && slot.isSiteInspection)
            ..._siteInspectionExtras(slot),
          if (expanded && canSelectPreferred)
            _PreferredSlotsForm(
              slot: slot,
              rows: preferredRows,
              rowErrors: preferredRowErrors,
              noteController: selectNoteController,
              submitting: submittingSelect,
              enabled: !confirming,
              onPickDate: onPickPreferredDate,
              onPickDateTime: onPickPreferredDateTime,
              onPickTime: onPickPreferredTime,
              onNoteChanged: onSelectNoteChanged,
              onSubmit: onSubmitPreferred,
            )
          else if (expanded && slot.options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: _SlotChoices(
                options: slot.options,
                pickedIndex: pickedIndex,
                enabled: canPick && !confirming,
                onPick: onPick,
              ),
            ),
          if (expanded && slot.clientNote.isNotEmpty)
            _QuoteBlock(label: 'Client comment', text: slot.clientNote),
          if (expanded && slot.confirmationNote.isNotEmpty)
            _QuoteBlock(
              label: 'Confirmation comment',
              text: slot.confirmationNote,
            ),
          if (expanded &&
              ((slot.needsSelection && !slot.canSelect) ||
                  (slot.isAwaitingConfirmation && !slot.canAccept)))
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: _WaitingBanner(text: slot.waitingBannerText),
            ),
          if (expanded && noteController != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: TextField(
                controller: noteController,
                minLines: 2,
                maxLines: 3,
                enabled: !confirming,
                onChanged: onNoteChanged,
                style: const TextStyle(
                  color: AppTheme.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: slot.requireNote
                      ? 'Add a required comment'
                      : 'Add a comment (optional)',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppTheme.accentBlue,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                error!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (selected && picked != null && !canSelectPreferred)
            _SelectedFooter(
              option: picked,
              canChange: canPick && !locked,
              onChange: onChange,
            ),
        ],
      ),
      ),
    );
  }
}

class _StatusLook {
  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;

  const _StatusLook({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
  });
}

_StatusLook _statusLook(
  SalesSopSlot slot, {
  required bool selected,
  required bool canPick,
}) {
  if (slot.isAccepted) {
    return const _StatusLook(
      label: 'Accepted',
      background: Color(0xFFDCFCE7),
      foreground: Color(0xFF15803D),
      icon: Icons.check_rounded,
    );
  }
  if (slot.needsSelection) {
    return _StatusLook(
      label: slot.canSelect ? 'Pick times' : 'Needs slots',
      background: const Color(0xFFEFF6FF),
      foreground: AppTheme.accentBlue,
      icon: Icons.edit_calendar_outlined,
    );
  }
  if (slot.isAwaitingConfirmation) {
    if (canPick && selected) {
      return const _StatusLook(
        label: 'Selected',
        background: Color(0xFFDCFCE7),
        foreground: Color(0xFF15803D),
        icon: Icons.check_rounded,
      );
    }
    return _StatusLook(
      label: canPick ? 'Confirm' : 'Awaiting',
      background: const Color(0xFFFFFBEB),
      foreground: const Color(0xFFB45309),
      icon: Icons.schedule_rounded,
    );
  }
  if (slot.isSubmitted) {
    return const _StatusLook(
      label: 'Submitted',
      background: Color(0xFFEEF2F7),
      foreground: AppTheme.mutedGrey,
      icon: Icons.hourglass_top_rounded,
    );
  }
  return _StatusLook(
    label: selected ? 'Selected' : (slot.statusLabel.isEmpty ? 'Pending' : slot.statusLabel),
    background: selected ? const Color(0xFFDCFCE7) : const Color(0xFFEEF2F7),
    foreground: selected ? const Color(0xFF15803D) : AppTheme.mutedGrey,
    icon: selected ? Icons.check_rounded : Icons.schedule_rounded,
  );
}

class _StatusPill extends StatelessWidget {
  final _StatusLook look;

  const _StatusPill({required this.look});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 1, right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: look.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(look.icon, size: 12, color: look.foreground),
          const SizedBox(width: 3),
          Text(
            look.label,
            style: TextStyle(
              color: look.foreground,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferredSlotsForm extends StatelessWidget {
  final SalesSopSlot slot;
  final List<_PreferredSlotRow> rows;
  final Map<int, String> rowErrors;
  final TextEditingController? noteController;
  final bool submitting;
  final bool enabled;
  final ValueChanged<int> onPickDate;
  final ValueChanged<int> onPickDateTime;
  final ValueChanged<int> onPickTime;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onSubmit;

  const _PreferredSlotsForm({
    required this.slot,
    required this.rows,
    required this.rowErrors,
    required this.noteController,
    required this.submitting,
    required this.enabled,
    required this.onPickDate,
    required this.onPickDateTime,
    required this.onPickTime,
    required this.onNoteChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (slot.selectionHelperText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
              child: Text(
                slot.selectionHelperText,
                style: const TextStyle(
                  color: AppTheme.mutedGrey,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ...List.generate(rows.length, (index) {
            final row = rows[index];
            final error = rowErrors[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: error == null
                      ? AppTheme.border
                      : const Color(0xFFFECACA),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Slot ${index + 1}',
                    style: const TextStyle(
                      color: AppTheme.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (slot.usesPredefinedTimes) ...[
                    _PickerTile(
                      icon: Icons.calendar_today_outlined,
                      label: row.date == null
                          ? 'Select date'
                          : DateFormat('dd MMM yyyy').format(row.date!),
                      enabled: enabled && !submitting,
                      onTap: () => onPickDate(index),
                    ),
                    const SizedBox(height: 8),
                    _PickerTile(
                      icon: Icons.access_time_outlined,
                      label: row.timeOption == null
                          ? 'Select time'
                          : row.timeOption!.display,
                      enabled: enabled && !submitting,
                      onTap: () => onPickTime(index),
                    ),
                  ] else
                    _PickerTile(
                      icon: Icons.schedule_outlined,
                      label: row.dateTime == null
                          ? 'Select date and time'
                          : DateFormat('dd MMM yyyy, h:mm a')
                              .format(row.dateTime!),
                      enabled: enabled && !submitting,
                      onTap: () => onPickDateTime(index),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      error,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
          if (noteController != null) ...[
            TextField(
              controller: noteController,
              minLines: 2,
              maxLines: 3,
              enabled: enabled && !submitting,
              onChanged: onNoteChanged,
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: slot.requireNote
                    ? 'Add a required comment'
                    : 'Add a comment (optional)',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.accentBlue,
                    width: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: enabled && !submitting ? onSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.navy,
                disabledBackgroundColor: const Color(0xFFD1D5DB),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      slot.selectButtonLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PickerTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.navy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppTheme.mutedGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeOptionSheet extends StatelessWidget {
  final List<SalesSopSlotTimeOption> options;
  final SalesSopSlotTimeOption? selected;

  const _TimeOptionSheet({
    required this.options,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select time option',
              style: TextStyle(
                color: AppTheme.navy,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = selected?.label == option.label;
                  return Material(
                    color: isSelected
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, option),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.display,
                                style: const TextStyle(
                                  color: AppTheme.navy,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF16A34A),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotChoices extends StatelessWidget {
  final List<SalesSopSlotOption> options;
  final int? pickedIndex;
  final bool enabled;
  final ValueChanged<int> onPick;

  const _SlotChoices({
    required this.options,
    required this.pickedIndex,
    required this.enabled,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final children = options.take(3).map((option) {
      final isPicked = pickedIndex == option.index;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: _SlotRadioCard(
            option: option,
            selected: isPicked,
            enabled: enabled,
            onTap: () => onPick(option.index),
          ),
        ),
      );
    }).toList();

    if (options.length > 3) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: options.map((option) {
          return SizedBox(
            width: (MediaQuery.sizeOf(context).width - 86) / 3,
            child: _SlotRadioCard(
              option: option,
              selected: pickedIndex == option.index,
              enabled: enabled,
              onTap: () => onPick(option.index),
            ),
          );
        }).toList(),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _SlotRadioCard extends StatelessWidget {
  final SalesSopSlotOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _SlotRadioCard({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final parts = _slotDisplay(option);
    final border = selected ? const Color(0xFF16A34A) : AppTheme.border;
    final background = selected ? const Color(0xFFECFDF5) : Colors.white;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RadioDot(selected: selected),
                  const SizedBox(height: 6),
                  Text(
                    parts.dateLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.navy,
                      fontSize: 11.5,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                  if (parts.timeLine.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      parts.timeLine,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.mutedGrey,
                        fontSize: 10,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;

  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFF16A34A) : const Color(0xFFD1D5DB),
          width: 1.6,
        ),
        color: Colors.white,
      ),
      child: selected
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

class _SelectedFooter extends StatelessWidget {
  final SalesSopSlotOption option;
  final bool canChange;
  final VoidCallback onChange;

  const _SelectedFooter({
    required this.option,
    required this.canChange,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final parts = _slotDisplay(option);
    final summary = [
      parts.dateLine,
      if (parts.timeLine.isNotEmpty) parts.timeLine,
    ].join(' · ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
      decoration: const BoxDecoration(
        color: Color(0xFFECFDF5),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(17)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            size: 14,
            color: Color(0xFF047857),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Selected: $summary',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.navy,
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (canChange)
            TextButton(
              onPressed: onChange,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.accentBlue,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(44, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Change',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final int selectedCount;
  final int submittableCount;
  final bool confirming;
  final double bottomInset;
  final VoidCallback onSaveLater;
  final VoidCallback onConfirm;

  const _BottomActionBar({
    required this.selectedCount,
    required this.submittableCount,
    required this.confirming,
    required this.bottomInset,
    required this.onSaveLater,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final confirmLabel = selectedCount == 0
        ? 'Confirm Selected Dates'
        : 'Confirm $selectedCount Selected Date${selectedCount == 1 ? '' : 's'}';

    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: AppTheme.softShadow,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + math.max(bottomInset, 8)),
        child: SafeArea(
          top: false,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 4,
                  child: OutlinedButton(
                    onPressed: confirming ? null : onSaveLater,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentBlue,
                      side: const BorderSide(color: Color(0xFFBFDBFE)),
                      backgroundColor: const Color(0xFFEFF6FF),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bookmark_border_rounded, size: 18),
                        SizedBox(height: 4),
                        Text(
                          'Save &\nContinue Later',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: ElevatedButton(
                    onPressed:
                        confirming || submittableCount == 0 ? null : onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      disabledBackgroundColor: const Color(0xFFD1D5DB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: confirming
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            '$confirmLabel  →',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  final List<SalesSopSlot> visits;
  final int? Function(SalesSopSlot slot) pickedIndex;
  final SalesSopSlotOption? Function(SalesSopSlot slot, int? index) optionFor;

  const _ConfirmSheet({
    required this.visits,
    required this.pickedIndex,
    required this.optionFor,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Confirm visit dates',
              style: TextStyle(
                color: AppTheme.navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You are confirming ${visits.length} selected date${visits.length == 1 ? '' : 's'}.',
              style: const TextStyle(
                color: AppTheme.mutedGrey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.42,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: visits.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final slot = visits[index];
                  final option = optionFor(slot, pickedIndex(slot));
                  final parts = option == null ? null : _slotDisplay(option);
                  return Text(
                    '${slot.title}  ·  ${parts == null ? 'Selected' : [parts.dateLine, parts.timeLine].where((e) => e.isNotEmpty).join(' · ')}',
                    style: const TextStyle(
                      color: AppTheme.navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                    ),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksSheet extends StatelessWidget {
  const _HowItWorksSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'How it works',
              style: TextStyle(
                color: AppTheme.navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            const _HowStep(
              number: '1',
              title: 'Pick preferred times',
              body: 'If a visit needs selection, choose the requested dates and times and submit them here.',
            ),
            const _HowStep(
              number: '2',
              title: 'Confirm one option',
              body: 'When preferred slots are in, whoever can confirm picks one date. Site inspection still uses its own accept action.',
            ),
            const _HowStep(
              number: '3',
              title: 'Same work as Tasks',
              body: 'Doing this here completes the same workflow task. Tasks stay available as another place to do it.',
            ),
          ],
        ),
      ),
    );
  }
}

class _HowStep extends StatelessWidget {
  final String number;
  final String title;
  final String body;

  const _HowStep({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: AppTheme.navy,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppTheme.mutedGrey,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterEmptyState extends StatelessWidget {
  final _VisitFilter filter;
  final VoidCallback onShowAll;

  const _FilterEmptyState({
    required this.filter,
    required this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final title = filter == _VisitFilter.pending
        ? 'No pending visits'
        : 'No selected visits yet';
    final message = filter == _VisitFilter.pending
        ? 'Nothing needs picking or confirming right now.'
        : 'Confirmed and submitted visits will show here.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onShowAll, child: const Text('Show all visits')),
        ],
      ),
    );
  }
}

class _SlotsEmptyState extends StatelessWidget {
  const _SlotsEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available_outlined, size: 42, color: AppTheme.accentBlue),
            SizedBox(height: 16),
            Text(
              'No slots yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'When a visit needs preferred times or a confirmation, it will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: AppTheme.mutedGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotsMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _SlotsMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: AppTheme.mutedGrey),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.mutedGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _QuoteBlock extends StatelessWidget {
  final String label;
  final String text;

  const _QuoteBlock({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 42,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              color: AppTheme.accentBlue,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentBlue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF374151),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitingBanner extends StatelessWidget {
  final String text;

  const _WaitingBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 18, color: Color(0xFFD97706)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitLook {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _VisitLook({
    required this.icon,
    required this.background,
    required this.foreground,
  });
}

_VisitLook _visitLook(String title) {
  final text = title.toLowerCase();
  if (text.contains('wood')) {
    return const _VisitLook(
      icon: Icons.forest_outlined,
      background: Color(0xFFF5E6D3),
      foreground: Color(0xFF9A3412),
    );
  }
  if (text.contains('paint')) {
    return const _VisitLook(
      icon: Icons.format_paint_outlined,
      background: Color(0xFFEEF2FF),
      foreground: Color(0xFF4338CA),
    );
  }
  if (text.contains('tile')) {
    return const _VisitLook(
      icon: Icons.grid_view_rounded,
      background: Color(0xFFECFEFF),
      foreground: Color(0xFF0F766E),
    );
  }
  if (text.contains('light')) {
    return const _VisitLook(
      icon: Icons.lightbulb_outline_rounded,
      background: Color(0xFFFEF3C7),
      foreground: Color(0xFFB45309),
    );
  }
  if (text.contains('furniture') || text.contains('sofa')) {
    return const _VisitLook(
      icon: Icons.chair_outlined,
      background: Color(0xFFF3E8FF),
      foreground: Color(0xFF6D28D9),
    );
  }
  if (text.contains('curtain') || text.contains('drape')) {
    return const _VisitLook(
      icon: Icons.curtains_outlined,
      background: Color(0xFFFCE7F3),
      foreground: Color(0xFFBE185D),
    );
  }
  if (text.contains('inspect') || text.contains('site')) {
    return const _VisitLook(
      icon: Icons.fact_check_outlined,
      background: Color(0xFFECFDF5),
      foreground: Color(0xFF047857),
    );
  }
  return const _VisitLook(
    icon: Icons.event_available_outlined,
    background: Color(0xFFEEF2F7),
    foreground: AppTheme.navy,
  );
}

class _SlotParts {
  final String dateLine;
  final String timeLine;

  const _SlotParts({required this.dateLine, required this.timeLine});
}

_SlotParts _slotDisplay(SalesSopSlotOption option) {
  final display = option.display.trim();
  final time = option.timeLabel.trim();
  if (time.isNotEmpty && time != display) {
    return _SlotParts(dateLine: _compactDate(display), timeLine: _prettyTime(time));
  }

  final match = RegExp(
    r'(\d{1,2}:\d{2}\s*(?:AM|PM)(?:\s*[–\-to]+\s*\d{1,2}:\d{2}\s*(?:AM|PM))?)\s*$',
    caseSensitive: false,
  ).firstMatch(display);
  if (match != null) {
    final datePart = display
        .substring(0, match.start)
        .replaceAll(RegExp(r'[·,|\-]+\s*$'), '')
        .trim();
    return _SlotParts(
      dateLine: _compactDate(datePart.isEmpty ? display : datePart),
      timeLine: _prettyTime(match.group(1)!),
    );
  }
  return _SlotParts(dateLine: _compactDate(display), timeLine: _prettyTime(time));
}

String _prettyTime(String value) {
  return value.replaceAll(RegExp(r'\s*-\s*'), ' – ').replaceAll(RegExp(r'\s+to\s+', caseSensitive: false), ' – ');
}

String _compactDate(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return cleaned;
  final parsed = DateTime.tryParse(cleaned) ?? _parseLooseDate(cleaned);
  if (parsed != null) {
    return DateFormat('EEE, d MMM').format(parsed);
  }
  return cleaned
      .replaceAll(RegExp(r'\b20\d{2}\b'), '')
      .replaceAll(RegExp(r'\s+,'), ',')
      .replaceAll(RegExp(r',\s*$'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

DateTime? _parseLooseDate(String raw) {
  final formats = <DateFormat>[
    DateFormat('EEE, d MMM yyyy'),
    DateFormat('EEEE, d MMMM yyyy'),
    DateFormat('d MMM yyyy'),
    DateFormat('d MMMM yyyy'),
    DateFormat('yyyy-MM-dd'),
    DateFormat('dd/MM/yyyy'),
  ];
  for (final format in formats) {
    try {
      return format.parseLoose(raw);
    } catch (_) {}
  }
  return null;
}

SalesSopSlotOption? _optionByIndex(SalesSopSlot slot, int? index) {
  if (index == null) return null;
  for (final option in slot.options) {
    if (option.index == index) return option;
  }
  return null;
}

String _locationFor(SalesSopSlot slot) {
  if (slot.presenceLabel.isNotEmpty) return slot.presenceLabel;
  if (slot.givenMeta.isNotEmpty) return slot.givenMeta;
  if (slot.isSiteInspection) return 'Site inspection visit';
  if (slot.selectionTaskName.isNotEmpty) return slot.selectionTaskName;
  if (slot.needsSelection) return 'Preferred times needed';
  if (slot.isAwaitingConfirmation) return 'Waiting for confirmation';
  return 'Visit slot';
}

List<Widget> _siteInspectionExtras(SalesSopSlot slot) {
  final extras = <Widget>[];
  if (slot.virtualConnectionDetails.isNotEmpty) {
    extras.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Meeting details',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                slot.virtualConnectionDetails,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  if (slot.siteCleanedConfirmed || slot.siteCleanedProofUrl.isNotEmpty) {
    extras.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Row(
          children: [
            if (slot.siteCleanedConfirmed) ...[
              const Icon(Icons.check_circle, size: 16, color: Color(0xFF16A34A)),
              const SizedBox(width: 6),
              const Text(
                'Site cleaned',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
            if (slot.siteCleanedProofUrl.isNotEmpty) ...[
              if (slot.siteCleanedConfirmed) const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _openUrl(slot.siteCleanedProofUrl),
                child: const Text(
                  'View proof',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accentBlue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  return extras;
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
