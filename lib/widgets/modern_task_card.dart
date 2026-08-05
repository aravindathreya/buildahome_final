import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color kTaskNavy = Color(0xFF1B254B);
const Color kTaskMuted = Color(0xFF8A94A6);
const Color kTaskBorder = Color(0xFFE8ECF1);
const Color kTaskSoftShadow = Color(0x14000000);

class TaskStatusStyle {
  final Color color;
  final Color background;
  final IconData icon;

  const TaskStatusStyle({
    required this.color,
    required this.background,
    required this.icon,
  });
}

TaskStatusStyle taskStatusStyle(String status) {
  switch (status.toLowerCase().replaceAll(' ', '_')) {
    case 'completed':
    case 'done':
    case 'finished':
    case 'skipped':
    case 'approved':
      return const TaskStatusStyle(
        color: Color(0xFF047857),
        background: Color(0xFFECFDF5),
        icon: Icons.check_circle_outline_rounded,
      );
    case 'in_progress':
      return const TaskStatusStyle(
        color: Color(0xFFB45309),
        background: Color(0xFFFFF7ED),
        icon: Icons.timelapse_rounded,
      );
    case 'ready':
      return const TaskStatusStyle(
        color: Color(0xFF2563EB),
        background: Color(0xFFEFF4FF),
        icon: Icons.bolt_rounded,
      );
    case 'waiting_approval':
      return const TaskStatusStyle(
        color: Color(0xFF243463),
        background: Color(0xFFEEF2F7),
        icon: Icons.rate_review_outlined,
      );
    case 'scheduled':
      return const TaskStatusStyle(
        color: Color(0xFF1B254B),
        background: Color(0xFFEEF2F7),
        icon: Icons.schedule_rounded,
      );
    case 'cancelled':
    case 'rejected':
      return const TaskStatusStyle(
        color: Color(0xFFB91C1C),
        background: Color(0xFFFEF2F2),
        icon: Icons.cancel_outlined,
      );
    case 'not_started':
      return const TaskStatusStyle(
        color: Color(0xFF8A94A6),
        background: Color(0xFFF7F8FB),
        icon: Icons.hourglass_empty_rounded,
      );
    default:
      return const TaskStatusStyle(
        color: Color(0xFF243463),
        background: Color(0xFFEEF2F7),
        icon: Icons.pending_actions_outlined,
      );
  }
}

Color taskAccentColor(int index) {
  const accents = [
    Color(0xFFB45309),
    Color(0xFFC2410C),
    Color(0xFF047857),
    Color(0xFF243463),
    Color(0xFFB91C1C),
    Color(0xFF2563EB),
  ];
  return accents[index % accents.length];
}

IconData taskConstructionIcon(int index) {
  const icons = [
    Icons.foundation_rounded,
    Icons.construction_rounded,
    Icons.architecture_rounded,
    Icons.handyman_rounded,
    Icons.home_work_outlined,
    Icons.plumbing_rounded,
    Icons.electrical_services_rounded,
    Icons.square_foot_rounded,
  ];
  return icons[index % icons.length];
}

/// Sentence-cases a UI label: first character upper, remainder lower.
String toSentenceCaseLabel(String value) {
  final cleaned = value.replaceAll('_', ' ').trim();
  if (cleaned.isEmpty) return cleaned;
  final lower = cleaned.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

String formatTaskStatusLabel(String value) => toSentenceCaseLabel(value);

class ModernTaskStatusPill extends StatelessWidget {
  final String status;
  final String? displayLabel;
  final Color? color;
  final Color? background;
  final double maxWidth;

  const ModernTaskStatusPill({
    super.key,
    required this.status,
    this.displayLabel,
    this.color,
    this.background,
    this.maxWidth = 92,
  });

  @override
  Widget build(BuildContext context) {
    final style = taskStatusStyle(status);
    final fg = color ?? style.color;
    final bg = background ?? style.background;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                formatTaskStatusLabel(displayLabel ?? status),
                style: TextStyle(
                  color: fg,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const List<Map<String, dynamic>> kTaskStatusOptions = [
  {
    'value': 'pending',
    'label': 'Pending',
    'color': Color(0xFFB45309),
    'icon': Icons.pending,
  },
  {
    'value': 'in_progress',
    'label': 'In progress',
    'color': Color(0xFF2563EB),
    'icon': Icons.work,
  },
  {
    'value': 'completed',
    'label': 'Completed',
    'color': Color(0xFF047857),
    'icon': Icons.check_circle,
  },
  {
    'value': 'cancelled',
    'label': 'Cancelled',
    'color': Color(0xFFB91C1C),
    'icon': Icons.cancel,
  },
];

class TaskStatusChipSet extends StatelessWidget {
  final String currentStatus;
  final ValueChanged<String>? onStatusSelected;
  final bool enabled;
  /// Optional custom status values (e.g. workflow `allowed_statuses`).
  /// When null, uses [kTaskStatusOptions].
  final List<String>? statuses;

  const TaskStatusChipSet({
    super.key,
    required this.currentStatus,
    this.onStatusSelected,
    this.enabled = true,
    this.statuses,
  });

  List<Map<String, dynamic>> get _options {
    if (statuses == null || statuses!.isEmpty) return kTaskStatusOptions;

    return statuses!.map((raw) {
      final normalized = raw.toLowerCase().replaceAll(' ', '_');
      for (final option in kTaskStatusOptions) {
        if (option['value'] == normalized) {
          return {
            ...option,
            // Keep the API value as provided (may use spaces or underscores).
            'value': raw,
            'label': formatTaskStatusLabel(option['label'] as String),
          };
        }
      }
      final style = taskStatusStyle(normalized);
      return {
        'value': raw,
        'label': formatTaskStatusLabel(raw),
        'color': style.color,
        'icon': style.icon,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final normalized = currentStatus.toLowerCase().replaceAll(' ', '_');
    final options = _options;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((statusData) {
        final value = statusData['value'] as String;
        final label = formatTaskStatusLabel(
          statusData['label'] as String? ?? value,
        );
        final color = statusData['color'] as Color;
        final icon = statusData['icon'] as IconData;
        final selected =
            normalized == value.toLowerCase().replaceAll(' ', '_');

        return FilterChip(
          selected: selected,
          showCheckmark: false,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : color,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : kTaskNavy,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
          selectedColor: color,
          backgroundColor: color.withOpacity(0.08),
          side: BorderSide(
            color: selected ? color : color.withOpacity(0.28),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          onSelected: !enabled
              ? null
              : (_) {
                  if (!selected) {
                    onStatusSelected?.call(value);
                  }
                },
        );
      }).toList(),
    );
  }
}

class ModernTaskCard extends StatelessWidget {
  final String title;
  final String? projectName;
  final String? assigneeName;
  final String? dateLabel;
  final String status;
  final String? statusLabel;
  final int accentIndex;
  final bool isSelected;
  final VoidCallback? onTap;
  final Widget? menu;
  final Widget? footer;
  final EdgeInsetsGeometry margin;
  /// When set, the card can be swiped right to mark complete (swipe-to-pay).
  /// Return `true` if the complete action succeeded.
  final Future<bool> Function()? onSwipeComplete;
  final String swipeCompleteLabel;

  const ModernTaskCard({
    super.key,
    required this.title,
    required this.status,
    this.projectName,
    this.assigneeName,
    this.dateLabel,
    this.statusLabel,
    this.accentIndex = 0,
    this.isSelected = false,
    this.onTap,
    this.menu,
    this.footer,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onSwipeComplete,
    this.swipeCompleteLabel = 'Swipe to complete',
  });

  @override
  Widget build(BuildContext context) {
    final accent = taskAccentColor(accentIndex);
    final style = taskStatusStyle(status);
    final icon = taskConstructionIcon(accentIndex);
    final hasMeta = (assigneeName != null && assigneeName!.trim().isNotEmpty) ||
        (dateLabel != null && dateLabel!.trim().isNotEmpty);

    final card = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF2563EB) : kTaskBorder,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: kTaskSoftShadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: accent),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 4),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          10,
                          12,
                          menu != null ? 4 : 10,
                          12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child:
                                      Icon(icon, color: accent, size: 18),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: const TextStyle(
                                                    color: kTaskNavy,
                                                    fontSize: 13.5,
                                                    fontWeight:
                                                        FontWeight.w800,
                                                    height: 1.25,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                if (isSelected) ...[
                                                  const SizedBox(height: 4),
                                                  const _SelectedTaskBadge(),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          ModernTaskStatusPill(
                                            status: status,
                                            displayLabel: statusLabel,
                                            color: style.color,
                                            background: style.background,
                                          ),
                                        ],
                                      ),
                                      if (projectName != null &&
                                          projectName!
                                              .trim()
                                              .isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          'Project: $projectName',
                                          style: const TextStyle(
                                            color: Color(0xFF2563EB),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      if (hasMeta) ...[
                                        const SizedBox(height: 6),
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            return Wrap(
                                              spacing: 10,
                                              runSpacing: 4,
                                              children: [
                                                if (assigneeName != null &&
                                                    assigneeName!
                                                        .trim()
                                                        .isNotEmpty)
                                                  _MetaChip(
                                                    icon: Icons
                                                        .person_outline_rounded,
                                                    label: assigneeName!,
                                                    maxWidth: constraints
                                                        .maxWidth,
                                                  ),
                                                if (dateLabel != null &&
                                                    dateLabel!
                                                        .trim()
                                                        .isNotEmpty)
                                                  _MetaChip(
                                                    icon: Icons
                                                        .calendar_today_outlined,
                                                    label: dateLabel!,
                                                    maxWidth: constraints
                                                        .maxWidth,
                                                  ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (footer != null) ...[
                              const SizedBox(height: 10),
                              footer!,
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Outside InkWell so the overflow menu stays tappable.
                if (menu != null)
                  Material(
                    color: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 2),
                      child: menu!,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    if (onSwipeComplete == null) {
      return Padding(padding: margin, child: card);
    }

    return Padding(
      padding: margin,
      child: SwipeToComplete(
        onComplete: onSwipeComplete!,
        label: swipeCompleteLabel,
        child: card,
      ),
    );
  }
}

/// Swipe-to-pay style gesture: drag the card right past a threshold to complete.
class SwipeToComplete extends StatefulWidget {
  final Widget child;
  final Future<bool> Function() onComplete;
  final String label;
  final double confirmationFraction;

  const SwipeToComplete({
    super.key,
    required this.child,
    required this.onComplete,
    this.label = 'Swipe to complete',
    this.confirmationFraction = 0.42,
  });

  @override
  State<SwipeToComplete> createState() => _SwipeToCompleteState();
}

class _SwipeToCompleteState extends State<SwipeToComplete>
    with TickerProviderStateMixin {
  static const Color _trackGreen = Color(0xFF047857);
  static const Color _trackGreenSoft = Color(0xFF059669);

  double _dragExtent = 0;
  double _maxExtent = 0;
  bool _armed = false;
  bool _completing = false;
  bool _succeeded = false;

  late final AnimationController _settleController;
  late final AnimationController _successController;
  Animation<double>? _settleAnimation;

  @override
  void initState() {
    super.initState();
    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        final anim = _settleAnimation;
        if (anim == null) return;
        setState(() => _dragExtent = anim.value);
      });

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void dispose() {
    _settleController.dispose();
    _successController.dispose();
    super.dispose();
  }

  double get _progress {
    if (_maxExtent <= 0) return 0;
    return (_dragExtent / _maxExtent).clamp(0.0, 1.0);
  }

  Future<void> _animateTo(double target, {Curve curve = Curves.easeOutCubic}) async {
    _settleAnimation = Tween<double>(begin: _dragExtent, end: target).animate(
      CurvedAnimation(parent: _settleController, curve: curve),
    );
    _settleController
      ..reset()
      ..duration = Duration(
        milliseconds: (220 + (_dragExtent - target).abs() * 0.4).round().clamp(180, 360),
      );
    await _settleController.forward();
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (_completing || _succeeded) return;

    final velocity = details.primaryVelocity ?? 0;
    final shouldComplete = _progress >= widget.confirmationFraction ||
        (velocity > 900 && _progress > 0.18);

    if (!shouldComplete) {
      _armed = false;
      await _animateTo(0);
      return;
    }

    await _confirmComplete();
  }

  Future<void> _confirmComplete() async {
    if (_completing || _succeeded) return;
    setState(() => _completing = true);

    HapticFeedback.mediumImpact();
    await _animateTo(_maxExtent, curve: Curves.easeOutQuart);
    unawaited(_successController.forward(from: 0));
    HapticFeedback.heavyImpact();

    final ok = await widget.onComplete();
    if (!mounted) return;

    if (ok) {
      setState(() {
        _succeeded = true;
        _completing = false;
      });
      // Brief hold so the check animation is visible before list refresh.
      await Future<void>.delayed(const Duration(milliseconds: 380));
      return;
    }

    setState(() => _completing = false);
    _armed = false;
    _successController.reset();
    await _animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxExtent = math.max(constraints.maxWidth, 1);
        final progress = _progress;

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Green pay-track revealed behind the card.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _trackGreen,
                        Color.lerp(_trackGreen, _trackGreenSoft, progress)!,
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Progress fill glow.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress.clamp(0.08, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.18),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            AnimatedBuilder(
                              animation: _successController,
                              builder: (context, _) {
                                final burst = Curves.elasticOut.transform(
                                  _successController.value.clamp(0.0, 1.0),
                                );
                                final scale = _succeeded || _completing
                                    ? 0.85 + (0.35 * burst)
                                    : 0.75 + (0.45 * progress);
                                return Transform.scale(
                                  scale: scale,
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2 + (0.25 * progress),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 20 + (4 * progress),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Opacity(
                                opacity: (0.35 + progress * 0.65).clamp(0.0, 1.0),
                                child: Text(
                                  _succeeded
                                      ? 'Completed'
                                      : _completing
                                          ? 'Completing…'
                                          : progress >= widget.confirmationFraction
                                              ? 'Release to complete'
                                              : widget.label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Draggable card surface.
              GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onHorizontalDragStart: (_) {
                  if (_completing || _succeeded) return;
                  _settleController.stop();
                },
                onHorizontalDragUpdate: (details) {
                  if (_completing || _succeeded) return;
                  final next = (_dragExtent + details.delta.dx)
                      .clamp(0.0, _maxExtent);
                  final crossed = !_armed &&
                      next / _maxExtent >= widget.confirmationFraction;
                  setState(() => _dragExtent = next);
                  if (crossed) {
                    _armed = true;
                    HapticFeedback.selectionClick();
                  } else if (next / _maxExtent <
                      widget.confirmationFraction * 0.85) {
                    _armed = false;
                  }
                },
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: () {
                  if (_completing || _succeeded) return;
                  _armed = false;
                  unawaited(_animateTo(0));
                },
                child: Transform.translate(
                  offset: Offset(_dragExtent, 0),
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SelectedTaskBadge extends StatelessWidget {
  const _SelectedTaskBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.near_me_rounded, size: 10, color: Color(0xFF2563EB)),
          SizedBox(width: 3),
          Text(
            'Selected',
            style: TextStyle(
              color: Color(0xFF2563EB),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double maxWidth;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.maxWidth = 120,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: kTaskMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: kTaskMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}

class TaskSummaryStatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  const TaskSummaryStatCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kTaskBorder),
        boxShadow: const [
          BoxShadow(
            color: kTaskSoftShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: kTaskNavy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: kTaskMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TaskHelpBanner extends StatelessWidget {
  final VoidCallback? onChat;

  const TaskHelpBanner({super.key, this.onChat});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/Good going.jpg',
              width: 54,
              height: 54,
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.4),
              errorBuilder: (_, __, ___) => Container(
                width: 54,
                height: 54,
                color: const Color(0xFFDBEAFE),
                child: const Icon(Icons.support_agent, color: kTaskNavy),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need Help with a Task?',
                  style: TextStyle(
                    color: kTaskNavy,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Our experts are here to support you at every step.',
                  style: TextStyle(
                    color: kTaskMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: kTaskNavy,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onChat,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'Chat with\nExpert',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
