import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

/// Full-screen gate while Chat V1 loads its first project conversations.
/// Matches [OpeningProjectGate]: solid navy, white logo, ring spinner.
class ChatV1OpeningSplash extends StatelessWidget {
  final String? subtitle;

  const ChatV1OpeningSplash({
    super.key,
    this.subtitle,
  });

  static const Color _navy = Color(0xFF1B254B);

  @override
  Widget build(BuildContext context) {
    final line = (subtitle ?? '').trim();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _navy,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/LOGO WHITE.png',
                height: 56,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => const Text(
                  'buildAhome',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'buildAhome Chat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 28),
              const SpinKitRing(
                color: Colors.white,
                size: 36,
                lineWidth: 2.5,
              ),
              const SizedBox(height: 22),
              Text(
                line.isNotEmpty ? line : 'Opening chat…',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
