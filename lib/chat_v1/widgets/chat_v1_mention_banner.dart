import 'package:flutter/material.dart';

import '../chat_v1_theme.dart';

class Cv1MentionBanner extends StatelessWidget {
  final VoidCallback onTap;

  const Cv1MentionBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? const Color(0xFF7DE5A8) : const Color(0xFF157A42);
    return Material(
      color: ChatV1Theme.accentSoft,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.alternate_email_rounded, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('You were tagged',
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w600)),
              ),
              Text('View message',
                  style: TextStyle(color: color, fontSize: 12)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_downward_rounded, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
