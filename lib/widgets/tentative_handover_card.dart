import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';

/// Tentative handover from remaining construction days, with a live countdown.
///
/// Pass [progress] to render the merged dashboard section (days left + bar +
/// counter + pulsing Live badge). Without [progress], renders the compact card.
class TentativeHandoverCard extends StatefulWidget {
  final int remainingDays;
  final EdgeInsetsGeometry? margin;
  final bool compact;

  /// 0–1 project completion. When set, shows the merged progress section.
  final double? progress;
  final String? percentLabel;
  final String? delayLabel;
  final String? plannedLabel;
  final Widget? trailingAction;
  final VoidCallback? onTap;

  const TentativeHandoverCard({
    super.key,
    required this.remainingDays,
    this.margin,
    this.compact = false,
    this.progress,
    this.percentLabel,
    this.delayLabel,
    this.plannedLabel,
    this.trailingAction,
    this.onTap,
  });

  /// Calendar date for tentative handover (local midnight of that day).
  static DateTime handoverDateFromRemaining(int remainingDays) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = remainingDays < 0 ? 0 : remainingDays;
    return today.add(Duration(days: days));
  }

  @override
  State<TentativeHandoverCard> createState() => _TentativeHandoverCardState();
}

class _TentativeHandoverCardState extends State<TentativeHandoverCard> {
  Timer? _timer;
  late DateTime _target;
  Duration _remaining = Duration.zero;

  bool get _merged => widget.progress != null;

  @override
  void initState() {
    super.initState();
    _reanchorTarget();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant TentativeHandoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remainingDays != widget.remainingDays) {
      _reanchorTarget();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reanchorTarget() {
    // Anchor from "now" so the counter opens at exactly N days and ticks live.
    final days = widget.remainingDays < 0 ? 0 : widget.remainingDays;
    _target = DateTime.now().add(Duration(days: days));
    _remaining = _target.difference(DateTime.now());
    if (_remaining.isNegative) _remaining = Duration.zero;
  }

  void _tick() {
    if (!mounted) return;
    final next = _target.difference(DateTime.now());
    setState(() {
      _remaining = next.isNegative ? Duration.zero : next;
    });
  }

  String get _dateLabel {
    final date =
        TentativeHandoverCard.handoverDateFromRemaining(widget.remainingDays);
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _dayWord(num count) => count == 1 ? 'day' : 'days';

  @override
  Widget build(BuildContext context) {
    final totalSeconds = _remaining.inSeconds;
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final dueNow = totalSeconds <= 0;

    final child = _merged
        ? _buildMergedSection(
            days: days,
            hours: hours,
            minutes: minutes,
            seconds: seconds,
            dueNow: dueNow,
          )
        : _buildCompactCard(
            days: days,
            hours: hours,
            minutes: minutes,
            seconds: seconds,
            dueNow: dueNow,
          );

    if (widget.onTap == null) return child;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }

  Widget _buildMergedSection({
    required int days,
    required int hours,
    required int minutes,
    required int seconds,
    required bool dueNow,
  }) {
    final progress = (widget.progress ?? 0).clamp(0.0, 1.0).toDouble();
    final remainingLabel = widget.remainingDays;
    final percent = widget.percentLabel;

    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dueNow
                          ? 'Tentative handover - Due now'
                          : 'Tentative handover - $_dateLabel',
                      style: TextStyle(
                        color: AppTheme.darkTextPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<int>(
                      tween: IntTween(begin: 0, end: remainingLabel),
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) {
                        return Text(
                          '$value ${_dayWord(value)} left to completion',
                          style: TextStyle(
                            color: AppTheme.darkTextSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                    if (widget.delayLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.delayLabel!,
                        style: TextStyle(
                          color: AppTheme.darkTextSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (widget.plannedLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.plannedLabel!,
                        style: TextStyle(
                          color: AppTheme.darkTextSecondary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const _LivePulseBadge(),
                  if (widget.trailingAction != null) ...[
                    const SizedBox(height: 8),
                    widget.trailingAction!,
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (percent != null) ...[
                Text(
                  percent,
                  style: TextStyle(
                    color: AppTheme.darkTextPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: const Color(0xFF2A2A2D),
                    color: AppTheme.darkTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (dueNow)
            Text(
              'Your project is ready for handover',
              style: TextStyle(
                color: AppTheme.darkTextSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Row(
              children: [
                Expanded(child: _CounterCell(value: days, label: 'Days')),
                const SizedBox(width: 8),
                Expanded(child: _CounterCell(value: hours, label: 'Hrs')),
                const SizedBox(width: 8),
                Expanded(child: _CounterCell(value: minutes, label: 'Min')),
                const SizedBox(width: 8),
                Expanded(child: _CounterCell(value: seconds, label: 'Sec')),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCompactCard({
    required int days,
    required int hours,
    required int minutes,
    required int seconds,
    required bool dueNow,
  }) {
    return Container(
      margin: widget.margin,
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 12 : 14,
        vertical: widget.compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF14261C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF14532D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: widget.compact ? 36 : 40,
                height: widget.compact ? 36 : 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.event_available_rounded,
                  color: const Color(0xFF34D399),
                  size: widget.compact ? 20 : 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tentative handover',
                      style: TextStyle(
                        color: Color(0xFF86EFAC),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dueNow ? 'Due now' : _dateLabel,
                      style: TextStyle(
                        color: AppTheme.darkTextPrimary,
                        fontSize: widget.compact ? 16 : 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const _LivePulseBadge(),
            ],
          ),
          const SizedBox(height: 12),
          if (dueNow)
            Text(
              'Your project is ready for handover',
              style: TextStyle(
                color: AppTheme.darkTextSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Row(
              children: [
                Expanded(child: _CounterCell(value: days, label: 'Days')),
                const SizedBox(width: 8),
                Expanded(child: _CounterCell(value: hours, label: 'Hrs')),
                const SizedBox(width: 8),
                Expanded(child: _CounterCell(value: minutes, label: 'Min')),
                const SizedBox(width: 8),
                Expanded(child: _CounterCell(value: seconds, label: 'Sec')),
              ],
            ),
        ],
      ),
    );
  }
}

class _LivePulseBadge extends StatefulWidget {
  const _LivePulseBadge();

  @override
  State<_LivePulseBadge> createState() => _LivePulseBadgeState();
}

class _LivePulseBadgeState extends State<_LivePulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        final glow = 0.25 + (0.45 * t);
        final scale = 0.92 + (0.08 * t);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF14261C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Color.lerp(
                const Color(0xFF14532D),
                const Color(0xFF34D399),
                t * 0.55,
              )!,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF34D399).withValues(alpha: glow * 0.35),
                blurRadius: 8 + (4 * t),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      const Color(0xFF059669),
                      const Color(0xFF6EE7B7),
                      t,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFF34D399).withValues(alpha: glow),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'LIVE',
                style: TextStyle(
                  color: Color.lerp(
                    const Color(0xFF86EFAC),
                    const Color(0xFFD1FAE5),
                    t * 0.4,
                  ),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CounterCell extends StatelessWidget {
  final int value;
  final String label;

  const _CounterCell({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1B4332)),
      ),
      child: Column(
        children: [
          Text(
            value.toString().padLeft(2, '0'),
            style: const TextStyle(
              color: Color(0xFF6EE7B7),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.darkTextSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
