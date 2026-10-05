import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sales_sop_slot.dart';

const visitPurple = Color(0xFF9670FF);
const visitGreen = Color(0xFF99F5C5);
const visitBg = Color(0xFF0D1013);
const visitCard = Color(0xFF191C22);
const visitMuted = Color(0xFFB0B5C2);
ThemeData visitsTheme() => ThemeData.dark().copyWith(
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Mulish-Regular'),
      scaffoldBackgroundColor: visitBg,
      colorScheme: const ColorScheme.dark(
          primary: visitPurple, secondary: visitGreen, surface: visitCard),
      appBarTheme: const AppBarTheme(
          backgroundColor: visitBg, foregroundColor: Colors.white),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: visitPurple,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                  fontFamily: 'Mulish-Regular',
                  fontSize: 16,
                  fontWeight: FontWeight.w700))),
    );
BoxDecoration visitDecoration({Color color = visitCard, Color? border}) =>
    BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border ?? const Color(0xFF2A2D35)));

bool visitIsCompleted(SalesSopSlot s) =>
    const {'completed', 'done', 'finished'}.contains(s.statusKey);

class SiteVisitsOverview extends StatefulWidget {
  final List<SalesSopSlot> slots;
  final Future<void> Function() onRefresh;
  final ValueChanged<SalesSopSlot> onOpen;
  final VoidCallback onDetails;
  final VoidCallback onHelp;
  final bool showInlineTitle;
  final bool loading;
  final String? error;
  const SiteVisitsOverview(
      {super.key,
      required this.slots,
      required this.onRefresh,
      required this.onOpen,
      required this.onDetails,
      required this.onHelp,
      this.showInlineTitle = true,
      this.loading = false,
      this.error});
  @override
  State<SiteVisitsOverview> createState() => _OverviewState();
}

class _OverviewState extends State<SiteVisitsOverview> {
  int filter = 0;
  @override
  Widget build(BuildContext context) {
    final slots = widget.slots;
    final completed = slots.where(visitIsCompleted).length;
    final accepted = slots.where((s) => s.isAccepted).length;
    final pending =
        slots.where((s) => !s.isAccepted && !visitIsCompleted(s)).length;
    final visible = slots.where((s) =>
        filter == 0 ||
        (filter == 1 ? !visitIsCompleted(s) : visitIsCompleted(s)));
    return Theme(
        data: visitsTheme(),
        child: ColoredBox(
            color: visitBg,
            child: RefreshIndicator(
                color: visitPurple,
                onRefresh: widget.onRefresh,
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                widget.showInlineTitle ? 'Site visits' : '',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 25,
                                    fontWeight: FontWeight.w700))),
                        TextButton.icon(
                            onPressed: widget.onHelp,
                            icon: const Icon(Icons.event_available_outlined,
                                size: 16),
                            label: const Text('How it works'),
                            style: TextButton.styleFrom(
                                foregroundColor: visitPurple,
                                backgroundColor:
                                    visitPurple.withValues(alpha: .12)))
                      ]),
                      const SizedBox(height: 8),
                      const Text('Track and confirm your upcoming site visits.',
                          style: TextStyle(
                              color: visitMuted, fontSize: 16, height: 1.5)),
                      const SizedBox(height: 20),
                      Container(
                          padding: const EdgeInsets.all(18),
                          decoration: visitDecoration(),
                          child: Row(children: [
                            SizedBox(
                                width: 72,
                                height: 72,
                                child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox.expand(
                                          child: CircularProgressIndicator(
                                              value: slots.isEmpty
                                                  ? 0
                                                  : (accepted + completed) /
                                                      slots.length,
                                              strokeWidth: 7,
                                              color: visitGreen,
                                              backgroundColor:
                                                  const Color(0xFF303440))),
                                      Text(
                                          '${accepted + completed}/${slots.length}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600)),
                                    ])),
                            const SizedBox(width: 18),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text('$accepted confirmed · $pending pending',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 7),
                                  Text(
                                      '${slots.length - completed} upcoming · $completed completed',
                                      style: const TextStyle(
                                          color: visitMuted, fontSize: 13)),
                                ])),
                          ])),
                      const SizedBox(height: 20),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final entry in [
                          MapEntry(0, 'All (${slots.length})'),
                          MapEntry(1, 'Upcoming (${slots.length - completed})'),
                          MapEntry(2, 'Completed ($completed)')
                        ])
                          ChoiceChip(
                              label: Text(entry.value,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: filter == entry.key
                                          ? Colors.white
                                          : visitMuted)),
                              selected: filter == entry.key,
                              onSelected: (_) =>
                                  setState(() => filter = entry.key),
                              showCheckmark: false,
                              selectedColor: visitPurple,
                              backgroundColor: visitCard,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24)))
                      ]),
                      const SizedBox(height: 12),
                      if (widget.loading)
                        const LinearProgressIndicator(color: visitPurple),
                      if (widget.error != null)
                        Text(widget.error!,
                            style: const TextStyle(color: Color(0xFFFFB4AB))),
                      if (visible.isEmpty && !widget.loading)
                        const Padding(
                            padding: EdgeInsets.all(32),
                            child: Text('No visits to show.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: visitMuted))),
                      for (final slot in visible)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                    onTap: () => widget.onOpen(slot),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                        padding: const EdgeInsets.all(15),
                                        decoration: visitDecoration(
                                            color: slot.isAccepted
                                                ? const Color(0xFF0C2924)
                                                : visitCard),
                                        child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (!slot.isAccepted &&
                                                  !visitIsCompleted(slot) &&
                                                  !slot.isSubmitted)
                                                Container(
                                                    width: 3,
                                                    height: 52,
                                                    margin: const EdgeInsets.only(
                                                        right: 12),
                                                    decoration: BoxDecoration(
                                                        color: const Color(
                                                            0xFFF5AF37),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4))),
                                              VisitIcon(slot: slot),
                                              const SizedBox(width: 13),
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    Text(slot.title,
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)),
                                                    const SizedBox(height: 8),
                                                    VisitDetail(
                                                        icon: Icons
                                                            .calendar_today_outlined,
                                                        text: slot.acceptedSlot
                                                                    ?.parsedDateTime !=
                                                                null
                                                            ? DateFormat(
                                                                    'EEE, d MMM yyyy')
                                                                .format(slot
                                                                    .acceptedSlot!
                                                                    .parsedDateTime!)
                                                            : slot
                                                                    .needsSelection
                                                                ? 'Choose a date and time'
                                                                : slot.acceptedSlot
                                                                        ?.display ??
                                                                    (slot.isSubmitted
                                                                        ? 'Preferred times submitted'
                                                                        : '${slot.options.length} available slots')),
                                                    if (slot.acceptedSlot
                                                            ?.parsedDateTime !=
                                                        null) ...[
                                                      const SizedBox(height: 6),
                                                      VisitDetail(
                                                          icon: Icons.schedule,
                                                          text: slot
                                                                  .acceptedSlot!
                                                                  .timeLabel
                                                                  .isNotEmpty
                                                              ? slot
                                                                  .acceptedSlot!
                                                                  .timeLabel
                                                              : DateFormat(
                                                                      'h:mm a')
                                                                  .format(slot
                                                                      .acceptedSlot!
                                                                      .parsedDateTime!))
                                                    ],
                                                  ])),
                                              const SizedBox(width: 6),
                                              _status(slot),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.chevron_right,
                                                  color: visitMuted, size: 16),
                                            ]))))),
                    ]))));
  }

  Widget _status(SalesSopSlot s) {
    final color = s.isAccepted || visitIsCompleted(s)
        ? visitGreen
        : const Color(0xFFF5AF37);
    final label = visitIsCompleted(s)
        ? 'Completed'
        : s.isAccepted
            ? 'Accepted'
            : s.isSubmitted
                ? 'Submitted'
                : 'Awaiting';
    final icon = visitIsCompleted(s) || s.isAccepted
        ? Icons.check_rounded
        : s.isSubmitted
            ? Icons.schedule
            : Icons.hourglass_top_rounded;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .15),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]));
  }
}

class VisitIcon extends StatelessWidget {
  final SalesSopSlot slot;
  const VisitIcon({super.key, required this.slot});
  @override
  Widget build(BuildContext context) {
    final done = slot.isAccepted || visitIsCompleted(slot);
    final color = done ? visitGreen : visitPurple;
    return Container(
        width: 46,
        height: 48,
        decoration: BoxDecoration(
            color: color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(
            done ? Icons.apartment_rounded : Icons.event_available_outlined,
            color: color));
  }
}

class VisitDetail extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? label;
  final VoidCallback? onChange;
  final bool emphasize;
  const VisitDetail(
      {super.key,
      required this.icon,
      required this.text,
      this.label,
      this.onChange,
      this.emphasize = false});
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: visitMuted, size: 19),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (label != null)
                  Text(label!,
                      style: const TextStyle(color: visitMuted, fontSize: 12)),
                Text(text,
                    style: TextStyle(
                        color: emphasize ? Colors.white : visitMuted,
                        fontSize: emphasize ? 15 : 13,
                        fontWeight:
                            emphasize ? FontWeight.w600 : FontWeight.w500,
                        height: 1.35)),
              ])),
          if (onChange != null)
            TextButton(
                onPressed: onChange,
                child:
                    const Text('Change', style: TextStyle(color: visitPurple)))
        ],
      );
}
