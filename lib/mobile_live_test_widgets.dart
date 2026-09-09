import 'package:flutter/material.dart';

import 'app_theme.dart';

const Color kWorkflowActionInk = Color(0xFF1B254B);

class MobileLiveTestPanel extends StatelessWidget {
  final Widget child;

  const MobileLiveTestPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MobileLiveTestMetaLine extends StatelessWidget {
  final String label;
  final String value;

  const MobileLiveTestMetaLine({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          color: AppTheme.navySoft,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class MobileLiveTestInfoBanner extends StatelessWidget {
  final String message;

  const MobileLiveTestInfoBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class MobileLiveTestErrorBanner extends StatelessWidget {
  final String message;

  const MobileLiveTestErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF9F1239),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class MobileLiveTestWarningBanner extends StatelessWidget {
  final String message;

  const MobileLiveTestWarningBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MobileLiveTestActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool loading;

  const MobileLiveTestActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    this.foregroundColor = Colors.white,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withOpacity(0.45),
          disabledForegroundColor: foregroundColor.withOpacity(0.85),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor,
                ),
              )
            : Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
      ),
    );
  }
}

Color mobileLiveTestActionColor(MobileLiveTestActionStyle style) {
  switch (style) {
    case MobileLiveTestActionStyle.positive:
      return const Color(0xFF16A34A);
    case MobileLiveTestActionStyle.negative:
      return const Color(0xFFDC2626);
    case MobileLiveTestActionStyle.neutral:
      return AppTheme.navy;
  }
}

enum MobileLiveTestActionStyle { positive, negative, neutral }

MobileLiveTestActionStyle actionStyleForOption({
  required String decision,
  required String kind,
}) {
  if (decision == 'approve' || decision == 'yes' || kind == 'yes') {
    return MobileLiveTestActionStyle.positive;
  }
  if (decision == 'reject' || decision == 'no' || kind == 'no') {
    return MobileLiveTestActionStyle.negative;
  }
  return MobileLiveTestActionStyle.neutral;
}

/// Section header matching My Tasks workflow actions row.
class MobileLiveTestSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const MobileLiveTestSectionHeader({
    super.key,
    required this.title,
    this.icon = Icons.auto_awesome_motion_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: kWorkflowActionInk),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: kWorkflowActionInk,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }
}

class WorkflowActionChipMeta {
  final String defaultLabel;
  final IconData icon;
  final Color color;
  final bool outlined;

  const WorkflowActionChipMeta({
    required this.defaultLabel,
    required this.icon,
    required this.color,
    this.outlined = false,
  });
}

WorkflowActionChipMeta workflowActionChipMeta(String type) {
  const success = Color(0xFF047857);
  const warn = Color(0xFFB45309);
  const info = AppTheme.accentBlue;
  const primary = AppTheme.primaryColorConst;
  const secondary = AppTheme.navySoft;
  const tertiary = Color(0xFF334155);

  switch (type) {
    case 'upload':
      return WorkflowActionChipMeta(
        defaultLabel: 'Upload file',
        icon: Icons.upload_file,
        color: warn,
      );
    case 'complete_button':
      return WorkflowActionChipMeta(
        defaultLabel: 'Complete task',
        icon: Icons.check_circle,
        color: success,
      );
    case 'update_status':
      return WorkflowActionChipMeta(
        defaultLabel: 'Update status',
        icon: Icons.sync,
        color: info,
      );
    case 'yes_no':
      return WorkflowActionChipMeta(
        defaultLabel: 'Yes / no',
        icon: Icons.rule,
        color: secondary,
      );
    case 'checklist':
      return WorkflowActionChipMeta(
        defaultLabel: 'Checklist',
        icon: Icons.checklist,
        color: primary,
      );
    case 'user_checklist':
      return WorkflowActionChipMeta(
        defaultLabel: 'User checklist',
        icon: Icons.playlist_add_check,
        color: secondary,
      );
    case 'user_checklist_followup':
      return WorkflowActionChipMeta(
        defaultLabel: 'Checklist follow-up',
        icon: Icons.assignment_turned_in_outlined,
        color: info,
      );
    case 'slot_selection':
      return WorkflowActionChipMeta(
        defaultLabel: 'Select slots',
        icon: Icons.event_available_outlined,
        color: info,
      );
    case 'slot_confirmation':
      return WorkflowActionChipMeta(
        defaultLabel: 'Confirm slot',
        icon: Icons.event_available_outlined,
        color: success,
      );
    case 'kyp_material_shift':
      return WorkflowActionChipMeta(
        defaultLabel: 'Shift material',
        icon: Icons.move_up_outlined,
        color: tertiary,
      );
    case 'text_list':
      return WorkflowActionChipMeta(
        defaultLabel: 'Material request',
        icon: Icons.format_list_bulleted,
        color: info,
      );
    case 'picture_choice_list':
      return WorkflowActionChipMeta(
        defaultLabel: 'Picture choices',
        icon: Icons.photo_library_outlined,
        color: info,
      );
    case 'picture_choice_pick':
      return WorkflowActionChipMeta(
        defaultLabel: 'Choose picture',
        icon: Icons.image_outlined,
        color: primary,
      );
    case 'view_prior_response':
    case 'yes_no_summary':
    case 'user_checklist_summary':
    case 'text_list_summary':
    case 'material_shift_summary':
      return WorkflowActionChipMeta(
        defaultLabel: 'View response',
        icon: Icons.visibility_outlined,
        color: AppTheme.mutedGrey,
        outlined: true,
      );
    default:
      return WorkflowActionChipMeta(
        defaultLabel: 'Action',
        icon: Icons.touch_app_outlined,
        color: AppTheme.mutedGrey,
        outlined: true,
      );
  }
}

/// Chip button styled like production `_ActionChipButton`.
class MobileLiveTestWorkflowActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isOutlined;
  final bool isLoading;
  final VoidCallback? onPressed;
  final bool visuallyDisabled;

  const MobileLiveTestWorkflowActionChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.isOutlined = false,
    this.isLoading = false,
    this.onPressed,
    this.visuallyDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || visuallyDisabled;
    final effectiveColor = disabled ? AppTheme.mutedGrey : color;
    final isPrimary = !isOutlined && !disabled;
    final fillColor = isPrimary
        ? effectiveColor.withValues(alpha: 0.12)
        : Colors.white;
    final contentColor = isPrimary ? effectiveColor : kWorkflowActionInk;
    final iconColor = isPrimary ? effectiveColor : effectiveColor;

    return Opacity(
      opacity: disabled ? 0.62 : 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isPrimary
                      ? effectiveColor.withValues(alpha: 0.28)
                      : AppTheme.border,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: AppTheme.softShadow,
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      ),
                    )
                  else
                    Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: contentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet frame matching production workflow action sheets.
class MobileLiveTestBottomSheetFrame extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const MobileLiveTestBottomSheetFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.circular(22),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.getPrimaryColor(context).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color: AppTheme.getPrimaryColor(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: AppTheme.getTextSecondary(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
