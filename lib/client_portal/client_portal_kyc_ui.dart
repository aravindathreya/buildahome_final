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
      iconBg: Color(0xFFECFDF5),
      iconFg: Color(0xFF059669),
    );
  }
  if (key.contains('pan') || name.contains('pan')) {
    return const KycDocVisual(
      icon: Icons.credit_card_outlined,
      iconBg: Color(0xFFEFF6FF),
      iconFg: Color(0xFF2563EB),
    );
  }
  if (key.contains('sale') || name.contains('sale deed')) {
    return const KycDocVisual(
      icon: Icons.home_work_outlined,
      iconBg: Color(0xFFF3E8FF),
      iconFg: Color(0xFF9333EA),
    );
  }
  if (key.contains('ec') || name.contains('ec')) {
    return const KycDocVisual(
      icon: Icons.receipt_long_outlined,
      iconBg: Color(0xFFFFF7ED),
      iconFg: Color(0xFFEA580C),
    );
  }
  if (key.contains('khata') || name.contains('khata')) {
    return const KycDocVisual(
      icon: Icons.article_outlined,
      iconBg: Color(0xFFECFEFF),
      iconFg: Color(0xFF0891B2),
    );
  }
  if (key.contains('photo') || name.contains('photograph')) {
    return const KycDocVisual(
      icon: Icons.photo_camera_outlined,
      iconBg: Color(0xFFFDF2F8),
      iconFg: Color(0xFFDB2777),
    );
  }
  return const KycDocVisual(
    icon: Icons.description_outlined,
    iconBg: Color(0xFFF0F4FF),
    iconFg: AppTheme.navy,
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
            Color(0xFFEFF6FF),
            Color(0xFFF5F3FF),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDBEAFE)),
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
                  color: const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  complete ? Icons.verified_user_rounded : Icons.shield_outlined,
                  color: const Color(0xFF7C3AED),
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
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
                  : const Color(0xFFDBEAFE),
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
            Color(0xFFECFDF5),
            Color(0xFFD1FAE5),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Color(0xFF059669),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All mandatory documents uploaded',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.navy,
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
            color: Color(0xFF059669),
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
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF059669)),
          SizedBox(width: 4),
          Text(
            'Uploaded',
            style: TextStyle(
              color: Color(0xFF059669),
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navy,
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
