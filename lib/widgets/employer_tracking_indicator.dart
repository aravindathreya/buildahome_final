import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/staff_location_tracker.dart';

/// Shown while a checked-in staff member's location is shared with the employer.
class EmployerTrackingIndicator extends StatelessWidget {
  final bool onDark;

  const EmployerTrackingIndicator({super.key, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: StaffLocationTracker.instance.tracking,
      builder: (context, tracking, _) {
        if (!tracking) return const SizedBox.shrink();
        // onDark means the chip sits on the navy dashboard card.
        // Otherwise follow the app theme so dark mode does not paint
        // near-white text on the pale mint chip.
        final themeDark = !onDark && AppTheme.isDark;
        final background = onDark
            ? Colors.white.withValues(alpha: 0.16)
            : themeDark
                ? const Color(0xFF064E3B)
                : const Color(0xFFECFDF5);
        final foreground = onDark
            ? Colors.white
            : themeDark
                ? const Color(0xFFA7F3D0)
                : const Color(0xFF047857);
        final borderColor = themeDark
            ? const Color(0xFF047857)
            : const Color(0xFFA7F3D0);
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(999),
              border: onDark ? null : Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _LiveDot(),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Location tracked by employer',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFF10B981),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
