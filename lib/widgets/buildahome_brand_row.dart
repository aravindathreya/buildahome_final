import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Compact logo + wordmark used on dashboard surfaces.
class BuildAhomeBrandRow extends StatefulWidget {
  final double logoHeight;
  final double fontSize;
  final Color? color;
  final EdgeInsetsGeometry padding;

  const BuildAhomeBrandRow({
    super.key,
    this.logoHeight = 28,
    this.fontSize = 18,
    this.color,
    this.padding = const EdgeInsets.only(bottom: 14),
  });

  @override
  State<BuildAhomeBrandRow> createState() => _BuildAhomeBrandRowState();
}

class _BuildAhomeBrandRowState extends State<BuildAhomeBrandRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppTheme.darkTextPrimary;
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          'assets/images/Logos/Hands Sheltering a Home Icon.png',
          height: widget.logoHeight,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Icon(
            Icons.home_rounded,
            color: color,
            size: widget.logoHeight * 0.9,
          ),
        ),
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'buildAhome',
                style: TextStyle(
                  color: color,
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.0,
                ),
              ),
              WidgetSpan(
                alignment: PlaceholderAlignment.top,
                child: Transform.translate(
                  offset: Offset(1, -widget.fontSize * 0.28),
                  child: Text(
                    'TM',
                    style: TextStyle(
                      color: color.withValues(alpha: 0.78),
                      fontSize: widget.fontSize * 0.42,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: widget.padding,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, child) {
          final t = _progress.value;
          // Soft leading edge so content fades in left → right.
          final softEdge = 0.22;
          final opaqueEnd = t.clamp(0.0, 1.0);
          final fadeEnd = (t + softEdge).clamp(0.0, 1.0);
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [
                  0.0,
                  opaqueEnd,
                  fadeEnd,
                ],
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: brand,
      ),
    );
  }
}
