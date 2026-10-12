import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_theme.dart';

class FloatingGlassBottomNavItem {
  const FloatingGlassBottomNavItem({
    required this.activeIcon,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.disabled = false,
  });

  final IconData activeIcon;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool disabled;
}

/// Floating, frosted glass bottom navigation bar.
class FloatingGlassBottomNav extends StatelessWidget {
  const FloatingGlassBottomNav({
    super.key,
    required this.items,
    this.navKey,
  });

  final List<FloatingGlassBottomNavItem> items;
  final Key? navKey;

  /// Screen edge padding; +20 each side vs the original 16 to narrow the bar.
  static const double _horizontalInset = 36;
  static const double _bottomInset = 10;
  static const double _barRadius = 28;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: _bottomInset),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          _horizontalInset,
          0,
          _horizontalInset,
          0,
        ),
        child: DecoratedBox(
          key: navKey,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_barRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.28 : 0.08),
                blurRadius: dark ? 24 : 16,
                offset: Offset(0, dark ? 10 : 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_barRadius),
            child: _barSurface(
              dark: dark,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_barRadius),
                  color: dark
                      ? AppTheme.darkBackgroundSecondary.withValues(alpha: 0.72)
                      : Colors.white,
                  border: Border.all(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.12)
                        : AppTheme.border,
                  ),
                  gradient: dark
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.10),
                            Colors.white.withValues(alpha: 0.02),
                          ],
                        )
                      : null,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  children: List.generate(items.length, (index) {
                    final item = items[index];
                    final color = item.disabled
                        ? const Color(0xFF6B7280)
                        : (item.selected
                            ? (dark ? Colors.white : AppTheme.navy)
                            : (dark
                                ? AppTheme.mutedGrey
                                : const Color(0xFF4B5568)));
                    return Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: item.onTap,
                          borderRadius: BorderRadius.circular(18),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.selected
                                      ? item.activeIcon
                                      : item.icon,
                                  color: color,
                                  size: 24,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 10.5,
                                    fontWeight: item.selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _barSurface({required bool dark, required Widget child}) {
    if (!dark) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: child,
    );
  }
}
