import 'package:flutter/material.dart';

import '../app_theme.dart';

const String offScheduleCheckInNote = 'Off schedule check-in';

String offScheduleCheckInNoteFor({required bool locationOverridden}) {
  if (!locationOverridden) return offScheduleCheckInNote;
  return 'Off schedule check-in. Location overridden.';
}

/// Collects an attendance note. Returns null when dismissed.
/// An empty string means the user confirmed without a note.
Future<String?> showAttendanceNoteSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String confirmLabel,
  required bool requireNote,
  String? initialNote,
  String? emptyNoteMessage,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _AttendanceNoteSheet(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      requireNote: requireNote,
      initialNote: initialNote,
      emptyNoteMessage: emptyNoteMessage,
    ),
  );
}

class _AttendanceNoteSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String confirmLabel;
  final bool requireNote;
  final String? initialNote;
  final String? emptyNoteMessage;

  const _AttendanceNoteSheet({
    required this.title,
    required this.subtitle,
    required this.confirmLabel,
    required this.requireNote,
    this.initialNote,
    this.emptyNoteMessage,
  });

  @override
  State<_AttendanceNoteSheet> createState() => _AttendanceNoteSheetState();
}

class _AttendanceNoteSheetState extends State<_AttendanceNoteSheet> {
  late final TextEditingController _noteController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final note = _noteController.text.trim();
    if (widget.requireNote && note.isEmpty) {
      setState(() {
        _error = widget.emptyNoteMessage ??
            'Add a note to override your location.';
      });
      return;
    }
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8ECF1),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: const TextStyle(
              color: AppTheme.navy,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.subtitle,
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _noteController,
            autofocus: widget.requireNote &&
                (widget.initialNote == null || widget.initialNote!.isEmpty),
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: widget.requireNote ? 'Note' : 'Note (optional)',
              hintText: widget.requireNote
                  ? 'Why are you checking in from this location?'
                  : 'Anything your team should know',
              alignLabelWithHint: true,
              errorText: _error,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE8ECF1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE8ECF1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.navy, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.navy,
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: Color(0xFFE8ECF1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.navy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    widget.confirmLabel,
                    style: const TextStyle(fontWeight: FontWeight.w800),
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
