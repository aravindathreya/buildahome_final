import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:intl/intl.dart';
import '../models/sales_sop_slot.dart';
import 'site_visits_ui.dart';

class VisitPreference {
  final DateTime dateTime;
  final SalesSopSlotTimeOption? timeOption;
  const VisitPreference(this.dateTime, this.timeOption);
}

class SiteVisitBooking extends StatefulWidget {
  final SalesSopSlot slot;
  final bool selectPreferred;
  final void Function(
      int? index, List<VisitPreference> preferences, String note)? onDraft;
  final int? initialIndex;
  final String initialNote;
  final List<VisitPreference> initialPreferences;
  final Future<void> Function(
      int? index, List<VisitPreference> preferences, String note) onSubmit;
  final bool readOnly;
  const SiteVisitBooking(
      {super.key,
      required this.slot,
      required this.onSubmit,
      this.selectPreferred = false,
      this.onDraft,
      this.initialIndex,
      this.initialNote = '',
      this.initialPreferences = const [],
      this.readOnly = false});
  @override
  State<SiteVisitBooking> createState() => _BookingState();
}

class _BookingState extends State<SiteVisitBooking> {
  int step = 0;
  DateTime? date;
  late DateTime month;
  SalesSopSlotOption? option;
  SalesSopSlotTimeOption? time;
  TimeOfDay? customTime;
  late TextEditingController note;
  final List<VisitPreference> preferences = [];
  bool saving = false;
  bool success = false;
  String? error;
  SalesSopSlot get slot => widget.slot;
  bool get preferred => widget.selectPreferred;
  DateTime get minimum =>
      DateTime.now().add(Duration(hours: slot.minNoticeHours));
  @override
  void initState() {
    super.initState();
    note = TextEditingController(text: widget.initialNote);
    note.addListener(_saveDraft);
    preferences.addAll(widget.initialPreferences);
    for (final item in slot.options) {
      if (item.index == widget.initialIndex) {
        option = item;
        date = item.parsedDateTime;
      }
    }
    final dates = slot.options
        .map((o) => o.parsedDateTime)
        .whereType<DateTime>()
        .toList()
      ..sort();
    final start = date ??
        (preferred
            ? minimum
            : dates.isEmpty
                ? DateTime.now()
                : dates.first);
    month = DateTime(start.year, start.month);
    if (widget.readOnly) {
      option = slot.acceptedSlot;
      date = option?.parsedDateTime;
      step = 2;
    } else if (preferred && preferences.length == slot.selectionSlotCount) {
      step = 2;
    }
  }

  void _saveDraft() =>
      widget.onDraft?.call(option?.index, List.of(preferences), note.text);

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  bool get _hasCalendarDays =>
      preferred || slot.options.any((o) => o.parsedDateTime != null);
  bool _available(DateTime day) => preferred
      ? !day.isBefore(DateTime(minimum.year, minimum.month, minimum.day))
      : slot.options.any(
          (o) => o.parsedDateTime != null && _sameDay(day, o.parsedDateTime!));
  String _dateLabel(DateTime d) => DateFormat('EEE, d MMMM yyyy').format(d);
  String _timeLabel(DateTime d) => DateFormat('h:mm a').format(d);

  bool get _canContinue {
    if (saving) return false;
    if (step == 0) {
      if (!_hasCalendarDays && !preferred) return option != null;
      return date != null;
    }
    if (step == 1) {
      if (preferred) {
        return slot.usesPredefinedTimes ? time != null : customTime != null;
      }
      return option != null;
    }
    return true;
  }

  void _continue() {
    _saveDraft();
    setState(() => error = null);
    if (step == 0) {
      if (!_hasCalendarDays && !preferred && option != null) {
        setState(() => step = 2);
        return;
      }
      if (date != null) setState(() => step = 1);
      return;
    }
    if (step == 1) {
      if (!preferred) {
        if (option != null) setState(() => step = 2);
        return;
      }
      if (date == null ||
          (slot.usesPredefinedTimes ? time == null : customTime == null))
        return;
      final at = slot.usesPredefinedTimes
          ? parseHomeSlotDateTime(
                  '${DateFormat('yyyy-MM-dd').format(date!)} ${time!.time}') ??
              DateTime(date!.year, date!.month, date!.day)
          : DateTime(date!.year, date!.month, date!.day, customTime!.hour,
              customTime!.minute);
      if (slot.minNoticeHours > 0 && at.isBefore(minimum)) {
        setState(() => error =
            'Choose a time at least ${slot.minNoticeHours} hours away.');
        return;
      }
      if (preferences
          .any((p) => p.dateTime == at && p.timeOption?.label == time?.label)) {
        setState(() => error = 'This date and time is already selected.');
        return;
      }
      setState(() {
        preferences.add(VisitPreference(at, time));
        _saveDraft();
        if (preferences.length < slot.selectionSlotCount) {
          step = 0;
          date = null;
          time = null;
          customTime = null;
        } else {
          step = 2;
        }
      });
      return;
    }
    _submit();
  }

  Future<void> _submit() async {
    if (saving) return;
    if (slot.requireNote && note.text.trim().isEmpty) {
      setState(() => error = 'A comment is required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSubmit(
          option?.index, List.of(preferences), note.text.trim());
      if (mounted)
        setState(() {
          saving = false;
          success = true;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: visitsTheme(),
      child: PopScope(
        canPop: !saving && (!success),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && success) Navigator.of(context).pop(true);
        },
        child: Scaffold(
            body: SafeArea(
                child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 20, 6),
              child: Row(children: [
                IconButton(
                    onPressed: saving
                        ? null
                        : () {
                            if (success) {
                              Navigator.of(context).pop(true);
                            } else if (step > 0 && !widget.readOnly) {
                              setState(() => step--);
                            } else {
                              Navigator.of(context).pop(false);
                            }
                          },
                    icon: Icon(success ? Icons.close : Icons.arrow_back)),
                Expanded(
                    child: success || widget.readOnly
                        ? Text(widget.readOnly ? slot.title : '',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700))
                        : Column(children: [
                            Text('Step ${step + 1} of 3',
                                style: const TextStyle(
                                    color: visitMuted, fontSize: 12)),
                            const SizedBox(height: 10),
                            Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < 3; i++) ...[
                                    if (i > 0)
                                      Container(
                                          width: 48,
                                          height: 2,
                                          color: i <= step
                                              ? visitPurple
                                              : const Color(0xFF373A44)),
                                    Container(
                                        width: 18,
                                        height: 18,
                                        decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: i <= step
                                                ? visitPurple
                                                : visitBg,
                                            border: Border.all(
                                                color: i <= step
                                                    ? visitPurple
                                                    : const Color(0xFF444852),
                                                width: 2))),
                                  ]
                                ]),
                          ])),
                const SizedBox(width: 40),
              ])),
          Expanded(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: success
                      ? _success()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Text(
                                  widget.readOnly
                                      ? 'Visit details'
                                      : [
                                          'Select a date',
                                          'Select a time',
                                          'Confirm your slot'
                                        ][step],
                                  style: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              Text(
                                  widget.readOnly
                                      ? (slot.presenceLabel.trim().isEmpty
                                          ? 'Saved visit details'
                                          : slot.presenceLabel.trim())
                                      : step == 0
                                          ? 'Choose a preferred date for the ${slot.title}.'
                                          : step == 1
                                              ? '${_slotCountLabel()}.'
                                              : 'Review your selection and confirm the visit.',
                                  style: const TextStyle(
                                      color: visitMuted,
                                      fontSize: 16,
                                      height: 1.5)),
                              if (preferred)
                                Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                        '${preferences.length} of ${slot.selectionSlotCount} preferred times selected',
                                        style: const TextStyle(
                                            color: visitPurple))),
                              const SizedBox(height: 20),
                              _visitHeader(),
                              if (slot.virtualConnectionDetails.trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _panel(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      const Text('Meeting details',
                                          style: TextStyle(
                                              color: visitMuted,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 6),
                                      Text(slot.virtualConnectionDetails.trim(),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              height: 1.4)),
                                    ])),
                              ],
                              const SizedBox(height: 20),
                              if (step == 0) ...[
                                const Text('Available dates',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 10),
                                _calendar(),
                                if (!_hasCalendarDays && !preferred) ...[
                                  const SizedBox(height: 18),
                                  const Text('Available time slots',
                                      style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 12),
                                  ..._timeChoices(null),
                                ],
                                if (date != null) ...[
                                  const SizedBox(height: 20),
                                  const Text('Selected date',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 10),
                                  _panel(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        VisitDetail(
                                            icon: Icons.calendar_today_outlined,
                                            text: _dateLabel(date!),
                                            emphasize: true,
                                            onChange: widget.readOnly
                                                ? null
                                                : () => setState(() {
                                                      date = null;
                                                      option = null;
                                                      time = null;
                                                      customTime = null;
                                                    })),
                                        const SizedBox(height: 8),
                                        const Text('Slots available',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 4),
                                        const Text(
                                            'Next, choose a time for this date.',
                                            style: TextStyle(
                                                color: visitMuted,
                                                fontSize: 13)),
                                      ]))
                                ],
                              ],
                              if (step == 1) ...[
                                if (date != null)
                                  _panel(
                                      child: VisitDetail(
                                          icon: Icons.calendar_today_outlined,
                                          text: _dateLabel(date!),
                                          onChange: () =>
                                              setState(() => step = 0))),
                                const SizedBox(height: 18),
                                const Text('Available time slots',
                                    style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 12),
                                ..._timeChoices(date),
                                if (slot.allowNote || slot.requireNote) ...[
                                  const SizedBox(height: 8),
                                  _noteBox(),
                                ],
                              ],
                              if (step == 2 && widget.readOnly && option == null && preferences.isEmpty)
                                _panel(
                                    child: Text(
                                        slot.isSubmitted
                                            ? 'Preferred times have been submitted.'
                                            : visitIsCompleted(slot)
                                                ? 'This visit is completed.'
                                                : 'This visit does not have a slot to change.',
                                        style: const TextStyle(
                                            color: visitMuted, height: 1.4))),
                              if (step == 2) ...[
                                if (!preferred && option != null)
                                  _panel(
                                      child: Column(children: [
                                    VisitDetail(
                                        icon: Icons.calendar_today_outlined,
                                        label: 'Date',
                                        emphasize: true,
                                        text: option!.parsedDateTime != null
                                            ? _dateLabel(
                                                option!.parsedDateTime!)
                                            : option!.display,
                                        onChange: widget.readOnly
                                            ? null
                                            : () => setState(() => step = 0)),
                                    const Divider(height: 30),
                                    VisitDetail(
                                        icon: Icons.schedule,
                                        label: 'Time',
                                        emphasize: true,
                                        text: _confirmTimeText(option!),
                                        onChange: widget.readOnly
                                            ? null
                                            : () => setState(() => step = 1)),
                                  ])),
                                if (preferred)
                                  for (var i = 0; i < preferences.length; i++)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: _panel(
                                            child: VisitDetail(
                                                icon: Icons.schedule,
                                                text:
                                                    '${_dateLabel(preferences[i].dateTime)} · ${preferences[i].timeOption?.label ?? _timeLabel(preferences[i].dateTime)}',
                                                onChange: () => setState(() {
                                                      final p = preferences
                                                          .removeAt(i);
                                                      date = p.dateTime;
                                                      time = p.timeOption;
                                                      customTime = TimeOfDay
                                                          .fromDateTime(
                                                              p.dateTime);
                                                      step = 0;
                                                    })))),
                                if (slot.allowNote || slot.requireNote) ...[
                                  const SizedBox(height: 20),
                                  if (widget.readOnly ||
                                      note.text.trim().isNotEmpty)
                                    _panel(
                                        child: VisitDetail(
                                            icon: Icons.chat_bubble_outline,
                                            label: 'Comment',
                                            emphasize: true,
                                            text: note.text.trim().isEmpty
                                                ? 'No additional comments'
                                                : note.text.trim(),
                                            onChange: widget.readOnly
                                                ? null
                                                : () =>
                                                    setState(() => step = 1)))
                                  else
                                    _noteBox(),
                                ],
                              ],
                              if (error != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Text(error!,
                                        style: const TextStyle(
                                            color: Color(0xFFFFB4AB)))),
                            ]))),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: success
                  ? Column(children: [
                      FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Done')),
                      const SizedBox(height: 10),
                      OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 46),
                              side: const BorderSide(color: visitPurple),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          child: const Text('View all visits')),
                    ])
                  : FilledButton(
                      onPressed: widget.readOnly
                          ? () => Navigator.of(context).pop(false)
                          : _canContinue
                              ? _continue
                              : null,
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                  Expanded(
                                      child: Text(
                                          widget.readOnly
                                              ? 'Done'
                                              : step == 2
                                                  ? preferred
                                                      ? 'Submit preferred slots'
                                                      : 'Confirm slot'
                                                  : 'Continue',
                                          textAlign: TextAlign.center)),
                                  if (!widget.readOnly)
                                    const Icon(Icons.chevron_right)
                                ]))),
        ]))),
      ));

  String _optionTimeTitle(SalesSopSlotOption o) {
    if (o.timeLabel.trim().isNotEmpty) return o.timeLabel.trim();
    if (o.parsedDateTime != null) return _timeLabel(o.parsedDateTime!);
    return o.display;
  }

  String _periodFor(DateTime? dt, String label) {
    final match = RegExp(r'\b(morning|afternoon|evening)\b', caseSensitive: false)
        .firstMatch(label);
    final hasClock = RegExp(r'\d').hasMatch(label);
    if (match != null && !hasClock) {
      final word = match.group(1)!;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }
    if (dt != null) {
      if (dt.hour < 11) return 'Morning';
      if (dt.hour < 16) return 'Afternoon';
      return 'Evening';
    }
    if (match != null) {
      final word = match.group(1)!;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }
    return 'Available';
  }

  String _periodSubtitle(String title, String label, DateTime? dt) {
    final period = _periodFor(dt, label.isNotEmpty ? label : title);
    if (period.isEmpty || period.toLowerCase() == title.trim().toLowerCase()) {
      return '';
    }
    return period;
  }

  String _confirmTimeText(SalesSopSlotOption o) {
    final title = _optionTimeTitle(o);
    final period = _periodSubtitle(title, o.timeLabel, o.parsedDateTime);
    if (period.isEmpty) return title;
    return '$title ($period)';
  }

  String _slotCountLabel() {
    final count = preferred && slot.usesPredefinedTimes
        ? slot.timeOptions.length
        : preferred
            ? 1
            : _timesForSelectedDay().length;
    final when = date == null ? '' : ' on ${DateFormat('EEE, d MMM yyyy').format(date!)}';
    return '$count time slot${count == 1 ? '' : 's'} available$when';
  }

  List<SalesSopSlotOption> _timesForSelectedDay() {
    return slot.options
        .where((o) =>
            date == null ||
            o.parsedDateTime == null ||
            _sameDay(date!, o.parsedDateTime!))
        .toList();
  }

  List<Widget> _timeChoices(DateTime? day) {
    if (preferred && slot.usesPredefinedTimes) {
      return [
        for (final item in slot.timeOptions)
          _timeCard(
            title: _clockTitle(item.time.isEmpty ? item.label : item.time),
            subtitle: _rangeSubtitle(item.time.isEmpty ? item.label : item.time),
            period: _periodFor(
                null, item.label.isNotEmpty ? item.label : item.time),
            selected: time == item,
            onTap: () => setState(() => time = item),
          ),
      ];
    }
    if (preferred && !slot.usesPredefinedTimes) {
      return [
        _timeCard(
          title: customTime?.format(context) ?? 'Choose a time',
          subtitle: 'Preferred visit time',
          period: customTime == null
              ? ''
              : _periodFor(
                  DateTime(0, 1, 1, customTime!.hour, customTime!.minute), ''),
          selected: customTime != null,
          onTap: () async {
            final value = await showTimePicker(
                context: context,
                initialTime: customTime ?? const TimeOfDay(hour: 10, minute: 0),
                builder: (context, child) =>
                    Theme(data: visitsTheme(), child: child!));
            if (value != null && mounted) setState(() => customTime = value);
          },
        ),
      ];
    }
    final options = slot.options.where((o) =>
        day == null ||
        o.parsedDateTime == null ||
        _sameDay(day, o.parsedDateTime!));
    return [
      for (final o in options)
        _timeCard(
          title: _clockTitle(_optionTimeTitle(o)),
          subtitle: _rangeSubtitle(
              o.timeLabel.trim().isNotEmpty ? o.timeLabel : _optionTimeTitle(o)),
          period: _periodFor(o.parsedDateTime, o.timeLabel),
          selected: option == o,
          onTap: () => setState(() => option = o),
        ),
    ];
  }

  String _clockTitle(String raw) {
    final text = raw.trim();
    final match = RegExp(r'\d{1,2}:\d{2}\s*(?:AM|PM)', caseSensitive: false)
        .firstMatch(text);
    if (match != null) return match.group(0)!.toUpperCase().replaceAll('  ', ' ');
    return text;
  }

  String _rangeSubtitle(String raw) {
    final text = raw.trim();
    if (!text.contains(RegExp(r'[–\-]| to ', caseSensitive: false))) return '';
    final clocks = RegExp(r'\d{1,2}:\d{2}\s*(?:AM|PM)', caseSensitive: false)
        .allMatches(text)
        .map((m) => m.group(0)!.replaceAll(RegExp(r'\s+'), ' ').toUpperCase())
        .toList();
    if (clocks.length >= 2) return '${clocks.first} – ${clocks[1]}';
    return text;
  }

  String _bookedWhen() {
    if (option == null) return '';
    final when = option!.parsedDateTime != null
        ? _dateLabel(option!.parsedDateTime!)
        : option!.display;
    final time = _confirmTimeText(option!);
    if (time.isEmpty || time == when) return when;
    return '$when · $time';
  }

  Widget _noteBox() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(slot.requireNote
                ? 'Add a comment (required)'
                : 'Add a comment (optional)'),
            const SizedBox(height: 10),
            TextField(
                controller: note,
                onChanged: (_) {
                  if (error != null) setState(() => error = null);
                },
                maxLines: 4,
                maxLength: 200,
                decoration: InputDecoration(
                    hintText:
                        'e.g. Prefer access from gate 2, anything the engineer should know?',
                    hintStyle:
                        const TextStyle(color: visitMuted, height: 1.5),
                    counterStyle: const TextStyle(color: visitMuted),
                    filled: true,
                    fillColor: visitCard,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: Color(0xFF303440))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: Color(0xFF303440))))),
          ]);

  Widget _panel({required Widget child}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: visitDecoration(),
      child: child);
  Widget _visitHeader() => _panel(
          child: Row(children: [
        VisitIcon(slot: slot),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(slot.title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
              [
                slot.presenceLabel,
                if (slot.submittedBy.isNotEmpty) 'Given by ${slot.submittedBy}'
              ].where((s) => s.isNotEmpty).join(' · '),
              style: const TextStyle(color: visitMuted, fontSize: 13)),
        ]))
      ]));
  Widget _timeCard({
    required String title,
    required String subtitle,
    required String period,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  decoration: visitDecoration(
                      color: selected ? const Color(0xFF252036) : visitCard,
                      border: selected ? visitPurple : null),
                  child: Row(children: [
                    Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected ? visitPurple : visitMuted),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          if (subtitle.trim().isNotEmpty &&
                              subtitle.trim().toLowerCase() !=
                                  title.trim().toLowerCase()) ...[
                            const SizedBox(height: 4),
                            Text(subtitle,
                                style: const TextStyle(
                                    color: visitMuted, fontSize: 13)),
                          ]
                        ])),
                    if (period.trim().isNotEmpty &&
                        period.trim().toLowerCase() != title.trim().toLowerCase())
                      Text(period,
                          style: const TextStyle(
                              color: visitMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                  ]))));
  Widget _calendar() {
    final first = DateTime(month.year, month.month);
    final offset = first.weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    return _panel(
        child: Column(children: [
      Row(children: [
        Expanded(
            child: Text(DateFormat('MMMM yyyy').format(month),
                style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
            onPressed: () =>
                setState(() => month = DateTime(month.year, month.month - 1)),
            icon: const Icon(Icons.chevron_left)),
        IconButton(
            onPressed: () =>
                setState(() => month = DateTime(month.year, month.month + 1)),
            icon: const Icon(Icons.chevron_right))
      ]),
      Row(children: [
        for (final day in ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'])
          Expanded(
              child: Center(
                  child: Text(day,
                      style: const TextStyle(color: visitMuted, fontSize: 11))))
      ]),
      const SizedBox(height: 12),
      GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ((days + offset + 6) ~/ 7) * 7,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, crossAxisSpacing: 4, mainAxisSpacing: 5),
          itemBuilder: (context, index) {
            final number = index - offset + 1;
            if (number < 1 || number > days) return const SizedBox();
            final day = DateTime(month.year, month.month, number);
            final enabled = _available(day);
            final selected = date != null && _sameDay(date!, day);
            return InkWell(
                onTap: enabled
                    ? () => setState(() {
                          date = day;
                          option = null;
                          time = null;
                          customTime = null;
                        })
                    : null,
                child: Container(
                    decoration: BoxDecoration(
                        color: selected
                            ? visitPurple
                            : enabled
                                ? const Color(0xFF24352C)
                                : const Color(0xFF20242B),
                        borderRadius: BorderRadius.circular(9),
                        border: enabled && !selected
                            ? Border.all(
                                color: visitGreen.withValues(alpha: .45))
                            : null),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('$number',
                              style: TextStyle(
                                  color: enabled
                                      ? Colors.white
                                      : const Color(0xFF646977),
                                  fontSize: 13)),
                          if (enabled)
                            Container(
                                margin: const EdgeInsets.only(top: 3),
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        selected ? Colors.black : visitGreen))
                        ])));
          }),
    ]));
  }

  Widget _success() => Column(children: [
        const SizedBox(height: 28),
        const _VisitConfirmedMark(),
        const SizedBox(height: 20),
        Text(preferred ? 'Preferred slots submitted' : 'Visit slot confirmed',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(
            preferred
                ? 'Your preferred times have been sent to the team for confirmation.'
                : _bookedWhen().isEmpty
                    ? 'Your ${slot.title} is scheduled. You will receive a confirmation shortly.'
                    : 'Your ${slot.title} is scheduled for ${_bookedWhen()}.',
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: visitMuted, fontSize: 16, height: 1.5)),
        const SizedBox(height: 28),
        _visitHeader(),
        if (!preferred && option != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _panel(
                  child: Column(children: [
                VisitDetail(
                    icon: Icons.calendar_today_outlined,
                    emphasize: true,
                    text: option!.parsedDateTime != null
                        ? _dateLabel(option!.parsedDateTime!)
                        : option!.display),
                const Divider(height: 24),
                VisitDetail(
                    icon: Icons.schedule,
                    emphasize: true,
                    text: _confirmTimeText(option!)),
              ]))),
      ]);
}

class _VisitConfirmedMark extends StatefulWidget {
  const _VisitConfirmedMark();
  @override
  State<_VisitConfirmedMark> createState() => _VisitConfirmedMarkState();
}

class _Sprinkle {
  final Color color;
  final double size;
  final double turn;
  final double? top;
  final double? left;
  final double? right;
  final double? bottom;
  const _Sprinkle({
    required this.color,
    required this.size,
    required this.turn,
    this.top,
    this.left,
    this.right,
    this.bottom,
  });
}

class _VisitConfirmedMarkState extends State<_VisitConfirmedMark>
    with TickerProviderStateMixin {
  late final AnimationController _circle;
  late final AnimationController _burst;

  static const _bits = <_Sprinkle>[
    _Sprinkle(color: visitPurple, size: 8, turn: .4, top: 18, left: 46),
    _Sprinkle(color: visitGreen, size: 10, turn: -.2, top: 36, right: 58),
    _Sprinkle(
        color: Color(0xFFF5AF37), size: 7, turn: .8, bottom: 28, left: 72),
    _Sprinkle(color: visitPurple, size: 6, turn: 1.1, top: 12, right: 108),
    _Sprinkle(color: visitGreen, size: 8, turn: .15, bottom: 22, right: 78),
    _Sprinkle(
        color: Color(0xFFF5AF37), size: 5, turn: -.6, top: 64, left: 28),
  ];

  @override
  void initState() {
    super.initState();
    _circle = AnimationController(vsync: this, lowerBound: 0, upperBound: 2);
    _burst = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 880));
    _circle.animateWith(SpringSimulation(
        SpringDescription.withDurationAndBounce(
            duration: const Duration(milliseconds: 380), bounce: .22),
        0,
        1,
        0));
    _burst.forward();
  }

  @override
  void dispose() {
    _circle.dispose();
    _burst.dispose();
    super.dispose();
  }

  double _draw(double t) {
    final u = ((t - .28) / .4).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(u);
  }

  double _fly(double t, int i) {
    final u = ((t - .04 - i * .018) / .6).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(u);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 168,
        width: double.infinity,
        child: AnimatedBuilder(
            animation: Listenable.merge([_circle, _burst]),
            builder: (context, _) {
              final t = _burst.value;
              final draw = _draw(t);
              return LayoutBuilder(builder: (context, box) {
                final cx = box.maxWidth / 2;
                final cy = box.maxHeight / 2;
                return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                  for (var i = 0; i < _bits.length; i++)
                    _piece(box, cx, cy, _bits[i], _fly(t, i)),
                  Transform.scale(
                      scale: _circle.value.clamp(0.0, 1.45),
                      child: Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: visitGreen.withValues(alpha: .12)),
                          child: Center(
                              child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: const BoxDecoration(
                                      shape: BoxShape.circle, color: visitGreen),
                                  child: Opacity(
                                      opacity: draw,
                                      child: Transform.scale(
                                          scale: .72 + .28 * draw,
                                          child: const Icon(Icons.check_rounded,
                                              size: 44,
                                              color: Color(0xFF09583A)))))))),
                ]);
              });
            }));
  }

  Widget _piece(BoxConstraints box, double cx, double cy, _Sprinkle s, double b) {
    final w = s.size;
    final h = s.size * 1.8;
    final x = s.left ?? (box.maxWidth - (s.right ?? 0) - w);
    final y = s.top ?? (box.maxHeight - (s.bottom ?? 0) - h);
    final end = Offset(x + w / 2 - cx, y + h / 2 - cy);
    final travel = b < 0 ? 0.0 : b;
    final settled = travel.clamp(0.0, 1.0);
    return Transform.translate(
        offset: end * travel,
        child: Opacity(
            opacity: (travel * 2.6).clamp(0.0, 1.0),
            child: Transform.rotate(
                angle: s.turn + 1.35 * (1 - settled),
                child: Transform.scale(
                    scale: (.35 + .65 * travel).clamp(0.0, 1.2),
                    child: _ConfettiMark(color: s.color, size: s.size)))));
  }
}

class _ConfettiMark extends StatelessWidget {
  final Color color;
  final double size;
  const _ConfettiMark({required this.color, required this.size});
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size * 1.8,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)));
}
