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
      title: 'Select Visit Dates',
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

class SlotsViewState extends State<SlotsView> {
  static const _draftPicksKey = 'sales_sop_slot_draft_picks';
  static const _draftNotesKey = 'sales_sop_slot_draft_notes';

  bool _loading = true;
  bool _confirming = false;
  String? _error;
  List<SalesSopSlot> _slots = const [];
  final Map<String, int> _picks = {};
  final Map<String, String> _notes = {};
  final Map<String, String> _errors = {};
  final Map<String, TextEditingController> _noteCtrls = {};
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
        _slots = result.slots;
        _syncPicksToSlots();
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
        _collapsed.add(id);
      } else if (!_picks.containsKey(id)) {
        _collapsed.remove(id);
      }
    }
    _picks.removeWhere((key, _) => !valid.contains(key));
    _notes.removeWhere((key, _) => !valid.contains(key));
  }

  String _idFor(SalesSopSlot slot) {
    return [
      slot.source,
      slot.itemRunId,
      slot.confirmActionId,
      slot.confirmUrl,
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

  bool _isSelected(SalesSopSlot slot) => _pickedIndex(slot) != null;

  bool _isLocked(SalesSopSlot slot) =>
      slot.isAccepted || !slot.canAccept || slot.options.isEmpty;

  bool _canPick(SalesSopSlot slot) =>
      slot.canAccept && slot.isAwaitingConfirmation && slot.options.isNotEmpty;

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
        items = items.where((slot) => !_isSelected(slot));
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

  int get _pendingCount => _slots.length - _selectedCount;

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

  Future<void> _selectSlot(SalesSopSlot slot, int index) async {
    if (!_canPick(slot) || _confirming) return;
    HapticFeedback.selectionClick();
    final id = _idFor(slot);
    setState(() {
      _picks[id] = index;
      _errors.remove(id);
      _collapsed.remove(id);
    });
    await _persistDrafts();
  }

  Future<void> _saveAndContinueLater() async {
    await _persistDrafts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _selectedCount == 0
              ? 'Progress saved. You can finish selecting later.'
              : 'Saved $_selectedCount selected date${_selectedCount == 1 ? '' : 's'}.',
        ),
      ),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _confirmSelected() async {
    if (_confirming) return;
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
    for (final slot in items) {
      try {
        await SalesSopSlotsService().acceptSlot(
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
    setState(() => _confirming = false);
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
                      locked: _isLocked(slot),
                      confirming: _confirming,
                      error: _errors[_idFor(slot)],
                      noteController: slot.requireNote && _canPick(slot)
                          ? _noteController(_idFor(slot))
                          : null,
                      onToggle: () {
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
                    );
                  }),
              ],
            ),
          ),
        ),
        _BottomActionBar(
          selectedCount: _selectedCount,
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
    final title = widget.showInlineTitle
        ? const Text(
            'Select Visit Dates',
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
          const Text(
            'Each visit has 3 possible dates. Choose one date for each visit.',
            style: TextStyle(
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
              const Expanded(
                child: Text(
                  'Each visit has 3 possible dates. Choose one date for each visit.',
                  style: TextStyle(
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
  final VoidCallback? onNudge;

  const _ProgressSummary({
    required this.selected,
    required this.pending,
    required this.total,
    this.onNudge,
  });

  @override
  Widget build(BuildContext context) {
    final safeTotal = math.max(total, 1);
    final percent = (selected / safeTotal).clamp(0.0, 1.0);
    final done = pending == 0 && total > 0;
    final title = selected == 0 ? 'Get started' : 'Almost there';
    final subtitle = selected == 0
        ? 'Select a date for your first visit'
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
              '$selected/$total',
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
                  '$selected visit${selected == 1 ? '' : 's'} selected',
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$pending visit${pending == 1 ? '' : 's'} pending',
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
  final bool locked;
  final bool confirming;
  final String? error;
  final TextEditingController? noteController;
  final VoidCallback onToggle;
  final ValueChanged<int> onPick;
  final VoidCallback onChange;
  final ValueChanged<String> onNoteChanged;

  const _VisitTimelineItem({
    required this.step,
    required this.isLast,
    required this.slot,
    required this.selected,
    required this.expanded,
    required this.pickedIndex,
    required this.canPick,
    required this.locked,
    required this.confirming,
    required this.error,
    required this.noteController,
    required this.onToggle,
    required this.onPick,
    required this.onChange,
    required this.onNoteChanged,
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
                locked: locked,
                confirming: confirming,
                error: error,
                noteController: noteController,
                onToggle: onToggle,
                onPick: onPick,
                onChange: onChange,
                onNoteChanged: onNoteChanged,
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
  final bool locked;
  final bool confirming;
  final String? error;
  final TextEditingController? noteController;
  final VoidCallback onToggle;
  final ValueChanged<int> onPick;
  final VoidCallback onChange;
  final ValueChanged<String> onNoteChanged;

  const _VisitCard({
    required this.slot,
    required this.selected,
    required this.expanded,
    required this.pickedIndex,
    required this.canPick,
    required this.locked,
    required this.confirming,
    required this.error,
    required this.noteController,
    required this.onToggle,
    required this.onPick,
    required this.onChange,
    required this.onNoteChanged,
  });

  @override
  Widget build(BuildContext context) {
    final look = _visitLook(slot.title);
    final picked = _optionByIndex(slot, pickedIndex);
    final location = _locationFor(slot);

    return AnimatedContainer(
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
                  _StatusPill(selected: selected),
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
          if (expanded && slot.options.isNotEmpty)
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
          if (expanded && slot.isAwaitingConfirmation && !slot.canAccept)
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
                  hintText: 'Add a required comment',
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
          if (selected && picked != null)
            _SelectedFooter(
              option: picked,
              canChange: canPick && !locked,
              onChange: onChange,
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool selected;

  const _StatusPill({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 1, right: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFDCFCE7) : const Color(0xFFEEF2F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.check_rounded : Icons.schedule_rounded,
            size: 12,
            color: selected ? const Color(0xFF15803D) : AppTheme.mutedGrey,
          ),
          const SizedBox(width: 3),
          Text(
            selected ? 'Selected' : 'Pending',
            style: TextStyle(
              color: selected ? const Color(0xFF15803D) : AppTheme.mutedGrey,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: border,
              width: selected ? 1.4 : 1,
            ),
          ),
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
              title: 'Review each visit',
              body: 'The client has shared 3 possible dates for every visit.',
            ),
            const _HowStep(
              number: '2',
              title: 'Choose exactly one slot',
              body: 'Tap one date and time per visit. You can change it anytime before confirming.',
            ),
            const _HowStep(
              number: '3',
              title: 'Confirm when ready',
              body: 'Use Pending to finish leftover visits, then confirm the selected dates.',
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
        ? 'Every visit already has a date.'
        : 'Choose a slot to see it here.';
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
              'No visit dates yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'When the client shares preferred times, they will show up here.',
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
  return 'Client preferred times';
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
