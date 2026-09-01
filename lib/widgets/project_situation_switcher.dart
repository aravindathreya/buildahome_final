import 'package:flutter/material.dart';

import '../app_theme.dart';

enum ProjectSituationTab { focus, timeline }

/// Compact Focus / Timeline switcher shared by both screens.
class ProjectSituationSwitcher extends StatelessWidget
    implements PreferredSizeWidget {
  final ProjectSituationTab selected;
  final ValueChanged<ProjectSituationTab> onChanged;

  const ProjectSituationSwitcher({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _TabChip(
              label: 'Focus',
              selected: selected == ProjectSituationTab.focus,
              onTap: () => onChanged(ProjectSituationTab.focus),
            ),
            _TabChip(
              label: 'Timeline',
              selected: selected == ProjectSituationTab.timeline,
              onTap: () => onChanged(ProjectSituationTab.timeline),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: selected ? AppTheme.navy : const Color(0xFF6B7280),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
