import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'client_portal_document_ui.dart';

/// Per-document icon and color for the KYC checklist (reference design).
class KycDocVisual {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;

  const KycDocVisual({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
  });
}

KycDocVisual kycDocVisualFor({required String docKey, required String label}) {
  final key = docKey.toLowerCase();
  final name = label.toLowerCase();

  if (key.contains('aadhar') || key.contains('aadhaar') || name.contains('aadhaar')) {
    return const KycDocVisual(
      icon: Icons.badge_outlined,
      iconBg: Color(0xFF143028),
      iconFg: Color(0xFF34D399),
    );
  }
  if (key.contains('pan') || name.contains('pan')) {
    return const KycDocVisual(
      icon: Icons.credit_card_outlined,
      iconBg: Color(0xFF241A33),
      iconFg: Color(0xFFC4B5FD),
    );
  }
  if (key.contains('sale') || name.contains('sale deed')) {
    return const KycDocVisual(
      icon: Icons.home_work_outlined,
      iconBg: Color(0xFF241A33),
      iconFg: Color(0xFFC4B5FD),
    );
  }
  if (key == 'ec' ||
      key.startsWith('ec_') ||
      name.contains('encumbrance') ||
      name.contains('ec (')) {
    return const KycDocVisual(
      icon: Icons.receipt_long_outlined,
      iconBg: Color(0xFF2A2112),
      iconFg: Color(0xFFFBBF24),
    );
  }
  if (key.contains('khata') || name.contains('khata')) {
    return const KycDocVisual(
      icon: Icons.article_outlined,
      iconBg: Color(0xFF142830),
      iconFg: Color(0xFF67E8F9),
    );
  }
  if (key.contains('tax') || name.contains('tax')) {
    return const KycDocVisual(
      icon: Icons.receipt_outlined,
      iconBg: Color(0xFF2A2112),
      iconFg: Color(0xFFFBBF24),
    );
  }
  if (key.contains('layout') || name.contains('layout')) {
    return const KycDocVisual(
      icon: Icons.map_outlined,
      iconBg: Color(0xFF2A2040),
      iconFg: Color(0xFFC4B5FD),
    );
  }
  if (key.contains('photo') || name.contains('photograph')) {
    return const KycDocVisual(
      icon: Icons.photo_camera_outlined,
      iconBg: Color(0xFF2A1624),
      iconFg: Color(0xFFF9A8D4),
    );
  }
  return KycDocVisual(
    icon: Icons.description_outlined,
    iconBg: Color(0xFF2A2040),
    iconFg: AppTheme.darkTextPrimary,
  );
}

class KycStatusCard extends StatelessWidget {
  final int done;
  final int total;

  const KycStatusCard({
    super.key,
    required this.done,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final safeTotal = total <= 0 ? 0 : total;
    final safeDone = safeTotal == 0 ? 0 : done.clamp(0, safeTotal);
    final complete = safeTotal > 0 && safeDone >= safeTotal;
    final progress = safeTotal == 0 ? 0.0 : safeDone / safeTotal;
    final pct = safeTotal == 0 ? 0 : (progress * 100).round().clamp(0, 100);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF241A33),
            Color(0xFF241A33),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF3A2A55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2040),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  complete ? Icons.verified_user_rounded : Icons.shield_outlined,
                  color: const Color(0xFFC4B5FD),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      complete ? 'KYC Completed' : 'KYC In Progress',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.darkTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$safeDone of $safeTotal mandatory documents uploaded',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.getTextSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SegmentedProgress(
                  total: safeTotal == 0 ? 1 : safeTotal,
                  filled: safeDone,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ClientPortalDocTheme.accentBlue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: ClientPortalDocTheme.accentBlue.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '$pct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentedProgress extends StatelessWidget {
  final int total;
  final int filled;

  const _SegmentedProgress({required this.total, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (index) {
        final isFilled = index < filled;
        return Expanded(
          child: Container(
            height: 8,
            margin: EdgeInsets.only(right: index < total - 1 ? 4 : 0),
            decoration: BoxDecoration(
              color: isFilled
                  ? ClientPortalDocTheme.accentBlue
                  : const Color(0xFF3A2A55),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}

class KycSuccessBanner extends StatelessWidget {
  const KycSuccessBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF143028),
            Color(0xFF143028),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF065F46)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF34D399).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Color(0xFF34D399),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All mandatory documents uploaded',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.darkTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Thank you! Your documents are under review.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.folder_open_rounded,
            color: Color(0xFF34D399),
            size: 36,
          ),
        ],
      ),
    );
  }
}

class KycUploadedBadge extends StatelessWidget {
  const KycUploadedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF143028),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF065F46)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF34D399)),
          SizedBox(width: 4),
          Text(
            'Uploaded',
            style: TextStyle(
              color: Color(0xFF34D399),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class KycDetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String label;
  final String value;

  const KycDetailRow({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconFg, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkTextPrimary,
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
